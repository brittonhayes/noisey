#!/usr/bin/env bash
set -euo pipefail

# Cross-compile noisey for Raspberry Pi
#
# Prerequisites:
#   cargo install cross --git https://github.com/cross-rs/cross
#   # or: sudo apt install gcc-aarch64-linux-gnu
#
# Usage:
#   ./cross-compile.sh           # Build for RPi 3/4/5 (64-bit)
#   ./cross-compile.sh armv7     # Build for RPi 2/3 (32-bit)

TARGET="${1:-aarch64}"

case "$TARGET" in
    aarch64|arm64)
        RUST_TARGET="aarch64-unknown-linux-gnu"
        ;;
    armv7|arm32)
        RUST_TARGET="armv7-unknown-linux-gnueabihf"
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [aarch64|armv7]"
        exit 1
        ;;
esac

echo "Building noisey for $RUST_TARGET..."

if command -v cross &> /dev/null; then
    cross build --release --target "$RUST_TARGET"
else
    echo "'cross' not found. Install it with:"
    echo "  cargo install cross --git https://github.com/cross-rs/cross"
    echo ""
    echo "Falling back to cargo build (requires linker for $RUST_TARGET)..."
    cargo build --release --target "$RUST_TARGET"
fi

BINARY="target/$RUST_TARGET/release/noisey"
echo ""
echo "Build complete: $BINARY"
echo ""
echo "Deploy to your Raspberry Pi:"
echo "  scp $BINARY pi@raspberrypi.local:/usr/local/bin/noisey"
echo "  scp noisey.service pi@raspberrypi.local:/etc/systemd/system/"
echo "  ssh pi@raspberrypi.local 'sudo systemctl daemon-reload && sudo systemctl enable --now noisey'"
