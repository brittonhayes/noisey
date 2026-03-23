use crate::noise::{BrownNoise, PinkNoise, WhiteNoise};
use crate::state::AudioCommand;
use rodio::{Decoder, OutputStream, OutputStreamHandle, Sink, Source};
use std::collections::HashMap;
use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use tokio::sync::mpsc;
use tracing::{error, info, warn};

struct AudioRuntime {
    _stream: OutputStream,
    stream_handle: OutputStreamHandle,
    sinks: HashMap<String, Sink>,
    master_volume: f32,
    volumes: HashMap<String, f32>,
    sounds_dir: PathBuf,
}

impl AudioRuntime {
    fn new(sounds_dir: PathBuf) -> Result<Self, Box<dyn std::error::Error>> {
        let (stream, stream_handle) = OutputStream::try_default()?;
        Ok(Self {
            _stream: stream,
            stream_handle,
            sinks: HashMap::new(),
            master_volume: 0.8,
            volumes: HashMap::new(),
            sounds_dir,
        })
    }

    fn play_sound(&mut self, id: &str, volume: f32) {
        self.stop_sound(id);

        let sink = match Sink::try_new(&self.stream_handle) {
            Ok(s) => s,
            Err(e) => {
                error!("Failed to create audio sink for {id}: {e}");
                return;
            }
        };

        match id {
            "white-noise" => sink.append(WhiteNoise::new()),
            "pink-noise" => sink.append(PinkNoise::new()),
            "brown-noise" => sink.append(BrownNoise::new()),
            _ => {
                if let Some(source) = self.load_sound_file(id) {
                    sink.append(source);
                } else {
                    warn!("Unknown sound: {id}");
                    return;
                }
            }
        }

        sink.set_volume(volume * self.master_volume);
        self.volumes.insert(id.to_string(), volume);
        self.sinks.insert(id.to_string(), sink);
        info!("Playing sound: {id} at volume {volume}");
    }

    fn load_sound_file(&self, id: &str) -> Option<Box<dyn Source<Item = f32> + Send>> {
        for ext in &["wav", "ogg"] {
            let path = self.sounds_dir.join(format!("{id}.{ext}"));
            if path.exists() {
                return self.decode_file(&path);
            }
        }

        // Scan directory for matching stem
        if let Ok(entries) = std::fs::read_dir(&self.sounds_dir) {
            for entry in entries.flatten() {
                let file_name = entry.file_name();
                let name = file_name.to_string_lossy();
                let stem = Path::new(&*name)
                    .file_stem()
                    .map(|s| s.to_string_lossy().to_string());
                if stem.as_deref() == Some(id) {
                    return self.decode_file(&entry.path());
                }
            }
        }

        None
    }

    fn decode_file(&self, path: &Path) -> Option<Box<dyn Source<Item = f32> + Send>> {
        let file = File::open(path).ok()?;
        let reader = BufReader::new(file);
        let decoder = Decoder::new(reader).ok()?;
        Some(Box::new(decoder.repeat_infinite().convert_samples::<f32>()))
    }

    fn stop_sound(&mut self, id: &str) {
        if let Some(sink) = self.sinks.remove(id) {
            sink.stop();
            info!("Stopped sound: {id}");
        }
        self.volumes.remove(id);
    }

    fn set_volume(&mut self, id: &str, volume: f32) {
        self.volumes.insert(id.to_string(), volume);
        if let Some(sink) = self.sinks.get(id) {
            sink.set_volume(volume * self.master_volume);
        }
    }

    fn update_all_volumes(&self) {
        for (id, sink) in &self.sinks {
            let vol = self.volumes.get(id).copied().unwrap_or(0.5);
            sink.set_volume(vol * self.master_volume);
        }
    }

    fn stop_all(&mut self) {
        for (id, sink) in self.sinks.drain() {
            sink.stop();
            info!("Stopped sound: {id}");
        }
        self.volumes.clear();
    }
}

/// Spawn the audio engine on a dedicated thread.
/// The OutputStream is created on that thread (it's not Send).
pub fn spawn_audio_thread(sounds_dir: PathBuf, rx: mpsc::Receiver<AudioCommand>) {
    std::thread::spawn(move || {
        let mut runtime = match AudioRuntime::new(sounds_dir) {
            Ok(r) => r,
            Err(e) => {
                error!("Failed to initialize audio: {e}");
                return;
            }
        };

        let mut rx = rx;
        while let Some(cmd) = rx.blocking_recv() {
            match cmd {
                AudioCommand::Play { id, volume } => runtime.play_sound(&id, volume),
                AudioCommand::Stop { id } => runtime.stop_sound(&id),
                AudioCommand::SetVolume { id, volume } => runtime.set_volume(&id, volume),
                AudioCommand::SetMasterVolume(vol) => {
                    runtime.master_volume = vol;
                    runtime.update_all_volumes();
                }
                AudioCommand::StopAll => runtime.stop_all(),
            }
        }

        info!("Audio engine shutting down");
    });
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
