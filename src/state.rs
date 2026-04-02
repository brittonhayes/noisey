use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Instant;
use tokio::sync::mpsc;

#[cfg(feature = "wifi")]
use crate::wifi;

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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recorded_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_secs: Option<f32>,
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

pub struct AppState {
    pub sounds: Vec<SoundEntry>,
    pub master_volume: f32,
    pub sleep_timer: Option<SleepTimer>,
    pub schedule: Option<Schedule>,
    pub audio_tx: mpsc::Sender<AudioCommand>,
    pub simulate: bool,
    pub sounds_dir: PathBuf,
    pub current_device: Option<String>,
    #[cfg(feature = "wifi")]
    pub wifi_state: wifi::SharedWifiState,
}

#[derive(Debug)]
pub enum AudioCommand {
    Play { id: String },
    Stop { id: String },
    SetMasterVolume(f32),
    StopAll,
    InvalidateCache { id: String },
    SelectDevice { device_name: Option<String> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioDeviceInfo {
    pub name: String,
    pub is_default: bool,
}

/// Sidecar metadata for uploaded sound memories.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoundMeta {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recorded_at: Option<String>,
}

#[derive(Serialize)]
pub struct StatusResponse {
    pub sounds: Vec<SoundEntry>,
    pub master_volume: f32,
    pub sleep_timer: Option<TimerStatus>,
    pub schedule: Option<Schedule>,
    pub simulate: bool,
    pub current_device: Option<String>,
    #[cfg(feature = "wifi")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wifi: Option<wifi::WifiState>,
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
            simulate: self.simulate,
            current_device: self.current_device.clone(),
            #[cfg(feature = "wifi")]
            wifi: None, // WiFi state is populated by the wifi routes separately
        }
    }
}
