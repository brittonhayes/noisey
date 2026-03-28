use crate::noise::{Biquad, CreekBrook, NightWind, OceanSurf, SoundSource, WarmRain, SAMPLE_RATE};
use crate::state::AudioCommand;
use std::collections::HashMap;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;
use tracing::{error, info, warn};

/// A decoded audio file stored as interleaved f32 samples.
struct DecodedAudio {
    samples: Vec<f32>,
    channels: u16,
}

/// An active sound being played — either procedural or file-based.
enum ActiveSource {
    /// Procedural noise generator (infinite iterator).
    Procedural(Box<dyn SoundSource>),
    /// File-based sound that loops. `position` tracks current sample index.
    File {
        audio: Arc<DecodedAudio>,
        position: usize,
    },
}

impl ActiveSource {
    /// Fill `buf` with the next samples (mono, at SAMPLE_RATE).
    fn fill(&mut self, buf: &mut [f32]) {
        match self {
            ActiveSource::Procedural(source) => {
                for sample in buf.iter_mut() {
                    *sample = source.next().unwrap_or(0.0);
                }
            }
            ActiveSource::File { audio, position } => {
                let ch = audio.channels as usize;
                for sample in buf.iter_mut() {
                    if audio.samples.is_empty() {
                        *sample = 0.0;
                        continue;
                    }
                    let mut mono = 0.0;
                    for c in 0..ch {
                        let idx = (*position + c) % audio.samples.len();
                        mono += audio.samples[idx];
                    }
                    mono /= ch as f32;
                    *sample = mono;
                    *position = (*position + ch) % audio.samples.len();
                }
            }
        }
    }
}

/// Smoothly interpolates toward a target value to avoid clicks/pops.
struct SmoothedValue {
    current: f32,
    target: f32,
    /// Per-sample coefficient (0..1). Higher = faster. ~0.001 ≈ 10ms at 44100Hz.
    coeff: f32,
}

impl SmoothedValue {
    fn new(initial: f32, coeff: f32) -> Self {
        Self {
            current: initial,
            target: initial,
            coeff,
        }
    }

    fn set(&mut self, target: f32) {
        self.target = target;
    }

    /// Advance one sample and return the smoothed value.
    fn next(&mut self) -> f32 {
        self.current += self.coeff * (self.target - self.current);
        self.current
    }

    fn is_settled(&self) -> bool {
        (self.current - self.target).abs() < 1e-6
    }
}

/// Fade-in duration in samples (~1.5s at 44100Hz) — graceful swell.
const FADE_IN_SAMPLES: usize = 66150;
/// Fade-out duration in samples (~0.5s at 44100Hz).
const FADE_OUT_SAMPLES: usize = 22050;

struct ActiveSound {
    source: ActiveSource,
    volume: SmoothedValue,
    /// Fade envelope: ramps 0→1 on start, 1→0 on stop.
    fade: f32,
    fade_delta: f32,
    /// Marked for removal once fade-out completes.
    pending_remove: bool,
}

/// Per-sample smoothing coefficient (~5ms at 44100Hz).
const SMOOTH_COEFF: f32 = 1.0 / (0.005 * SAMPLE_RATE as f32);

/// Hardcoded warmth level (40%).
const WARMTH: f32 = 0.4;

/// Shared state between the command-processing loop and the audio callback.
struct MixerState {
    sounds: HashMap<String, ActiveSound>,
    master_volume: SmoothedValue,
    warmth_filter_l: Biquad,
    warmth_filter_r: Biquad,
}

/// Map warmth parameter (0.0-1.0) to filter cutoff frequency.
fn warmth_to_cutoff(warmth: f32) -> f32 {
    // Exponential mapping: 0.0 -> 20000Hz, 1.0 -> 300Hz
    300.0 * (20000.0_f32 / 300.0).powf(1.0 - warmth)
}

/// Spawn the audio engine on a dedicated thread.
/// Returns a receiver that sends the actual simulation mode (may differ from requested if device fails).
pub fn spawn_audio_thread(
    sounds_dir: PathBuf,
    rx: mpsc::Receiver<AudioCommand>,
    simulate: bool,
) -> std::sync::mpsc::Receiver<bool> {
    let (sim_tx, sim_rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        if let Err(e) = run_audio_engine(sounds_dir, rx, simulate, sim_tx) {
            error!("Audio engine failed: {e}");
        }
    });
    sim_rx
}

fn run_audio_engine(
    sounds_dir: PathBuf,
    mut rx: mpsc::Receiver<AudioCommand>,
    simulate: bool,
    sim_tx: std::sync::mpsc::Sender<bool>,
) -> Result<(), Box<dyn std::error::Error>> {
    let warmth_cutoff = warmth_to_cutoff(WARMTH);
    let mixer = Arc::new(Mutex::new(MixerState {
        sounds: HashMap::new(),
        master_volume: SmoothedValue::new(0.8, SMOOTH_COEFF),
        warmth_filter_l: Biquad::low_pass(warmth_cutoff, 0.707),
        warmth_filter_r: Biquad::low_pass(warmth_cutoff, 0.707),
    }));

    let _device = if simulate {
        info!("Audio engine: running in simulation mode (no audio hardware)");
        let _ = sim_tx.send(true);
        None
    } else {
        match try_open_device(Arc::clone(&mixer)) {
            Some(dev) => {
                info!("Audio engine: playback device opened (miniaudio)");
                let _ = sim_tx.send(false);
                Some(dev)
            }
            None => {
                warn!("Audio engine: failed to open playback device, falling back to simulation mode");
                let _ = sim_tx.send(true);
                None
            }
        }
    };

    if _device.is_none() {
        let mixer_for_sim = Arc::clone(&mixer);
        std::thread::spawn(move || {
            let frame_size = 1024usize;
            let sleep_dur = std::time::Duration::from_micros(
                (frame_size as u64 * 1_000_000) / SAMPLE_RATE as u64,
            );
            let mut buf = vec![0.0f32; frame_size];
            loop {
                std::thread::sleep(sleep_dur);
                if let Ok(mut state) = mixer_for_sim.lock() {
                    for active in state.sounds.values_mut() {
                        active.source.fill(&mut buf);
                    }
                }
            }
        });
    }

    process_commands(&mixer, &sounds_dir, &mut rx);

    info!("Audio engine: shutting down");
    Ok(())
}

fn try_open_device(mixer: Arc<Mutex<MixerState>>) -> Option<miniaudio::Device> {
    let mut device_config = miniaudio::DeviceConfig::new(miniaudio::DeviceType::Playback);
    device_config
        .playback_mut()
        .set_format(miniaudio::Format::F32);
    device_config.playback_mut().set_channels(2);
    device_config.set_sample_rate(SAMPLE_RATE);

    device_config.set_data_callback(move |_device, output, _input| {
        let output_f32 = output.as_samples_mut::<f32>();
        for s in output_f32.iter_mut() {
            *s = 0.0;
        }

        let mut state = match mixer.lock() {
            Ok(s) => s,
            Err(_) => return,
        };

        if state.sounds.is_empty() && state.master_volume.is_settled() {
            return;
        }

        let frame_count = output_f32.len() / 2;
        let mut mono_buf = vec![0.0f32; frame_count];

        // Pre-compute per-frame master volume ramp to avoid borrow conflict
        let mut master_ramp = Vec::with_capacity(frame_count);
        for _ in 0..frame_count {
            master_ramp.push(state.master_volume.next());
        }

        for active in state.sounds.values_mut() {
            active.source.fill(&mut mono_buf);
            for (i, &sample) in mono_buf.iter().enumerate() {
                let vol = active.volume.next();
                let fade = (active.fade + active.fade_delta).clamp(0.0, 1.0);
                active.fade = fade;
                let scaled = sample * vol * fade * master_ramp[i];
                output_f32[i * 2] += scaled;
                output_f32[i * 2 + 1] += scaled;
            }
        }

        // Remove sounds whose fade-out has completed
        state
            .sounds
            .retain(|_, active| !(active.pending_remove && active.fade <= 0.0));

        // Apply warmth filter (post-mix, pre-clamp)
        for i in 0..frame_count {
            output_f32[i * 2] = state.warmth_filter_l.process(output_f32[i * 2]);
            output_f32[i * 2 + 1] = state.warmth_filter_r.process(output_f32[i * 2 + 1]);
        }

        for s in output_f32.iter_mut() {
            *s = s.clamp(-1.0, 1.0);
        }
    });

    let device = miniaudio::Device::new(None, &device_config).ok()?;
    device.start().ok()?;
    Some(device)
}

fn process_commands(
    mixer: &Arc<Mutex<MixerState>>,
    sounds_dir: &Path,
    rx: &mut mpsc::Receiver<AudioCommand>,
) {
    let mut file_cache: HashMap<String, Arc<DecodedAudio>> = HashMap::new();

    while let Some(cmd) = rx.blocking_recv() {
        let mut state = mixer.lock().unwrap();
        match cmd {
            AudioCommand::Play { id } => {
                state.sounds.remove(&id);

                let source = match id.as_str() {
                    "ocean-surf" => Some(ActiveSource::Procedural(Box::new(OceanSurf::new()))),
                    "warm-rain" => Some(ActiveSource::Procedural(Box::new(WarmRain::new()))),
                    "creek" => Some(ActiveSource::Procedural(Box::new(CreekBrook::new()))),
                    "night-wind" => Some(ActiveSource::Procedural(Box::new(NightWind::new()))),
                    _ => {
                        let audio = file_cache.get(&id).cloned().or_else(|| {
                            let decoded = load_sound_file(sounds_dir, &id)?;
                            let arc = Arc::new(decoded);
                            file_cache.insert(id.clone(), Arc::clone(&arc));
                            Some(arc)
                        });

                        audio.map(|a| ActiveSource::File {
                            audio: a,
                            position: 0,
                        })
                    }
                };

                match source {
                    Some(src) => {
                        state.sounds.insert(
                            id.clone(),
                            ActiveSound {
                                source: src,
                                volume: SmoothedValue::new(1.0, SMOOTH_COEFF),
                                fade: 0.0,
                                fade_delta: 1.0 / FADE_IN_SAMPLES as f32,
                                pending_remove: false,
                            },
                        );
                        info!(sound = %id, "Audio engine: started playback (fade in)");
                    }
                    None => {
                        warn!(sound = %id, "Audio engine: sound not found");
                    }
                }
            }
            AudioCommand::Stop { id } => {
                if let Some(active) = state.sounds.get_mut(&id) {
                    active.fade_delta = -1.0 / FADE_OUT_SAMPLES as f32;
                    active.pending_remove = true;
                    info!(sound = %id, "Audio engine: fading out");
                }
            }
            AudioCommand::SetMasterVolume(vol) => {
                state.master_volume.set(vol);
            }
            AudioCommand::StopAll => {
                let count = state.sounds.len();
                for (_id, active) in state.sounds.iter_mut() {
                    active.fade_delta = -1.0 / FADE_OUT_SAMPLES as f32;
                    active.pending_remove = true;
                }
                info!(count = count, "Audio engine: fading out all sounds");
            }
        }
    }
}

fn load_sound_file(sounds_dir: &Path, id: &str) -> Option<DecodedAudio> {
    for ext in &["wav", "ogg"] {
        let path = sounds_dir.join(format!("{id}.{ext}"));
        if path.exists() {
            return decode_file(&path);
        }
    }

    if let Ok(entries) = std::fs::read_dir(sounds_dir) {
        for entry in entries.flatten() {
            let file_name = entry.file_name();
            let name = file_name.to_string_lossy();
            let stem = Path::new(&*name)
                .file_stem()
                .map(|s| s.to_string_lossy().to_string());
            if stem.as_deref() == Some(id) {
                return decode_file(&entry.path());
            }
        }
    }

    None
}

fn decode_file(path: &Path) -> Option<DecodedAudio> {
    let ext = path.extension()?.to_str()?.to_lowercase();
    match ext.as_str() {
        "wav" => decode_wav(path),
        "ogg" => decode_ogg(path),
        _ => {
            warn!("Unsupported audio format: {ext}");
            None
        }
    }
}

fn decode_wav(path: &Path) -> Option<DecodedAudio> {
    let reader = hound::WavReader::open(path).ok()?;
    let spec = reader.spec();
    let channels = spec.channels;
    let sample_rate = spec.sample_rate;

    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => reader
            .into_samples::<f32>()
            .filter_map(|s| s.ok())
            .collect(),
        hound::SampleFormat::Int => {
            let max_val = (1u32 << (spec.bits_per_sample - 1)) as f32;
            reader
                .into_samples::<i32>()
                .filter_map(|s| s.ok())
                .map(|s| s as f32 / max_val)
                .collect()
        }
    };

    info!(
        path = %path.display(),
        channels = channels,
        sample_rate = sample_rate,
        samples = samples.len(),
        "Audio engine: decoded WAV file"
    );

    Some(DecodedAudio { samples, channels })
}

fn decode_ogg(path: &Path) -> Option<DecodedAudio> {
    let data = std::fs::read(path).ok()?;
    let cursor = Cursor::new(data);
    let mut reader = lewton::inside_ogg::OggStreamReader::new(cursor).ok()?;

    let channels = reader.ident_hdr.audio_channels as u16;
    let sample_rate = reader.ident_hdr.audio_sample_rate;

    let mut samples = Vec::new();
    while let Ok(Some(packet)) = reader.read_dec_packet_itl() {
        for sample in packet {
            samples.push(sample as f32 / 32768.0);
        }
    }

    info!(
        path = %path.display(),
        channels = channels,
        sample_rate = sample_rate,
        samples = samples.len(),
        "Audio engine: decoded OGG file"
    );

    Some(DecodedAudio { samples, channels })
}

/// Scan the sounds directory and return available file-based sound IDs.
pub fn scan_sound_files(sounds_dir: &Path) -> Vec<(String, String)> {
    let mut sounds = Vec::new();
    let valid_extensions = ["wav", "ogg"];

    if let Ok(entries) = std::fs::read_dir(sounds_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if valid_extensions.contains(&ext) {
                    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                        let id = stem.to_string();
                        let name = stem
                            .replace(['-', '_'], " ")
                            .split_whitespace()
                            .map(|w| {
                                let mut chars = w.chars();
                                match chars.next() {
                                    Some(c) => {
                                        c.to_uppercase().to_string()
                                            + &chars.as_str().to_lowercase()
                                    }
                                    None => String::new(),
                                }
                            })
                            .collect::<Vec<_>>()
                            .join(" ");
                        sounds.push((id, name));
                    }
                }
            }
        }
    }

    sounds.sort_by(|a, b| a.1.cmp(&b.1));
    sounds
}
