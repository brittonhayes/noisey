use serde::{Deserialize, Serialize};
use std::time::Instant;
use tokio::sync::mpsc;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SoundCategory {
    Noise,
    Nature,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoundEntry {
    pub id: String,
    pub name: String,
    pub category: SoundCategory,
    pub active: bool,
    pub volume: f32,
}

pub struct SleepTimer {
    pub end_time: Instant,
    pub duration_secs: u64,
}

pub struct AppState {
    pub sounds: Vec<SoundEntry>,
    pub master_volume: f32,
    pub sleep_timer: Option<SleepTimer>,
    pub audio_tx: mpsc::Sender<AudioCommand>,
}

#[derive(Debug)]
pub enum AudioCommand {
    Play { id: String, volume: f32 },
    Stop { id: String },
    SetVolume { id: String, volume: f32 },
    SetMasterVolume(f32),
    StopAll,
}

#[derive(Serialize)]
pub struct StatusResponse {
    pub sounds: Vec<SoundEntry>,
    pub master_volume: f32,
    pub sleep_timer: Option<TimerStatus>,
}

#[derive(Serialize)]
pub struct TimerStatus {
    pub remaining_secs: u64,
    pub duration_secs: u64,
}

impl AppState {
    pub fn status(&self) -> StatusResponse {
        let sleep_timer = self.sleep_timer.as_ref().map(|t| {
            let remaining = t.end_time.saturating_duration_since(Instant::now());
            TimerStatus {
                remaining_secs: remaining.as_secs(),
                duration_secs: t.duration_secs,
            }
        });

        StatusResponse {
            sounds: self.sounds.clone(),
            master_volume: self.master_volume,
            sleep_timer,
        }
    }
}
