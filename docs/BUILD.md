# Build Guide: Noisey Sleep Device

A minimal, premium white noise machine with an e-ink status display — like a [TRMNL](https://usetrmnl.com) for sleep.

```
┌─────────────────────────────────┐
│                                 │
│   ┌───────────────────────┐     │
│   │                       │     │
│   │   noisey              │     │
│   │   ─────────────────   │     │
│   │                       │     │
│   │   brown noise ●●●●○○  │     │
│   │                       │     │
│   │   vol 65%             │     │
│   │   sleep 6h 30m        │     │
│   │                       │     │
│   └───────────────────────┘     │
│                                 │
│              ◉                  │
│                                 │
│   ░░░░░░░░░░░░░░░░░░░░░░░░░░   │
│                                 │
└─────────────────────────────────┘
```

## Overview

This guide walks through building a dedicated sleep device:

- **White enclosure** with a clean, minimal design
- **E-ink display** showing current sound, volume, and sleep timer
- **Quality speaker** for rich ambient noise
- **Controlled from your phone** — no buttons needed, just the display
- **Always on** — runs as a systemd service, starts on boot

The display refreshes only when state changes (e-ink is perfect for this — zero power draw between updates, no light emission, readable in darkness with ambient light).

## Parts List

| Part | Recommended Model | Est. Cost |
|------|------------------|-----------|
| Raspberry Pi Zero 2 W | [Pi Zero 2 W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/) | $15 |
| E-ink display | [Waveshare 2.9" e-Paper HAT](https://www.waveshare.com/2.9inch-e-paper-module.htm) (296×128) | $18 |
| Speaker | [Adafruit 3W 4Ω Speaker](https://www.adafruit.com/product/1314) | $8 |
| DAC + Amp | [Adafruit I2S 3W Amp (MAX98357A)](https://www.adafruit.com/product/3006) | $6 |
| MicroSD card | Any 8GB+ Class 10 | $6 |
| USB-C power supply | 5V 2.5A | $8 |
| Enclosure | 3D printed (see below) or off-the-shelf project box | $5–15 |
| **Total** | | **~$66–76** |

### Upgrade Options

| Upgrade | Part | Cost |
|---------|------|------|
| Better audio | [HiFiBerry DAC+ Zero](https://www.hifiberry.com/shop/boards/hifiberry-dac-zero/) | $20 |
| Larger display | [Waveshare 4.2" e-Paper](https://www.waveshare.com/4.2inch-e-paper-module.htm) (400×300) | $28 |
| Full-size Pi | Raspberry Pi 4/5 (overkill but easier to work with) | $35–80 |
| Premium speaker | [Visaton FRS 7](https://www.visaton.de/en/products/fullrange-systems/frs-7-4-ohm) | $15 |

## Assembly

### 1. Prepare the Raspberry Pi

Install Raspberry Pi OS Lite (no desktop):

```bash
# On your computer, use Raspberry Pi Imager
# Select: Raspberry Pi OS Lite (64-bit)
# Configure: WiFi, SSH enabled, hostname: noisey.local
```

Boot the Pi and SSH in:

```bash
ssh pi@noisey.local
```

Install audio dependencies:

```bash
sudo apt update
sudo apt install -y libasound2-dev
```

### 2. Set Up the I2S Amplifier

Wire the MAX98357A to the Pi Zero 2 W:

```
MAX98357A    →  Pi Zero 2 W
─────────────────────────────
VIN          →  5V (pin 2)
GND          →  GND (pin 6)
BCLK         →  GPIO 18 (pin 12)
LRCLK        →  GPIO 19 (pin 35)
DIN          →  GPIO 21 (pin 40)
```

Enable I2S audio:

```bash
# Add to /boot/config.txt
echo "dtoverlay=hifiberry-dac" | sudo tee -a /boot/config.txt

# Create ALSA config
cat <<'EOF' | sudo tee /etc/asound.conf
pcm.!default {
    type hw
    card 0
}
ctl.!default {
    type hw
    card 0
}
EOF

sudo reboot
```

Test audio:

```bash
speaker-test -t sine -f 440 -l 1
```

### 3. Connect the E-ink Display

Wire the Waveshare 2.9" display to the Pi:

```
Waveshare    →  Pi Zero 2 W
─────────────────────────────
VCC          →  3.3V (pin 1)
GND          →  GND (pin 9)
DIN (MOSI)   →  GPIO 10 (pin 19)
CLK (SCLK)   →  GPIO 11 (pin 23)
CS           →  GPIO 8 / CE0 (pin 24)
DC           →  GPIO 25 (pin 22)
RST          →  GPIO 17 (pin 11)
BUSY         →  GPIO 24 (pin 18)
```

If you have the HAT version, it plugs directly into the 40-pin header — no wiring needed.

Enable SPI:

```bash
sudo raspi-config nonint do_spi 0
sudo reboot
```

Verify:

```bash
ls /dev/spidev0.*
# Should show /dev/spidev0.0
```

### 4. Install Noisey

Cross-compile on your development machine:

```bash
# Clone and build
git clone https://github.com/brittonhayes/noisey.git
cd noisey

# Build with e-ink support for Pi Zero 2 W
./cross-compile.sh aarch64
# Or for Pi Zero (v1): ./cross-compile.sh armv7
```

Deploy to the Pi:

```bash
scp target/aarch64-unknown-linux-gnu/release/noisey pi@noisey.local:/usr/local/bin/

# Copy the systemd service
scp noisey.service pi@noisey.local:/tmp/
ssh pi@noisey.local 'sudo mv /tmp/noisey.service /etc/systemd/system/'
```

### 5. Configure the Service

Update the systemd service for e-ink:

```bash
ssh pi@noisey.local
sudo nano /etc/systemd/system/noisey.service
```

```ini
[Unit]
Description=Noisey — ambient noise machine
After=network.target sound.target

[Service]
Type=simple
User=pi
Group=audio
ExecStart=/usr/local/bin/noisey --sounds-dir /home/pi/sounds --eink --eink-refresh 30
Restart=always
RestartSec=5
Environment=RUST_LOG=noisey=info

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now noisey
```

### 6. Verify Everything

```bash
# Check service status
sudo systemctl status noisey

# Check display output (if no hardware, file fallback)
cat /tmp/noisey-display.txt

# Open web UI from your phone
# http://noisey.local:8080
```

## Enclosure Design

The goal is a **premium, minimal, white** product — something you'd see on a nightstand in a boutique hotel.

### Design Principles

- **White matte finish** — 3D print in white PLA/PETG or spray paint
- **No visible screws** — snap-fit or magnetic closure
- **Front: display only** — the e-ink screen is the face
- **Bottom: speaker** — downward-firing into the surface for diffused sound
- **Back: power port** — single USB-C cutout, nothing else
- **No buttons** — all control happens via the phone web UI

### Dimensions

For the 2.9" display build:

```
Width:   90mm
Height: 130mm
Depth:   35mm
```

### 3D Printing

If you have access to a 3D printer:

1. Print the enclosure in white PLA or PETG
2. Use 0.2mm layer height for smooth surfaces
3. Sand with 400 → 800 → 1200 grit sandpaper
4. Optional: spray with white matte primer for a ceramic-like finish

A two-piece design works well:

- **Front shell**: display cutout, speaker grille holes on bottom
- **Back plate**: snap-fit, USB-C port cutout, ventilation slots

### Off-the-Shelf Option

If you don't have a 3D printer:

1. Get a white ABS project box (~100×130×35mm)
2. Cut a rectangular window for the display
3. Drill speaker holes in the bottom
4. Cut a USB-C port hole in the back

## Usage

Once assembled and running, control is entirely from your phone:

1. Open `http://noisey.local:8080` on your phone
2. Tap a sound to start playing
3. Adjust volume with sliders
4. Set a sleep timer
5. The e-ink display reflects the current state

The display shows:
- Which sounds are playing
- Volume level for each active sound
- Master volume percentage
- Sleep timer countdown (if active)

### Adding Custom Sounds

```bash
# SCP sound files to the Pi
scp rain.wav ocean-waves.ogg pi@noisey.local:/home/pi/sounds/

# Restart to pick up new files
ssh pi@noisey.local 'sudo systemctl restart noisey'
```

## Troubleshooting

### No audio output

```bash
# Check ALSA devices
aplay -l

# Test with a WAV file
aplay /usr/share/sounds/alsa/Front_Center.wav

# Check I2S overlay is loaded
dmesg | grep -i i2s
```

### Display not updating

```bash
# Check SPI is enabled
ls /dev/spidev0.0

# Check noisey logs for display errors
journalctl -u noisey -f

# Test GPIO access
cat /sys/class/gpio/gpio25/value
```

### Service won't start

```bash
# Check logs
journalctl -u noisey --no-pager -n 50

# Run manually to see errors
/usr/local/bin/noisey --sounds-dir /home/pi/sounds --eink
```

## Inspiration

This project is inspired by:

- [TRMNL](https://usetrmnl.com) — the minimal e-ink dashboard device
- [Sound+Sleep SE](https://www.soundofsleep.com/) — the commercial sound machine we're replacing
- [Muji wall-mounted CD player](https://www.muji.com/) — the design ethos: white, quiet, intentional
