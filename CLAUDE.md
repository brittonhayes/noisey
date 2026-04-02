# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Noisey is a Rust-based IoT ambient noise machine designed to run on a Raspberry Pi. It provides a web UI for controlling ambient sounds — both procedurally generated noise and user-uploaded audio files. The goal is a self-contained, single-binary appliance: no external dependencies at runtime, no separate web server, no config files required to start.

## Build & Dev

```bash
cargo build --release                  # Standard build
cargo test                             # Run tests
cargo clippy -- -D warnings            # Lint
cargo fmt --check                      # Format check
cargo test test_name                   # Single test by name
```

The `--simulate` flag runs without audio hardware, useful for development and CI. Feature flags (`eink`, `wifi`) gate optional hardware integrations — check `Cargo.toml` for the full list. Cross-compilation to Raspberry Pi targets uses `cross` via the cross-compile script in the repo root.

## Design Principles

**Single binary, zero config.** Static web assets are embedded into the binary at compile time. The app should start with sensible defaults and no mandatory configuration. Sound files are the only external runtime dependency.

**No system audio dependencies at build time.** The audio backend loads platform audio libraries dynamically at runtime (ALSA on Linux). If no audio device is available, the engine falls back to simulation mode automatically — it should never crash due to missing hardware.

**One-way command flow.** The web server owns the shared application state and sends commands to the audio thread through a channel. The audio thread never writes back to shared state. This keeps concurrency simple — if you're adding new audio behavior, it should be driven by adding a new command variant and handling it on the audio thread side.

**Procedural sounds are iterators.** Built-in ambient sounds are implemented as trait objects that yield f32 samples. To add a new procedural sound, implement the sound source trait and wire it into the command handler's match block. File-based sounds are decoded at load time and loop seamlessly via a baked crossfade.

**Feature flags for hardware.** Optional hardware support (e-ink display, WiFi provisioning) lives behind cargo feature flags so headless/desktop builds don't pull in unnecessary code. Each feature flag gates its own module and API routes.

## Navigating the Codebase

- **Entry point and CLI args:** Start from `main.rs` — it sets up state, spawns background tasks, and starts the web server.
- **Audio engine:** Look for the module that handles audio device setup, the mixing callback, and the command processing loop. Procedural noise generators live in their own module built around a shared trait.
- **Web API:** The server module defines all REST routes. Routes follow a RESTful pattern around sounds, volume, timers, and schedules. Static assets are served via rust-embed.
- **Shared state:** There's a central app state struct behind `Arc<RwLock<...>>` — grep for the state type definitions to understand what's tracked.
- **Background tasks:** Sleep timer and schedule enforcement run as tokio tasks spawned from main. They read/write shared state and send audio commands.

## REST API Conventions

All API endpoints live under `/api/` and return JSON. Sound toggling stops any currently playing sound before starting a new one (single-sound-at-a-time UX). File uploads are multipart with server-side decode validation. The status endpoint returns the full application state snapshot for the UI to render.
