use crate::noise::{Biquad, CreekBrook, NightWind, OceanSurf, SoundSource, WarmRain, SAMPLE_RATE};
use crate::state::AudioCommand;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

/// A decoded audio file stored as interleaved f32 samples.
pub struct DecodedAudio {
    pub samples: Vec<f32>,
    pub channels: u16,
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

/// Crossfade duration in samples (~4s at 44100Hz) for seamless looping.
const CROSSFADE_SAMPLES: usize = SAMPLE_RATE as usize * 4;

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
                info!("Audio engine: playback device opened (cpal)");
                let _ = sim_tx.send(false);
                Some(dev)
            }
            None => {
                warn!(
                    "Audio engine: failed to open playback device, falling back to simulation mode"
                );
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

fn try_open_device(mixer: Arc<Mutex<MixerState>>) -> Option<cpal::Stream> {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

    let host = cpal::default_host();
    let device = host.default_output_device()?;

    let config = cpal::StreamConfig {
        channels: 2,
        sample_rate: cpal::SampleRate(SAMPLE_RATE),
        buffer_size: cpal::BufferSize::Default,
    };

    let stream = device
        .build_output_stream(
            &config,
            move |output_f32: &mut [f32], _: &cpal::OutputCallbackInfo| {
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
            },
            |err| {
                error!("Audio stream error: {err}");
            },
            None,
        )
        .ok()?;

    stream.play().ok()?;
    Some(stream)
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
            AudioCommand::InvalidateCache { id } => {
                file_cache.remove(&id);
                info!(sound = %id, "Audio engine: cache invalidated");
            }
        }
    }
}

/// Supported audio file extensions.
pub const AUDIO_EXTENSIONS: &[&str] = &["wav", "ogg", "mp3", "m4a", "aac", "flac"];

fn load_sound_file(sounds_dir: &Path, id: &str) -> Option<DecodedAudio> {
    for ext in AUDIO_EXTENSIONS {
        let path = sounds_dir.join(format!("{id}.{ext}"));
        if path.exists() {
            return decode_file(&path).ok();
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
                return decode_file(&entry.path()).ok();
            }
        }
    }

    None
}

/// Public wrapper for decoding a file (used by upload validation).
/// Returns a descriptive error string on failure.
pub fn decode_file_from_path(path: &Path) -> Result<DecodedAudio, String> {
    decode_file(path)
}

fn decode_file(path: &Path) -> Result<DecodedAudio, String> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .ok_or_else(|| "file has no extension".to_string())?;
    if !AUDIO_EXTENSIONS.contains(&ext.as_str()) {
        return Err(format!("unsupported audio format: {ext}"));
    }
    decode_with_symphonia(path)
}

/// Decode any supported audio file using symphonia, resample to SAMPLE_RATE if needed,
/// and bake a crossfade into the loop boundary for seamless looping.
fn decode_with_symphonia(path: &Path) -> Result<DecodedAudio, String> {
    let file = std::fs::File::open(path).map_err(|e| format!("could not open file: {e}"))?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        // Symphonia's isomp4 demuxer registers "mp4" not "m4a", so remap for probe
        let lower = ext.to_lowercase();
        let ext_hint = if lower == "m4a" { "mp4" } else { &lower };
        hint.with_extension(ext_hint);
    }

    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|e| format!("could not identify audio format: {e}"))?;

    let mut format_reader = probed.format;

    let track = format_reader
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| "no supported audio track found in file".to_string())?;

    let codec_params = track.codec_params.clone();
    let track_id = track.id;

    let channels = codec_params.channels.map(|c| c.count()).unwrap_or(1) as u16;
    let source_rate = codec_params.sample_rate.unwrap_or(SAMPLE_RATE);

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .map_err(|e| format!("unsupported codec: {e}"))?;

    let mut samples: Vec<f32> = Vec::new();
    let mut decode_errors: usize = 0;

    loop {
        let packet = match format_reader.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::IoError(ref e))
                if e.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(_) => break,
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(e) => {
                decode_errors += 1;
                if decode_errors <= 3 {
                    warn!(path = %path.display(), error = %e, "Audio decode: packet error");
                }
                continue;
            }
        };

        let spec = *decoded.spec();
        let num_frames = decoded.frames();
        let mut sample_buf = SampleBuffer::<f32>::new(num_frames as u64, spec);
        sample_buf.copy_interleaved_ref(decoded);
        samples.extend_from_slice(sample_buf.samples());
    }

    if decode_errors > 0 {
        warn!(path = %path.display(), errors = decode_errors, "Audio decode: total packet errors");
    }

    if samples.is_empty() {
        warn!(path = %path.display(), "Audio engine: decoded 0 samples");
        return Err("could not decode any audio samples from file".to_string());
    }

    // Resample if source rate differs from our engine rate
    if source_rate != SAMPLE_RATE {
        samples = resample(&samples, channels, source_rate, SAMPLE_RATE);
    }

    info!(
        path = %path.display(),
        channels = channels,
        source_rate = source_rate,
        samples = samples.len(),
        "Audio engine: decoded audio file"
    );

    // Bake crossfade for seamless looping
    samples = bake_crossfade(samples, channels);

    Ok(DecodedAudio { samples, channels })
}

/// Simple linear resampler for converting between sample rates.
fn resample(samples: &[f32], channels: u16, from_rate: u32, to_rate: u32) -> Vec<f32> {
    if from_rate == to_rate || samples.is_empty() {
        return samples.to_vec();
    }

    let ch = channels as usize;
    let num_frames_in = samples.len() / ch;
    let ratio = to_rate as f64 / from_rate as f64;
    let num_frames_out = (num_frames_in as f64 * ratio) as usize;

    let mut output = Vec::with_capacity(num_frames_out * ch);

    for i in 0..num_frames_out {
        let src_pos = i as f64 / ratio;
        let src_idx = src_pos as usize;
        let frac = src_pos - src_idx as f64;

        for c in 0..ch {
            let idx0 = (src_idx * ch + c).min(samples.len() - 1);
            let idx1 = ((src_idx + 1) * ch + c).min(samples.len() - 1);
            let s = samples[idx0] as f64 * (1.0 - frac) + samples[idx1] as f64 * frac;
            output.push(s as f32);
        }
    }

    output
}

/// Bake a crossfade into the sample buffer so looping via modulo is seamless.
/// The tail of the recording blends into the head using an equal-power cosine curve.
fn bake_crossfade(mut samples: Vec<f32>, channels: u16) -> Vec<f32> {
    let ch = channels as usize;
    let total_frames = samples.len() / ch;
    let crossfade_frames = CROSSFADE_SAMPLES.min(total_frames / 3); // don't crossfade more than 1/3

    if crossfade_frames < SAMPLE_RATE as usize / 10 {
        // Too short to crossfade meaningfully (<100ms)
        return samples;
    }

    // For each frame in the crossfade region at the end, blend with the corresponding
    // frame at the start of the recording.
    let half_pi = std::f32::consts::FRAC_PI_2;

    for i in 0..crossfade_frames {
        let t = i as f32 / crossfade_frames as f32;
        // Equal-power crossfade: tail fades out, head fades in
        let gain_out = (half_pi * (1.0 - t)).sin();
        let gain_in = (half_pi * t).sin();

        for c in 0..ch {
            let tail_idx = (total_frames - crossfade_frames + i) * ch + c;
            let head_idx = i * ch + c;
            samples[tail_idx] = samples[tail_idx] * gain_out + samples[head_idx] * gain_in;
        }
    }

    // Trim the head region that's now baked into the tail crossfade
    let trim_start = crossfade_frames * ch;
    samples.drain(..trim_start);

    samples
}

/// Scan the sounds directory and return available file-based sound IDs.
pub fn scan_sound_files(sounds_dir: &Path) -> Vec<(String, String)> {
    let mut sounds = Vec::new();

    if let Ok(entries) = std::fs::read_dir(sounds_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if AUDIO_EXTENSIONS.contains(&ext.to_lowercase().as_str()) {
                    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                        let id = stem.to_string();
                        let name = humanize_filename(stem);
                        sounds.push((id, name));
                    }
                }
            }
        }
    }

    sounds.sort_by(|a, b| a.1.cmp(&b.1));
    sounds
}

/// Convert a filename stem like "ocean-waves_costa_rica" to "Ocean Waves Costa Rica".
pub fn humanize_filename(stem: &str) -> String {
    stem.replace(['-', '_'], " ")
        .split_whitespace()
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                Some(c) => c.to_uppercase().to_string() + &chars.as_str().to_lowercase(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Compute duration in seconds for a decoded audio buffer.
pub fn duration_secs(sample_count: usize, channels: u16) -> f32 {
    let frames = sample_count / channels as usize;
    frames as f32 / SAMPLE_RATE as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_humanize_filename() {
        assert_eq!(humanize_filename("ocean-waves"), "Ocean Waves");
        assert_eq!(
            humanize_filename("costa_rica-rainforest"),
            "Costa Rica Rainforest"
        );
        assert_eq!(humanize_filename("simple"), "Simple");
    }

    #[test]
    fn test_bake_crossfade_short_audio() {
        // Very short audio should be returned unchanged
        let samples = vec![1.0; 100];
        let result = bake_crossfade(samples.clone(), 1);
        assert_eq!(result.len(), 100);
    }

    #[test]
    fn test_bake_crossfade_produces_shorter_output() {
        // 10 seconds of mono audio at 44100Hz
        let n = 44100 * 10;
        let samples: Vec<f32> = (0..n).map(|i| i as f32 / n as f32).collect();
        let result = bake_crossfade(samples, 1);
        // Output should be shorter by crossfade_frames
        assert!(result.len() < n);
        assert!(result.len() > n / 2);
    }

    #[test]
    fn test_resample_identity() {
        let samples = vec![1.0, 0.5, -0.5, -1.0];
        let result = resample(&samples, 1, 44100, 44100);
        assert_eq!(result, samples);
    }

    #[test]
    fn test_resample_upsample() {
        let samples = vec![0.0, 1.0];
        let result = resample(&samples, 1, 22050, 44100);
        assert_eq!(result.len(), 4);
    }

    #[test]
    fn test_duration_secs() {
        assert!((duration_secs(44100, 1) - 1.0).abs() < 0.001);
        assert!((duration_secs(88200, 2) - 1.0).abs() < 0.001);
    }
}
