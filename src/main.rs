mod audio;
#[cfg(feature = "eink")]
mod display;
mod noise;
mod server;
mod state;
#[cfg(feature = "wifi")]
mod wifi;

use crate::audio::{scan_sound_files, spawn_audio_thread};
#[cfg(feature = "eink")]
use crate::display::{spawn_display_thread, DisplayConfig};
use crate::server::{create_router, SharedState};
use crate::state::{AppState, AudioCommand, Schedule, SoundCategory, SoundEntry};
use chrono::NaiveTime;
use clap::Parser;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{mpsc, RwLock};
use tracing::info;
#[cfg(feature = "wifi")]
use tracing::warn;

#[derive(Parser)]
#[command(name = "noisey", about = "IoT ambient noise machine")]
struct Args {
    /// Port to serve the web interface on
    #[arg(long, default_value = "8080")]
    port: u16,

    /// Host address to bind to
    #[arg(long, default_value = "0.0.0.0")]
    host: String,

    /// Directory containing sound files (.wav, .ogg)
    #[arg(long, default_value = "./sounds")]
    sounds_dir: PathBuf,

    /// Enable e-ink display output (requires --features eink)
    #[arg(long, default_value = "false")]
    eink: bool,

    /// E-ink display refresh interval in seconds
    #[arg(long, default_value = "30")]
    eink_refresh: u64,

    /// Run in simulation mode (no audio hardware required)
    #[arg(long, default_value = "false")]
    simulate: bool,

    /// Force WiFi setup mode (start hotspot for configuration)
    #[cfg(feature = "wifi")]
    #[arg(long, default_value = "false")]
    setup: bool,
}

/// Path to the schedule config file.
fn schedule_config_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("noisey").join("schedule.json"))
}

/// Load a saved schedule from disk.
fn load_schedule() -> Option<Schedule> {
    let path = schedule_config_path()?;
    let data = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&data).ok()
}

/// Save the current schedule to disk.
pub fn save_schedule(schedule: &Option<Schedule>) {
    let Some(path) = schedule_config_path() else {
        return;
    };
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    match schedule {
        Some(s) => {
            if let Ok(json) = serde_json::to_string_pretty(s) {
                let _ = std::fs::write(&path, json);
            }
        }
        None => {
            let _ = std::fs::remove_file(&path);
        }
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "noisey=info".into()),
        )
        .init();

    let args = Args::parse();

    // Build sound catalog
    let builtin = |id: &str, name: &str| SoundEntry {
        id: id.into(),
        name: name.into(),
        category: SoundCategory::Nature,
        active: false,
        description: None,
        recorded_at: None,
        duration_secs: None,
    };

    let mut sounds: Vec<SoundEntry> = vec![
        builtin("ocean-surf", "Ocean Surf"),
        builtin("warm-rain", "Warm Rain"),
        builtin("creek", "Creek"),
        builtin("night-wind", "Night Wind"),
    ];

    // Scan for user-provided sound files
    let file_sounds = scan_sound_files(&args.sounds_dir);
    for (id, name) in file_sounds {
        // Check for sidecar metadata
        let meta_path = args.sounds_dir.join(format!("{id}.json"));
        let meta: Option<crate::state::SoundMeta> = std::fs::read_to_string(&meta_path)
            .ok()
            .and_then(|data| serde_json::from_str(&data).ok());

        let display_name = meta.as_ref().map(|m| m.name.clone()).unwrap_or(name);
        sounds.push(SoundEntry {
            id,
            name: display_name,
            category: SoundCategory::Custom,
            active: false,
            description: meta.as_ref().and_then(|m| m.description.clone()),
            recorded_at: meta.as_ref().and_then(|m| m.recorded_at.clone()),
            duration_secs: None,
        });
    }

    let file_count = sounds.len() - 4;
    info!(
        total = sounds.len(),
        builtin = 4,
        files = file_count,
        "Startup: sound catalog loaded"
    );

    // Create audio command channel
    let (audio_tx, audio_rx) = mpsc::channel::<AudioCommand>(64);

    // Start audio engine on a dedicated thread and wait for actual mode
    let sim_rx = spawn_audio_thread(args.sounds_dir.clone(), audio_rx, audio_tx.clone(), args.simulate);
    let simulate = sim_rx.recv().unwrap_or(args.simulate);
    if simulate {
        info!("Startup: audio engine started (simulation mode)");
    } else {
        info!("Startup: audio engine started");
    }

    // Load saved schedule
    let schedule = load_schedule();
    if let Some(ref s) = schedule {
        info!(
            start = %s.start_time,
            stop = %s.stop_time,
            sound = %s.sound_id,
            "Startup: schedule loaded from disk"
        );
    }

    // WiFi setup mode: check connectivity and start hotspot if needed
    #[cfg(feature = "wifi")]
    let wifi_state: wifi::SharedWifiState = {
        use std::sync::Arc as StdArc;
        let initial = if args.setup {
            info!("WiFi: --setup flag set, forcing setup mode");
            wifi::WifiState::Unknown
        } else {
            wifi::WifiState::Unknown
        };
        StdArc::new(RwLock::new(initial))
    };

    #[cfg(feature = "wifi")]
    {
        let needs_setup = args.setup || !wifi::check_connectivity().await;
        if needs_setup {
            match wifi::start_hotspot().await {
                Ok(()) => {
                    *wifi_state.write().await = wifi::WifiState::AccessPoint;
                    info!(
                        ssid = wifi::HOTSPOT_SSID,
                        password = wifi::HOTSPOT_PASSWORD,
                        "WiFi: setup mode active — connect to '{}' (password: '{}') then visit http://10.42.0.1:{}",
                        wifi::HOTSPOT_SSID,
                        wifi::HOTSPOT_PASSWORD,
                        args.port,
                    );
                }
                Err(e) => {
                    warn!("WiFi: failed to start hotspot: {e}");
                    *wifi_state.write().await = wifi::WifiState::Failed { reason: e };
                }
            }
        } else {
            let ip = wifi::get_device_ip().await.unwrap_or_default();
            info!(ip = %ip, "WiFi: already connected");
            *wifi_state.write().await = wifi::WifiState::Connected { ip };
        }
    }

    // Shared application state
    let state: SharedState = Arc::new(RwLock::new(AppState {
        sounds,
        master_volume: 0.8,
        sleep_timer: None,
        schedule,
        audio_tx,
        simulate,
        sounds_dir: args.sounds_dir.clone(),
        current_device: None,
        #[cfg(feature = "wifi")]
        wifi_state: wifi_state.clone(),
    }));

    // Spawn sleep timer watcher
    let timer_state = state.clone();
    tokio::spawn(async move {
        sleep_timer_task(timer_state).await;
    });

    // Spawn schedule watcher
    let schedule_state = state.clone();
    tokio::spawn(async move {
        schedule_task(schedule_state).await;
    });

    // Start e-ink display if enabled
    #[cfg(feature = "eink")]
    if args.eink {
        let display_config = DisplayConfig {
            refresh_secs: args.eink_refresh,
            ..DisplayConfig::default()
        };
        spawn_display_thread(state.clone(), display_config);
        info!(
            refresh_secs = args.eink_refresh,
            "Startup: e-ink display enabled"
        );
    }

    // Start web server
    let addr: SocketAddr = format!("{}:{}", args.host, args.port)
        .parse()
        .expect("Invalid host:port");

    let router = create_router(state);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();

    info!(addr = %addr, "Startup: web server listening on http://{addr}");

    axum::serve(listener, router).await.unwrap();
}

async fn sleep_timer_task(state: SharedState) {
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        let mut state = state.write().await;
        if let Some(timer) = &state.sleep_timer {
            if Instant::now() >= timer.end_time {
                info!("Timer: sleep timer expired, stopping all sounds");
                let _ = state.audio_tx.send(AudioCommand::StopAll).await;

                // Mark all sounds as inactive
                for sound in &mut state.sounds {
                    sound.active = false;
                }
                state.sleep_timer = None;
            }
        }
    }
}

async fn schedule_task(state: SharedState) {
    let mut was_in_window = false;

    loop {
        tokio::time::sleep(std::time::Duration::from_secs(30)).await;

        let mut state = state.write().await;
        let schedule = match &state.schedule {
            Some(s) if s.enabled => s.clone(),
            _ => {
                was_in_window = false;
                continue;
            }
        };

        let start = match NaiveTime::parse_from_str(&schedule.start_time, "%H:%M") {
            Ok(t) => t,
            Err(_) => continue,
        };
        let stop = match NaiveTime::parse_from_str(&schedule.stop_time, "%H:%M") {
            Ok(t) => t,
            Err(_) => continue,
        };

        let now = chrono::Local::now().time();
        let in_window = if start <= stop {
            // Same-day window: e.g. 08:00–18:00
            now >= start && now < stop
        } else {
            // Overnight window: e.g. 22:00–07:00
            now >= start || now < stop
        };

        if in_window && !was_in_window {
            // Entering window — start playing
            let sound_id = schedule.sound_id.clone();

            // Stop any currently playing sounds first
            let active_ids: Vec<String> = state
                .sounds
                .iter()
                .filter(|s| s.active)
                .map(|s| s.id.clone())
                .collect();
            for aid in &active_ids {
                let _ = state
                    .audio_tx
                    .send(AudioCommand::Stop { id: aid.clone() })
                    .await;
            }
            for s in state.sounds.iter_mut() {
                s.active = false;
            }

            // Play the scheduled sound
            let _ = state
                .audio_tx
                .send(AudioCommand::Play {
                    id: sound_id.clone(),
                })
                .await;
            if let Some(s) = state.sounds.iter_mut().find(|s| s.id == sound_id) {
                s.active = true;
            }
            info!(sound = %sound_id, "Schedule: entering window, starting sound");
        } else if !in_window && was_in_window {
            // Leaving window — stop all sounds
            let _ = state.audio_tx.send(AudioCommand::StopAll).await;
            for s in state.sounds.iter_mut() {
                s.active = false;
            }
            info!("Schedule: leaving window, stopping all sounds");
        }

        was_in_window = in_window;
    }
}
