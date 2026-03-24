use crate::state::{AppState, AudioCommand, SleepTimer, StatusResponse};
use axum::{
    extract::{Path, State},
    http::{header, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use rust_embed::Embed;
use serde::Deserialize;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tracing::info;

#[derive(Embed)]
#[folder = "static/"]
struct StaticAssets;

pub type SharedState = Arc<RwLock<AppState>>;

pub fn create_router(state: SharedState) -> Router {
    let router = Router::new()
        .route("/", get(index_handler))
        .route("/api/sounds", get(list_sounds))
        .route("/api/sounds/{id}/toggle", post(toggle_sound))
        .route("/api/sounds/{id}/volume", post(set_sound_volume))
        .route("/api/master-volume", post(set_master_volume))
        .route("/api/sleep-timer", post(set_sleep_timer))
        .route("/api/status", get(get_status));

    #[cfg(feature = "eink")]
    let router = router.route("/api/display/preview", get(display_preview));

    router
        .route("/{*path}", get(static_handler))
        .layer(CorsLayer::permissive())
        .with_state(state)
}

async fn index_handler() -> impl IntoResponse {
    match StaticAssets::get("index.html") {
        Some(content) => Html(String::from_utf8_lossy(&content.data).to_string()).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn static_handler(Path(path): Path<String>) -> impl IntoResponse {
    match StaticAssets::get(&path) {
        Some(content) => {
            let mime = mime_guess::from_path(&path).first_or_octet_stream();
            Response::builder()
                .header(header::CONTENT_TYPE, mime.as_ref())
                .body(axum::body::Body::from(content.data.to_vec()))
                .unwrap()
                .into_response()
        }
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn list_sounds(State(state): State<SharedState>) -> Json<Vec<crate::state::SoundEntry>> {
    let state = state.read().await;
    Json(state.sounds.clone())
}

async fn get_status(State(state): State<SharedState>) -> Json<StatusResponse> {
    let state = state.read().await;
    Json(state.status())
}

async fn toggle_sound(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<StatusResponse>, StatusCode> {
    let mut state = state.write().await;

    let sound = state
        .sounds
        .iter_mut()
        .find(|s| s.id == id)
        .ok_or(StatusCode::NOT_FOUND)?;

    sound.active = !sound.active;
    let active = sound.active;
    let volume = sound.volume;

    let cmd = if active {
        AudioCommand::Play {
            id: id.clone(),
            volume,
        }
    } else {
        AudioCommand::Stop { id: id.clone() }
    };

    let _ = state.audio_tx.send(cmd).await;
    info!("Toggled sound {id}: active={active}");

    Ok(Json(state.status()))
}

#[derive(Deserialize)]
pub struct VolumeRequest {
    pub volume: f32,
}

async fn set_sound_volume(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    Json(body): Json<VolumeRequest>,
) -> Result<Json<StatusResponse>, StatusCode> {
    let mut state = state.write().await;
    let volume = body.volume.clamp(0.0, 1.0);

    let sound = state
        .sounds
        .iter_mut()
        .find(|s| s.id == id)
        .ok_or(StatusCode::NOT_FOUND)?;

    sound.volume = volume;

    if sound.active {
        let _ = state
            .audio_tx
            .send(AudioCommand::SetVolume {
                id: id.clone(),
                volume,
            })
            .await;
    }

    Ok(Json(state.status()))
}

async fn set_master_volume(
    State(state): State<SharedState>,
    Json(body): Json<VolumeRequest>,
) -> Json<StatusResponse> {
    let mut state = state.write().await;
    let volume = body.volume.clamp(0.0, 1.0);
    state.master_volume = volume;
    let _ = state
        .audio_tx
        .send(AudioCommand::SetMasterVolume(volume))
        .await;
    Json(state.status())
}

#[derive(Deserialize)]
pub struct SleepTimerRequest {
    pub minutes: u64,
}

async fn set_sleep_timer(
    State(state): State<SharedState>,
    Json(body): Json<SleepTimerRequest>,
) -> Json<StatusResponse> {
    let mut state = state.write().await;

    if body.minutes == 0 {
        state.sleep_timer = None;
        info!("Sleep timer cancelled");
    } else {
        let duration_secs = body.minutes * 60;
        state.sleep_timer = Some(SleepTimer {
            end_time: Instant::now() + Duration::from_secs(duration_secs),
            duration_secs,
        });
        info!("Sleep timer set for {} minutes", body.minutes);
    }

    Json(state.status())
}

/// Serve a live 1-bit BMP preview of the e-ink display.
/// Hit /api/display/preview in your browser to see exactly what the e-ink screen renders.
#[cfg(feature = "eink")]
async fn display_preview(State(state): State<SharedState>) -> impl IntoResponse {
    use crate::display::{render_status, EINK_HEIGHT, EINK_WIDTH};

    let frame = render_status(&state).await;
    let bmp = frame.to_bmp(EINK_WIDTH, EINK_HEIGHT);

    Response::builder()
        .header(header::CONTENT_TYPE, "image/bmp")
        .header(header::CACHE_CONTROL, "no-cache")
        .body(axum::body::Body::from(bmp))
        .unwrap()
        .into_response()
}
