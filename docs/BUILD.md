# Build Guide: Noisey White Noise Machine

A dedicated IoT white noise machine you control from your phone — built with a Raspberry Pi, an I2S amplifier, and a speaker in a simple wooden enclosure.

```
    ┌──────────────────────────────┐
    │  ┌──┐                        │
    │  │Pi│   ┌───────┐            │
    │  └──┘   │MAX    │            │
    │         │98357A │   ┌────┐   │
    │         └───────┘   │spkr│   │
    │    ○ ○ ○ ○ ○ ○ ○    └────┘   │
    │    ○ ○ ○ ○ ○ ○ ○  speaker    │
    │    ○ ○ ○ ○ ○ ○ ○  grille     │
    │              ┌─┐             │
    └──────────────│U│─────────────┘
                   └─┘ USB-C
```

**What you get:**

- 4 built-in sounds — Ocean Surf, Warm Rain, Creek, Night Wind
- Upload your own sounds (WAV, OGG, MP3, M4A, AAC, FLAC)
- Control everything from your phone — volume, sleep timer, schedule
- WiFi setup mode — no keyboard or monitor needed
- No buttons, no screen, just sound

## Parts List

| Part | Model | Est. Cost |
|------|-------|-----------|
| Raspberry Pi Zero 2 W | [Pi Zero 2 W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/) | $15 |
| I2S DAC + Amp | [Adafruit MAX98357A](https://www.adafruit.com/product/3006) | $6 |
| Speaker | [3W 4Ω Speaker](https://www.adafruit.com/product/1314) | $8 |
| MicroSD card | Any 8GB+ Class 10 | $6 |
| USB-C power supply | 5V 2.5A | $8 |
| Enclosure | Wooden box or repurposed item (see below) | $0–15 |
| **Total** | | **~$43–58** |

You'll also need: soldering iron, solder, hookup wire, hot glue or mounting tape.

### Optional Upgrades

| Upgrade | Part | Cost |
|---------|------|------|
| Better audio | [HiFiBerry DAC+ Zero](https://www.hifiberry.com/shop/boards/hifiberry-dac-zero/) | $20 |
| Premium speaker | [Visaton FRS 7](https://www.visaton.de/en/products/fullrange-systems/frs-7-4-ohm) | $15 |
| E-ink display | [Waveshare 2.9" e-Paper HAT](https://www.waveshare.com/2.9inch-e-paper-module.htm) — see appendix | $18 |

## Step 1: Flash Raspberry Pi OS

On your computer, download and run [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

1. **Choose OS** → Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)
2. **Choose Storage** → your microSD card
3. **Click the gear icon** (or Ctrl+Shift+X) to configure:
   - Set hostname: `noisey`
   - Enable SSH (password authentication)
   - Set username: `pi`, set a password
   - Configure your WiFi network (SSID and password)
   - Set locale/timezone
4. **Write** the image to the card

Insert the card into the Pi, plug in power, and wait about 90 seconds for first boot.

```bash
ssh pi@noisey.local
```

Install the packages noisey needs:

```bash
sudo apt update
sudo apt install -y libasound2-dev network-manager
```

NetworkManager is required for the WiFi setup feature. Enable it as the network backend:

```bash
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# Disable the default dhcpcd so NetworkManager takes over
sudo systemctl disable dhcpcd
sudo systemctl stop dhcpcd
sudo reboot
```

SSH back in after reboot:

```bash
ssh pi@noisey.local
```

## Step 2: Wire the I2S Amplifier

Solder five wires between the MAX98357A breakout and the Pi Zero 2 W header:

```
MAX98357A    →  Pi Zero 2 W
─────────────────────────────
VIN          →  5V (pin 2)
GND          →  GND (pin 6)
BCLK         →  GPIO 18 (pin 12)
LRCLK        →  GPIO 19 (pin 35)
DIN          →  GPIO 21 (pin 40)
```

Then solder the speaker wires to the **+** and **−** pads on the MAX98357A.

**Tips:**

- Keep wires short (5–8 cm) to reduce noise
- Use solid-core hookup wire for the signal lines
- Solder, don't breadboard — breadboard connections rattle loose
- Heat-shrink or tape any exposed joints

## Step 3: Enable I2S Audio

Add the I2S device tree overlay:

```bash
# Newer Pi OS (Bookworm+) uses /boot/firmware/config.txt
# Older Pi OS uses /boot/config.txt — check which exists
echo "dtoverlay=hifiberry-dac" | sudo tee -a /boot/firmware/config.txt
```

Create the ALSA configuration:

```bash
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
```

Reboot and test:

```bash
sudo reboot
# After reboot, SSH back in
speaker-test -t sine -f 440 -l 1
```

You should hear a tone from the speaker. If not, see the troubleshooting section.

## Step 4: Build and Deploy Noisey

On your development machine (not the Pi), cross-compile the binary:

```bash
git clone https://github.com/brittonhayes/noisey.git
cd noisey

# Install the cross-compilation tool
cargo install cross --git https://github.com/cross-rs/cross

# Build with WiFi support for Pi Zero 2 W (64-bit)
cross build --release --features wifi --target aarch64-unknown-linux-gnu
```

> **Note:** The included `cross-compile.sh` script doesn't pass feature flags,
> so use the `cross` command directly for WiFi-enabled builds.

Deploy to the Pi:

```bash
# Copy the binary
scp target/aarch64-unknown-linux-gnu/release/noisey pi@noisey.local:/tmp/
ssh pi@noisey.local 'sudo mv /tmp/noisey /usr/local/bin/noisey'

# Create the sounds directory
ssh pi@noisey.local 'mkdir -p /home/pi/sounds'

# Copy and install the systemd service
scp noisey.service pi@noisey.local:/tmp/
ssh pi@noisey.local 'sudo mv /tmp/noisey.service /etc/systemd/system/'
```

## Step 5: Configure and Start the Service

SSH into the Pi and edit the service file:

```bash
ssh pi@noisey.local
sudo nano /etc/systemd/system/noisey.service
```

Set the contents to:

```ini
[Unit]
Description=Noisey - Ambient Sound Machine
After=sound.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/noisey --sounds-dir /home/pi/sounds --setup
Restart=always
RestartSec=5
User=pi
Group=audio
SupplementaryGroups=netdev
Environment=RUST_LOG=noisey=info

[Install]
WantedBy=multi-user.target
```

The `--setup` flag tells noisey to start a WiFi hotspot on boot if it can't reach a saved network. The `netdev` group grants access to NetworkManager.

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now noisey
```

## Step 6: WiFi Setup

If this is the first boot (or the Pi can't connect to a saved network), noisey automatically creates a WiFi hotspot.

1. On your phone, open WiFi settings and connect to:
   - **Network:** `Noisey-Setup`
   - **Password:** `noisey42`
2. Open a browser and go to **`http://10.42.0.1:8080`**
3. The setup page scans for available networks — tap yours and enter the password
4. Noisey connects to your WiFi and the hotspot shuts down
5. Reconnect your phone to your home WiFi
6. Open **`http://noisey.local:8080`** — you should see the noisey web UI

The Pi remembers your WiFi network across reboots. If it ever loses connectivity, the hotspot comes back automatically so you can reconfigure.

To force back into setup mode later, restart the service — the `--setup` flag checks connectivity on each boot.

> **Tip:** If `noisey.local` doesn't resolve, find the Pi's IP with:
> `ssh pi@noisey.local 'hostname -I'` or check your router's device list.

## Step 7: The Enclosure

The goal is simple: a clean box that hides the electronics and lets the speaker breathe. Wood sounds warm and looks great on a nightstand.

### Option A: Wooden Craft Box

A small unfinished wooden box from a craft store (roughly 10 × 13 × 5 cm).

1. **Speaker grille** — drill a grid of 3–4mm holes in the top or front panel for sound to exit
2. **Power port** — drill or file a slot in the back panel for the USB-C cable
3. **Mount the speaker** — hot glue or screw it behind the drilled holes, facing outward
4. **Mount the boards** — attach the Pi and MAX98357A with foam tape, standoffs, or small screws
5. **Line the interior** with a scrap of felt to dampen rattles
6. **Finish** — sand smooth, then oil, stain, or paint to taste

### Option B: Cigar Box

Cedar cigar boxes are the perfect size, already finished, and cost a few dollars at tobacco shops or online.

- The wood gives a warm, natural look
- Just drill speaker holes in the lid and a cable slot in the back
- The hinged lid makes accessing the internals easy

### Option C: Vintage Find

Thrift stores are full of small wooden boxes, old radios, clock cases, and jewelry boxes:

- **Old wooden radio** — often has an existing speaker grille you can reuse
- **Wooden clock case** — gut the mechanism, mount your hardware inside
- **Wooden jewelry box** — compact and usually well-finished
- **Small wooden drawer** — from a dismantled piece of furniture

Any of these gives the device character and keeps electronics out of the landfill.

### Option D: Simple DIY

Cut six pieces of 6mm plywood or pine and glue them into a box. Sand, stain, done. This is the cheapest and most customizable option.

### Mounting Tips

- **Ventilation** — leave a few small gaps or drill vent holes to prevent overheating
- **MicroSD access** — position the Pi so you can reach the card slot, or use a microSD extension cable
- **Speaker placement** — the speaker sounds best facing an opening with a small sealed air chamber behind it
- **Cable routing** — size the USB-C hole snugly around the cable for a clean look
- **Secure the boards** — foam mounting tape works well and dampens vibration

## Using Noisey

Open **`http://noisey.local:8080`** on any device on your network.

The web UI features a moon visualization that reflects the current volume. From here you can:

- **Play a sound** — tap any of the 4 built-in sounds (Ocean Surf, Warm Rain, Creek, Night Wind)
- **Adjust volume** — swipe the moon or use the volume dots
- **Set a sleep timer** — choose from 1 min to 8 hours; sound fades out when it expires
- **Set a schedule** — e.g., start Ocean Surf at 22:00, stop at 07:00 (supports overnight windows)
- **Upload custom sounds** — tap the + button, pick a file (WAV, OGG, MP3, M4A, AAC, FLAC, up to 100 MB)
- **Delete custom sounds** — long-press or use the delete button on any uploaded sound

Your schedule is saved to `~/.config/noisey/schedule.json` and persists across reboots.

## Troubleshooting

### No audio output

```bash
# List ALSA devices — you should see the I2S card
aplay -l

# Test directly
aplay /usr/share/sounds/alsa/Front_Center.wav

# Check the I2S overlay loaded
dmesg | grep -i i2s

# Make sure config.txt has the overlay
grep hifiberry /boot/firmware/config.txt
```

If `aplay -l` shows no devices, double-check your wiring and that `dtoverlay=hifiberry-dac` is in the config.

### Service won't start

```bash
# Check logs
journalctl -u noisey --no-pager -n 50

# Run manually to see errors
/usr/local/bin/noisey --sounds-dir /home/pi/sounds --simulate
```

The `--simulate` flag runs without audio hardware, useful for testing the web UI.

### Can't find "Noisey-Setup" hotspot

- Verify the binary was built with `--features wifi`
- Check that `--setup` is in the ExecStart line of the service file
- Ensure NetworkManager is running: `systemctl status NetworkManager`
- Check noisey logs: `journalctl -u noisey -f`

### Can't reach the web UI

- Try the IP address directly instead of `noisey.local`: `hostname -I`
- Verify the service is running: `sudo systemctl status noisey`
- Check the port isn't blocked: `curl http://localhost:8080`

### Uploaded sound won't play

- Check the file format is supported (WAV, OGG, MP3, M4A, AAC, FLAC)
- Check `journalctl -u noisey` for decode errors
- Try a different file — some encodings may not be supported

## Appendix: Optional E-ink Display

If you later add a [Waveshare 2.9" e-Paper HAT](https://www.waveshare.com/2.9inch-e-paper-module.htm), rebuild with both features:

```bash
cross build --release --features eink,wifi --target aarch64-unknown-linux-gnu
```

Add the display flags to your service file's ExecStart:

```
ExecStart=/usr/local/bin/noisey --sounds-dir /home/pi/sounds --setup --eink --eink-refresh 30
```

Enable SPI on the Pi:

```bash
sudo raspi-config nonint do_spi 0
sudo reboot
```

Wiring (if not using the plug-in HAT version):

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

The display shows the active sound, volume level, and sleep timer countdown — refreshing only when state changes.

## Inspiration

- [Sound+Sleep SE](https://www.soundofsleep.com/) — the commercial sound machine we're replacing
- [Muji wall-mounted CD player](https://www.muji.com/) — the design ethos: simple, quiet, intentional
- [/r/DIYElectronics](https://www.reddit.com/r/diyelectronics/) — endless enclosure ideas
