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
}

pub struct SleepTimer {
    pub end_time: Instant,
    pub duration_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Schedule {
    pub start_time: String,
    pub stop_time: String,
    pub sound_id: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdaptiveConfig {
    pub enabled: bool,
    pub min_volume: f32,
    pub max_volume: f32,
    pub sensitivity: f32,
    pub mic_available: bool,
}

impl Default for AdaptiveConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            min_volume: 0.1,
            max_volume: 1.0,
            sensitivity: 0.5,
            mic_available: false,
        }
    }
}

pub struct AppState {
    pub sounds: Vec<SoundEntry>,
    pub master_volume: f32,
    pub sleep_timer: Option<SleepTimer>,
    pub schedule: Option<Schedule>,
    pub adaptive: AdaptiveConfig,
    pub audio_tx: mpsc::Sender<AudioCommand>,
    pub simulate: bool,
}

#[derive(Debug)]
pub enum AudioCommand {
    Play {
        id: String,
    },
    Stop {
        id: String,
    },
    SetMasterVolume(f32),
    StopAll,
    SetAdaptiveMode {
        enabled: bool,
        min_vol: f32,
        max_vol: f32,
        sensitivity: f32,
    },
}

#[derive(Serialize)]
pub struct StatusResponse {
    pub sounds: Vec<SoundEntry>,
    pub master_volume: f32,
    pub sleep_timer: Option<TimerStatus>,
    pub schedule: Option<Schedule>,
    pub adaptive: AdaptiveConfig,
    pub simulate: bool,
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
            schedule: self.schedule.clone(),
            adaptive: self.adaptive.clone(),
            simulate: self.simulate,
        }
    }
}
