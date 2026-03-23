# noisey

A Rust-based IoT ambient noise machine with web-based remote control. Designed to run on a Raspberry Pi as a replacement for commercial sound machines like the Sound+Sleep SE.

## Features

- **Procedural noise generation** — White, pink, and brown noise built-in
- **Custom sound files** — Drop `.wav` or `.ogg` files into the `sounds/` directory
- **Sound mixing** — Play multiple sounds simultaneously with individual volume controls
- **Sleep timer** — Preset durations (15m to 8h) with live countdown
- **Mobile-first web UI** — Control everything from your phone's browser
- **Single binary** — Static assets embedded, no external files needed

## Quick Start

```bash
# Build
cargo build --release

# Run (serves web UI on http://localhost:8080)
./target/release/noisey

# With custom sound files
./target/release/noisey --sounds-dir ~/my-sounds

# Custom port/host
./target/release/noisey --port 3000 --host 0.0.0.0
```

Then open `http://<device-ip>:8080` on your phone.

## Adding Sound Files

Place `.wav` or `.ogg` files in the `sounds/` directory (or specify with `--sounds-dir`):

```
sounds/
├── rain.wav
├── ocean-waves.ogg
├── thunder.wav
└── wind.ogg
```

Filenames become display names: `ocean-waves.ogg` → "Ocean Waves".

## Raspberry Pi Deployment

### Cross-compile

```bash
# Install cross (one-time)
cargo install cross --git https://github.com/cross-rs/cross

# Build for RPi 3/4/5 (64-bit)
./cross-compile.sh

# Build for RPi 2/3 (32-bit)
./cross-compile.sh armv7
```

### Install on Pi

```bash
scp target/aarch64-unknown-linux-gnu/release/noisey pi@raspberrypi.local:/usr/local/bin/
scp noisey.service pi@raspberrypi.local:/tmp/

ssh pi@raspberrypi.local
sudo mv /tmp/noisey.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now noisey
```

### Prerequisites on Pi

```bash
sudo apt install libasound2-dev
```

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/sounds` | List all sounds with state |
| `POST` | `/api/sounds/:id/toggle` | Toggle a sound on/off |
| `POST` | `/api/sounds/:id/volume` | Set volume `{ "volume": 0.7 }` |
| `POST` | `/api/master-volume` | Set master volume `{ "volume": 0.8 }` |
| `POST` | `/api/sleep-timer` | Set timer `{ "minutes": 60 }` (0 = cancel) |
| `GET` | `/api/status` | Full status |

## License

MIT
