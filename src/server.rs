use crate::audio::{self, AUDIO_EXTENSIONS};
use crate::state::{
    AudioCommand, Schedule, SleepTimer, SoundCategory, SoundEntry, SoundMeta, StatusResponse,
};
use axum::{
    extract::{Multipart, Path, State},
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
use tower_http::limit::RequestBodyLimitLayer;
use tracing::{info, warn};

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
        .route(
            "/api/sounds/upload",
            post(upload_sound).layer(RequestBodyLimitLayer::new(100 * 1024 * 1024)), // 100MB
        )
        .route("/api/sounds/{id}", delete(delete_sound))
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

/// Upload a sound file (multipart/form-data).
/// Fields: `file` (required), `name` (optional display name).
async fn upload_sound(
    State(state): State<SharedState>,
    mut multipart: Multipart,
) -> Result<Json<SoundEntry>, StatusCode> {
    let mut file_data: Option<Vec<u8>> = None;
    let mut file_name: Option<String> = None;
    let mut display_name: Option<String> = None;
    let mut description: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| StatusCode::BAD_REQUEST)?
    {
        let field_name = field.name().unwrap_or("").to_string();
        match field_name.as_str() {
            "file" => {
                file_name = field.file_name().map(|s| s.to_string());
                let bytes = field.bytes().await.map_err(|_| StatusCode::BAD_REQUEST)?;
                file_data = Some(bytes.to_vec());
            }
            "name" => {
                let text = field.text().await.unwrap_or_default();
                if !text.is_empty() {
                    display_name = Some(text);
                }
            }
            "description" => {
                let text = field.text().await.unwrap_or_default();
                if !text.is_empty() {
                    description = Some(text);
                }
            }
            _ => {}
        }
    }

    let data = file_data.ok_or(StatusCode::BAD_REQUEST)?;
    let original_name = file_name.ok_or(StatusCode::BAD_REQUEST)?;

    // Extract extension and validate
    let ext = std::path::Path::new(&original_name)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .ok_or(StatusCode::BAD_REQUEST)?;

    if !AUDIO_EXTENSIONS.contains(&ext.as_str()) {
        warn!(ext = %ext, "Upload rejected: unsupported format");
        return Err(StatusCode::UNSUPPORTED_MEDIA_TYPE);
    }

    // Generate a sanitized ID from the filename
    let stem = std::path::Path::new(&original_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("upload");
    let id = sanitize_id(stem);

    let sounds_dir = {
        let s = state.read().await;
        s.sounds_dir.clone()
    };

    // Ensure sounds directory exists
    let _ = std::fs::create_dir_all(&sounds_dir);

    let file_path = sounds_dir.join(format!("{id}.{ext}"));

    // Write file to disk
    std::fs::write(&file_path, &data).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Validate that symphonia can decode it
    let decoded = audio::decode_file_from_path(&file_path);
    if decoded.is_none() {
        // Clean up invalid file
        let _ = std::fs::remove_file(&file_path);
        warn!(path = %file_path.display(), "Upload rejected: could not decode audio");
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }

    let dur = decoded
        .as_ref()
        .map(|d| audio::duration_secs(d.samples.len(), d.channels));

    // Determine display name
    let name = display_name
        .filter(|n| !n.trim().is_empty())
        .unwrap_or_else(|| audio::humanize_filename(&id));

    // Save sidecar metadata
    let meta = SoundMeta {
        name: name.clone(),
        description: description.clone(),
        recorded_at: None,
    };
    let meta_path = sounds_dir.join(format!("{id}.json"));
    if let Ok(json) = serde_json::to_string_pretty(&meta) {
        let _ = std::fs::write(&meta_path, json);
    }

    let entry = SoundEntry {
        id: id.clone(),
        name,
        category: SoundCategory::Custom,
        active: false,
        description,
        recorded_at: None,
        duration_secs: dur,
    };

    // Add to catalog and invalidate audio cache
    let mut s = state.write().await;
    // Remove existing entry with same ID if re-uploading
    s.sounds.retain(|existing| existing.id != id);
    s.sounds.push(entry.clone());
    let _ = s
        .audio_tx
        .send(AudioCommand::InvalidateCache { id: id.clone() })
        .await;

    info!(id = %id, "API: sound uploaded");

    Ok(Json(entry))
}

/// Delete a custom sound by ID.
async fn delete_sound(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<StatusResponse>, StatusCode> {
    let mut s = state.write().await;

    // Only allow deleting custom sounds
    let is_custom = s
        .sounds
        .iter()
        .find(|snd| snd.id == id)
        .map(|snd| snd.category == SoundCategory::Custom)
        .unwrap_or(false);

    if !is_custom {
        return Err(StatusCode::FORBIDDEN);
    }

    // Stop if playing
    if s.sounds.iter().any(|snd| snd.id == id && snd.active) {
        let _ = s.audio_tx.send(AudioCommand::Stop { id: id.clone() }).await;
    }

    // Remove from catalog
    s.sounds.retain(|snd| snd.id != id);

    // Invalidate audio cache
    let _ = s
        .audio_tx
        .send(AudioCommand::InvalidateCache { id: id.clone() })
        .await;

    // Delete files from disk
    let sounds_dir = s.sounds_dir.clone();
    for ext in AUDIO_EXTENSIONS {
        let path = sounds_dir.join(format!("{id}.{ext}"));
        let _ = std::fs::remove_file(&path);
    }
    let _ = std::fs::remove_file(sounds_dir.join(format!("{id}.json")));

    info!(id = %id, "API: sound deleted");

    Ok(Json(s.status()))
}

/// Sanitize a string for use as a sound ID (filesystem-safe, URL-safe).
fn sanitize_id(input: &str) -> String {
    let sanitized: String = input
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c.to_lowercase().next().unwrap_or(c)
            } else if c == ' ' {
                '-'
            } else {
                '_'
            }
        })
        .collect();

    // Collapse multiple dashes/underscores
    let mut result = String::new();
    let mut prev_sep = false;
    for c in sanitized.chars() {
        if c == '-' || c == '_' {
            if !prev_sep {
                result.push(c);
            }
            prev_sep = true;
        } else {
            result.push(c);
            prev_sep = false;
        }
    }

    result
        .trim_matches(|c: char| c == '-' || c == '_')
        .to_string()
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
