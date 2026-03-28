use crate::state::{AudioCommand, Schedule, SleepTimer, StatusResponse};
use axum::{
    extract::{Path, State},
    http::{header, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::{delete, get, post},
    Json, Router,
};
use rust_embed::Embed;
use serde::Deserialize;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tracing::info;

use crate::state::AppState;

#[derive(Embed)]
#[folder = "static/"]
struct StaticAssets;

pub type SharedState = Arc<RwLock<AppState>>;

pub fn create_router(state: SharedState) -> Router {
    let router = Router::new()
        .route("/", get(index_handler))
        .route("/api/sounds", get(list_sounds))
        .route("/api/sounds/{id}/toggle", post(toggle_sound))
        .route("/api/volume", post(set_volume))
        .route("/api/sleep-timer", post(set_sleep_timer))
        .route("/api/schedule", get(get_schedule))
        .route("/api/schedule", post(set_schedule))
        .route("/api/schedule", delete(delete_schedule))
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
        .iter()
        .find(|s| s.id == id)
        .ok_or(StatusCode::NOT_FOUND)?;

    let was_active = sound.active;

    if was_active {
        let _ = state
            .audio_tx
            .send(AudioCommand::Stop { id: id.clone() })
            .await;
        if let Some(s) = state.sounds.iter_mut().find(|s| s.id == id) {
            s.active = false;
        }
        info!(sound = %id, "API stop request");
    } else {
        // Stop whatever is currently playing, then start the new one
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
        let _ = state
            .audio_tx
            .send(AudioCommand::Play { id: id.clone() })
            .await;
        if let Some(s) = state.sounds.iter_mut().find(|s| s.id == id) {
            s.active = true;
        }
        info!(sound = %id, "API play request");
    }

    Ok(Json(state.status()))
}

#[derive(Deserialize)]
pub struct VolumeRequest {
    pub volume: f32,
}

async fn set_volume(
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

    info!(volume = %volume, "API volume set");

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
        info!("API sleep timer cancelled");
    } else {
        let duration_secs = body.minutes * 60;
        state.sleep_timer = Some(SleepTimer {
            end_time: Instant::now() + Duration::from_secs(duration_secs),
            duration_secs,
        });
        info!(minutes = body.minutes, "API sleep timer set");
    }

    Json(state.status())
}

// ========================================
// SCHEDULE
// ========================================

async fn get_schedule(State(state): State<SharedState>) -> Json<Option<Schedule>> {
    let state = state.read().await;
    Json(state.schedule.clone())
}

#[derive(Deserialize)]
pub struct ScheduleRequest {
    pub start_time: String,
    pub stop_time: String,
    pub sound_id: String,
    pub enabled: bool,
}

async fn set_schedule(
    State(state): State<SharedState>,
    Json(body): Json<ScheduleRequest>,
) -> Json<StatusResponse> {
    let mut state = state.write().await;
    let schedule = Schedule {
        start_time: body.start_time,
        stop_time: body.stop_time,
        sound_id: body.sound_id,
        enabled: body.enabled,
    };
    info!(
        start = %schedule.start_time,
        stop = %schedule.stop_time,
        sound = %schedule.sound_id,
        enabled = schedule.enabled,
        "API schedule updated"
    );
    state.schedule = Some(schedule);
    crate::save_schedule(&state.schedule);
    Json(state.status())
}

async fn delete_schedule(State(state): State<SharedState>) -> Json<StatusResponse> {
    let mut state = state.write().await;
    state.schedule = None;
    crate::save_schedule(&state.schedule);
    info!("API schedule deleted");
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
