use crate::noise::{BrownNoise, PinkNoise, SoundSource, WhiteNoise, SAMPLE_RATE};
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
    /// Writes exactly `buf.len()` samples, mixing down to mono if needed.
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
                    // Mix channels down to mono
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

struct ActiveSound {
    source: ActiveSource,
    volume: f32,
}

/// Shared state between the command-processing loop and the audio callback.
struct MixerState {
    sounds: HashMap<String, ActiveSound>,
    master_volume: f32,
}

/// Spawn the audio engine on a dedicated thread.
pub fn spawn_audio_thread(sounds_dir: PathBuf, rx: mpsc::Receiver<AudioCommand>) {
    std::thread::spawn(move || {
        if let Err(e) = run_audio_engine(sounds_dir, rx) {
            error!("Audio engine failed: {e}");
        }
    });
}

fn run_audio_engine(
    sounds_dir: PathBuf,
    mut rx: mpsc::Receiver<AudioCommand>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mixer = Arc::new(Mutex::new(MixerState {
        sounds: HashMap::new(),
        master_volume: 0.8,
    }));

    // Set up miniaudio playback device
    let mut device_config = miniaudio::DeviceConfig::new(miniaudio::DeviceType::Playback);
    device_config
        .playback_mut()
        .set_format(miniaudio::Format::F32);
    device_config.playback_mut().set_channels(2);
    device_config.set_sample_rate(SAMPLE_RATE);

    let mixer_for_callback = Arc::clone(&mixer);
    device_config.set_data_callback(move |_device, output, _input| {
        let output_f32 = output.as_samples_mut::<f32>();
        // Zero the buffer first
        for s in output_f32.iter_mut() {
            *s = 0.0;
        }

        let mut state = match mixer_for_callback.lock() {
            Ok(s) => s,
            Err(_) => return,
        };

        if state.sounds.is_empty() {
            return;
        }

        let master_vol = state.master_volume;
        // We output stereo (2 channels), so frame count = samples / 2
        let frame_count = output_f32.len() / 2;
        let mut mono_buf = vec![0.0f32; frame_count];

        for active in state.sounds.values_mut() {
            active.source.fill(&mut mono_buf);
            let vol = active.volume * master_vol;
            for (i, &sample) in mono_buf.iter().enumerate() {
                let scaled = sample * vol;
                // Write to both left and right channels (interleaved stereo)
                output_f32[i * 2] += scaled;
                output_f32[i * 2 + 1] += scaled;
            }
        }

        // Clamp output to prevent clipping
        for s in output_f32.iter_mut() {
            *s = s.clamp(-1.0, 1.0);
        }
    });

    let device = miniaudio::Device::new(None, &device_config)
        .map_err(|e| format!("Failed to create audio device: {e}"))?;
    device
        .start()
        .map_err(|e| format!("Failed to start audio device: {e}"))?;

    info!("Audio device started (miniaudio)");

    // Pre-load file-based sound cache
    let mut file_cache: HashMap<String, Arc<DecodedAudio>> = HashMap::new();

    // Process commands
    while let Some(cmd) = rx.blocking_recv() {
        let mut state = mixer.lock().unwrap();
        match cmd {
            AudioCommand::Play { id, volume } => {
                // Stop existing instance first
                state.sounds.remove(&id);

                let source = match id.as_str() {
                    "white-noise" => Some(ActiveSource::Procedural(Box::new(WhiteNoise::new()))),
                    "pink-noise" => Some(ActiveSource::Procedural(Box::new(PinkNoise::new()))),
                    "brown-noise" => Some(ActiveSource::Procedural(Box::new(BrownNoise::new()))),
                    _ => {
                        // Try to load from file cache or decode
                        let audio = file_cache.get(&id).cloned().or_else(|| {
                            let decoded = load_sound_file(&sounds_dir, &id)?;
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
                                volume,
                            },
                        );
                        info!("Playing sound: {id} at volume {volume}");
                    }
                    None => {
                        warn!("Unknown sound: {id}");
                    }
                }
            }
            AudioCommand::Stop { id } => {
                if state.sounds.remove(&id).is_some() {
                    info!("Stopped sound: {id}");
                }
            }
            AudioCommand::SetVolume { id, volume } => {
                if let Some(active) = state.sounds.get_mut(&id) {
                    active.volume = volume;
                }
            }
            AudioCommand::SetMasterVolume(vol) => {
                state.master_volume = vol;
            }
            AudioCommand::StopAll => {
                let ids: Vec<String> = state.sounds.keys().cloned().collect();
                state.sounds.clear();
                for id in ids {
                    info!("Stopped sound: {id}");
                }
            }
        }
    }

    info!("Audio engine shutting down");
    Ok(())
}

/// Load and decode a sound file (WAV or OGG) into memory.
fn load_sound_file(sounds_dir: &Path, id: &str) -> Option<DecodedAudio> {
    // Try WAV first
    for ext in &["wav", "ogg"] {
        let path = sounds_dir.join(format!("{id}.{ext}"));
        if path.exists() {
            return decode_file(&path);
        }
    }

    // Scan directory for matching stem
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

/// Decode a single audio file into f32 samples.
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

/// Decode a WAV file using the `hound` crate (pure Rust).
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
        "Decoded WAV: {} ({channels}ch, {sample_rate}Hz, {} samples)",
        path.display(),
        samples.len()
    );

    Some(DecodedAudio { samples, channels })
}

/// Decode an OGG Vorbis file using the `lewton` crate (pure Rust).
fn decode_ogg(path: &Path) -> Option<DecodedAudio> {
    let data = std::fs::read(path).ok()?;
    let cursor = Cursor::new(data);
    let mut reader = lewton::inside_ogg::OggStreamReader::new(cursor).ok()?;

    let channels = reader.ident_hdr.audio_channels as u16;
    let sample_rate = reader.ident_hdr.audio_sample_rate;

    let mut samples = Vec::new();
    while let Ok(Some(packet)) = reader.read_dec_packet_itl() {
        for sample in packet {
            // lewton returns i16 samples
            samples.push(sample as f32 / 32768.0);
        }
    }

    info!(
        "Decoded OGG: {} ({channels}ch, {sample_rate}Hz, {} samples)",
        path.display(),
        samples.len()
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
