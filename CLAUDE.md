# CLAUDE.md

## Project

Noisey is a Rust-based IoT ambient noise machine with a web UI and optional e-ink display. Runs on Raspberry Pi.

## Build Prerequisites

```bash
# Required system library (ALSA audio)
sudo apt install libasound2-dev

# For cross-compiling to Raspberry Pi
cargo install cross --git https://github.com/cross-rs/cross
```

## Build Commands

```bash
# Standard build
cargo build --release

# Build with e-ink display support
cargo build --release --features eink

# Cross-compile for Raspberry Pi
./cross-compile.sh           # aarch64 (Pi 3/4/5)
./cross-compile.sh armv7     # armv7 (Pi 2/3)
```

## Run

```bash
# Default (web UI on port 8080)
cargo run --release

# With e-ink display
cargo run --release --features eink -- --eink --eink-refresh 30

# Custom sounds directory
cargo run --release -- --sounds-dir ~/my-sounds --port 3000
```

## Test

```bash
cargo test
cargo test --features eink
```

## Lint

```bash
cargo clippy -- -D warnings
cargo fmt --check
```

## Architecture

```
src/
├── main.rs      # CLI args, state setup, sleep timer task
├── audio.rs     # Audio engine (dedicated thread, rodio sinks)
├── noise.rs     # Procedural noise generators (white/pink/brown)
├── server.rs    # Axum web server, REST API, static assets
├── state.rs     # Shared state types, audio commands
└── display.rs   # E-ink display driver (behind "eink" feature flag)
static/          # Embedded web UI (HTML/CSS/JS)
docs/BUILD.md    # Hardware build guide for the physical device
```

## Key Design Decisions

- Audio engine runs on a dedicated std::thread (rodio OutputStream is !Send)
- Communication with audio thread via tokio mpsc channel
- Static assets embedded into binary via rust-embed
- E-ink support is behind the `eink` cargo feature flag to avoid pulling in display code on headless builds
- Display falls back to writing `/tmp/noisey-display.txt` when SPI/GPIO hardware is unavailable
