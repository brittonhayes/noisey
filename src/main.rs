mod audio;
#[cfg(feature = "eink")]
mod display;
mod noise;
mod server;
mod state;

use crate::audio::{scan_sound_files, spawn_audio_thread};
#[cfg(feature = "eink")]
use crate::display::{spawn_display_thread, DisplayConfig};
use crate::server::{create_router, SharedState};
use crate::state::{AppState, AudioCommand, SoundCategory, SoundEntry};
use clap::Parser;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{mpsc, RwLock};
use tracing::info;

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
    let mut sounds: Vec<SoundEntry> = vec![
        SoundEntry {
            id: "white-noise".into(),
            name: "White Noise".into(),
            category: SoundCategory::Noise,
            active: false,
            volume: 0.5,
        },
        SoundEntry {
            id: "pink-noise".into(),
            name: "Pink Noise".into(),
            category: SoundCategory::Noise,
            active: false,
            volume: 0.5,
        },
        SoundEntry {
            id: "brown-noise".into(),
            name: "Brown Noise".into(),
            category: SoundCategory::Noise,
            active: false,
            volume: 0.5,
        },
    ];

    // Scan for user-provided sound files
    let file_sounds = scan_sound_files(&args.sounds_dir);
    for (id, name) in file_sounds {
        sounds.push(SoundEntry {
            id,
            name,
            category: SoundCategory::Custom,
            active: false,
            volume: 0.5,
        });
    }

    info!(
        "Loaded {} sounds ({} from files)",
        sounds.len(),
        sounds.len() - 3
    );

    // Create audio command channel
    let (audio_tx, audio_rx) = mpsc::channel::<AudioCommand>(64);

    // Shared application state
    let state: SharedState = Arc::new(RwLock::new(AppState {
        sounds,
        master_volume: 0.8,
        sleep_timer: None,
        audio_tx,
    }));

    // Start audio engine on a dedicated thread
    // OutputStream is created there since it's not Send
    spawn_audio_thread(args.sounds_dir.clone(), audio_rx);
    info!("Audio engine started");

    // Spawn sleep timer watcher
    let timer_state = state.clone();
    tokio::spawn(async move {
        sleep_timer_task(timer_state).await;
    });

    // Start e-ink display if enabled
    #[cfg(feature = "eink")]
    if args.eink {
        let display_config = DisplayConfig {
            refresh_secs: args.eink_refresh,
            ..DisplayConfig::default()
        };
        spawn_display_thread(state.clone(), display_config);
        info!("E-ink display enabled");
    }

    // Start web server
    let addr: SocketAddr = format!("{}:{}", args.host, args.port)
        .parse()
        .expect("Invalid host:port");

    let router = create_router(state);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();

    info!("Noisey listening on http://{addr}");

    axum::serve(listener, router).await.unwrap();
}

async fn sleep_timer_task(state: SharedState) {
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        let mut state = state.write().await;
        if let Some(timer) = &state.sleep_timer {
            if Instant::now() >= timer.end_time {
                info!("Sleep timer expired — stopping all sounds");
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
