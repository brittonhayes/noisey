use crate::server::SharedState;
use tracing::{error, info, warn};

/// Default e-ink display dimensions (Waveshare 2.9")
pub const EINK_WIDTH: u32 = 296;
pub const EINK_HEIGHT: u32 = 128;

/// Display configuration for e-ink hardware.
#[derive(Debug, Clone)]
pub struct DisplayConfig {
    /// SPI device path (e.g., /dev/spidev0.0)
    pub spi_device: String,
    /// GPIO pin for Data/Command (BCM numbering)
    pub dc_pin: u8,
    /// GPIO pin for Reset
    pub rst_pin: u8,
    /// GPIO pin for Busy signal
    pub busy_pin: u8,
    /// Refresh interval in seconds
    pub refresh_secs: u64,
}

impl Default for DisplayConfig {
    fn default() -> Self {
        Self {
            spi_device: "/dev/spidev0.0".into(),
            dc_pin: 25,
            rst_pin: 17,
            busy_pin: 24,
            refresh_secs: 30,
        }
    }
}

/// Render the current application status into a framebuffer-style text layout.
/// Returns a vector of lines representing the e-ink display content.
///
/// The layout is designed for a 2.9" or 4.2" Waveshare e-ink display
/// with a clean, minimalist aesthetic matching the device design.
pub async fn render_status(state: &SharedState) -> DisplayFrame {
    let state = state.read().await;
    let status = state.status();

    let mut lines: Vec<String> = Vec::new();

    // Header
    lines.push(String::new());
    lines.push("  noisey".to_string());
    lines.push("  ─────────────────────────".to_string());

    // Active sounds
    let active_sounds: Vec<_> = status.sounds.iter().filter(|s| s.active).collect();

    if active_sounds.is_empty() {
        lines.push(String::new());
        lines.push("  silence".to_string());
        lines.push(String::new());
    } else {
        lines.push(String::new());
        for sound in &active_sounds {
            lines.push(format!("  {}", sound.name.to_lowercase()));
        }
        lines.push(String::new());
    }

    // Master volume
    let master_pct = (status.master_volume * 100.0) as u8;
    lines.push(format!("  vol {}%", master_pct));

    // Sleep timer
    if let Some(timer) = &status.sleep_timer {
        let remaining = timer.remaining_secs;
        let hours = remaining / 3600;
        let minutes = (remaining % 3600) / 60;
        if hours > 0 {
            lines.push(format!("  sleep {}h {}m", hours, minutes));
        } else {
            lines.push(format!("  sleep {}m", minutes));
        }
    }

    lines.push(String::new());

    DisplayFrame { lines }
}

/// A rendered frame ready to send to the e-ink display.
#[derive(Debug, Clone)]
pub struct DisplayFrame {
    pub lines: Vec<String>,
}

impl DisplayFrame {
    /// Convert to a single string for logging or file-based display output.
    pub fn to_text(&self) -> String {
        self.lines.join("\n")
    }

    /// Convert to a 1-bit bitmap buffer for e-ink displays.
    /// Each pixel is one bit: 0 = black, 1 = white.
    /// Text is rendered using a simple built-in 5x7 bitmap font.
    ///
    /// Returns (width, height, buffer) where buffer is packed bits,
    /// MSB first, row-major order.
    pub fn to_bitmap(&self, width: u32, height: u32) -> Vec<u8> {
        let mut buf = vec![0xFFu8; (width * height).div_ceil(8) as usize];
        render_into_bitmap(&mut buf, width, height, &self.lines);
        buf
    }

    /// Render to a 1-bit BMP file (black and white only).
    /// Returns the raw bytes of a valid .bmp file you can open in any image viewer.
    /// This is the exact pixel-for-pixel representation of what the e-ink display shows.
    pub fn to_bmp(&self, width: u32, height: u32) -> Vec<u8> {
        // BMP row stride: each row padded to 4-byte boundary (1 bit per pixel)
        let row_stride = width.div_ceil(32) * 4;
        let pixel_data_size = row_stride * height;
        let header_size: u32 = 14 + 40 + 8; // file header + DIB header + 2-color palette
        let file_size = header_size + pixel_data_size;

        let mut bmp = Vec::with_capacity(file_size as usize);

        // -- BMP File Header (14 bytes) --
        bmp.extend_from_slice(b"BM");
        bmp.extend_from_slice(&file_size.to_le_bytes());
        bmp.extend_from_slice(&0u16.to_le_bytes()); // reserved
        bmp.extend_from_slice(&0u16.to_le_bytes()); // reserved
        bmp.extend_from_slice(&header_size.to_le_bytes()); // pixel data offset

        // -- BITMAPINFOHEADER (40 bytes) --
        bmp.extend_from_slice(&40u32.to_le_bytes()); // header size
        bmp.extend_from_slice(&(width as i32).to_le_bytes());
        bmp.extend_from_slice(&(height as i32).to_le_bytes());
        bmp.extend_from_slice(&1u16.to_le_bytes()); // color planes
        bmp.extend_from_slice(&1u16.to_le_bytes()); // bits per pixel
        bmp.extend_from_slice(&0u32.to_le_bytes()); // no compression
        bmp.extend_from_slice(&pixel_data_size.to_le_bytes());
        bmp.extend_from_slice(&2835u32.to_le_bytes()); // h pixels/meter (~72 DPI)
        bmp.extend_from_slice(&2835u32.to_le_bytes()); // v pixels/meter
        bmp.extend_from_slice(&2u32.to_le_bytes()); // colors in palette
        bmp.extend_from_slice(&0u32.to_le_bytes()); // important colors

        // -- Color Table (8 bytes: 2 entries × 4 bytes BGRA) --
        // Index 0 = black (for set bits in our convention, but BMP 1-bit:
        // palette[0] maps to 0-bits, palette[1] maps to 1-bits)
        // Our bitmap: 1 = white, 0 = black. So palette[0] = black, palette[1] = white.
        bmp.extend_from_slice(&[0x00, 0x00, 0x00, 0x00]); // palette[0] = black
        bmp.extend_from_slice(&[0xFF, 0xFF, 0xFF, 0x00]); // palette[1] = white

        // -- Pixel Data --
        // Render into our raw bitmap first
        let raw = self.to_bitmap(width, height);

        // BMP stores rows bottom-to-top
        let mut pixel_data = vec![0xFFu8; (row_stride * height) as usize];
        for y in 0..height {
            let bmp_row = (height - 1 - y) as usize;
            let dst_offset = bmp_row * row_stride as usize;
            let src_bit_offset = y * width;

            for x in 0..width {
                let src_bit = src_bit_offset + x;
                let src_byte = (src_bit / 8) as usize;
                let src_shift = 7 - (src_bit % 8);
                let pixel = (raw[src_byte] >> src_shift) & 1;

                let dst_byte = dst_offset + (x / 8) as usize;
                let dst_shift = 7 - (x % 8);
                if pixel == 0 {
                    // black pixel: clear bit
                    pixel_data[dst_byte] &= !(1 << dst_shift);
                }
                // white pixel: bit already set (0xFF init)
            }
        }

        bmp.extend_from_slice(&pixel_data);
        bmp
    }
}

/// Render text lines into a 1-bit packed bitmap buffer.
/// Buffer must be pre-filled with 0xFF (white). Black pixels are cleared.
fn render_into_bitmap(buf: &mut [u8], width: u32, height: u32, lines: &[String]) {
    let char_w = 6u32; // 5px char + 1px spacing
    let char_h = 9u32; // 7px char + 2px line spacing
    let margin_top = 8u32;

    for (row, line) in lines.iter().enumerate() {
        let y_origin = margin_top + row as u32 * char_h;
        if y_origin + 7 > height {
            break;
        }
        for (col, ch) in line.chars().enumerate() {
            let x_origin = col as u32 * char_w;
            if x_origin + 5 > width {
                break;
            }
            let glyph = font_glyph(ch);
            for gy in 0..7u32 {
                for gx in 0..5u32 {
                    if glyph[gy as usize] & (1 << (4 - gx)) != 0 {
                        let px = x_origin + gx;
                        let py = y_origin + gy;
                        let bit_idx = py * width + px;
                        let byte_idx = (bit_idx / 8) as usize;
                        let bit_pos = 7 - (bit_idx % 8);
                        if byte_idx < buf.len() {
                            buf[byte_idx] &= !(1 << bit_pos); // set black
                        }
                    }
                }
            }
        }
    }
}

/// Spawn the e-ink display refresh loop.
/// Reads shared state periodically and outputs the rendered frame.
///
/// On real hardware, this writes to the e-ink display via SPI.
/// When hardware is unavailable, it writes to /tmp/noisey-display.txt
/// for development and testing.
pub fn spawn_display_thread(state: SharedState, config: DisplayConfig) {
    let rt = tokio::runtime::Handle::current();

    std::thread::spawn(move || {
        info!(
            "E-ink display thread started (refresh every {}s)",
            config.refresh_secs
        );

        // Try to initialize hardware display
        let hw = EinkHardware::try_init(&config);
        if hw.is_none() {
            warn!("E-ink hardware not available — writing to /tmp/noisey-display.txt instead");
        }

        let mut last_text = String::new();

        loop {
            std::thread::sleep(std::time::Duration::from_secs(config.refresh_secs));

            let frame = rt.block_on(render_status(&state));
            let text = frame.to_text();

            // Only refresh if content changed (e-ink displays have limited write cycles)
            if text == last_text {
                continue;
            }
            last_text = text.clone();

            if let Some(hw) = &hw {
                match hw.update(&frame) {
                    Ok(()) => info!("E-ink display updated"),
                    Err(e) => error!("E-ink display update failed: {e}"),
                }
            } else {
                // Fallback: write text + BMP preview for development
                if let Err(e) = std::fs::write("/tmp/noisey-display.txt", &text) {
                    error!("Failed to write display output: {e}");
                }
                let bmp = frame.to_bmp(EINK_WIDTH, EINK_HEIGHT);
                if let Err(e) = std::fs::write("/tmp/noisey-display.bmp", &bmp) {
                    error!("Failed to write display BMP: {e}");
                } else {
                    info!("Display preview written to /tmp/noisey-display.bmp");
                }
            }
        }
    });
}

/// Hardware abstraction for Waveshare e-ink displays.
///
/// Communicates via SPI with GPIO control pins. Supports common
/// Waveshare displays:
/// - 2.13" (250×122) — compact, fits small enclosures
/// - 2.9"  (296×128) — recommended, good balance of size and info
/// - 4.2"  (400×300) — larger, more detailed status
struct EinkHardware {
    width: u32,
    height: u32,
    spi_path: String,
    dc_pin: u8,
    rst_pin: u8,
    busy_pin: u8,
}

impl EinkHardware {
    /// Attempt to initialize the e-ink display hardware.
    /// Returns None if SPI or GPIO is not available (e.g., development machine).
    fn try_init(config: &DisplayConfig) -> Option<Self> {
        // Check if SPI device exists
        if !std::path::Path::new(&config.spi_device).exists() {
            info!(
                "SPI device {} not found, skipping hardware display",
                config.spi_device
            );
            return None;
        }

        // Check if GPIO is available (Raspberry Pi)
        if !std::path::Path::new("/sys/class/gpio").exists() {
            info!("GPIO not available, skipping hardware display");
            return None;
        }

        // Export and configure GPIO pins
        if let Err(e) = Self::setup_gpio(config.dc_pin, "out") {
            warn!("Failed to setup DC pin {}: {e}", config.dc_pin);
            return None;
        }
        if let Err(e) = Self::setup_gpio(config.rst_pin, "out") {
            warn!("Failed to setup RST pin {}: {e}", config.rst_pin);
            return None;
        }
        if let Err(e) = Self::setup_gpio(config.busy_pin, "in") {
            warn!("Failed to setup BUSY pin {}: {e}", config.busy_pin);
            return None;
        }

        // Hardware reset
        let hw = Self {
            width: EINK_WIDTH,
            height: EINK_HEIGHT,
            spi_path: config.spi_device.clone(),
            dc_pin: config.dc_pin,
            rst_pin: config.rst_pin,
            busy_pin: config.busy_pin,
        };

        if let Err(e) = hw.reset() {
            warn!("E-ink reset failed: {e}");
            return None;
        }

        if let Err(e) = hw.init_display() {
            warn!("E-ink init failed: {e}");
            return None;
        }

        info!("E-ink display initialized ({}×{})", hw.width, hw.height);
        Some(hw)
    }

    fn setup_gpio(pin: u8, direction: &str) -> Result<(), std::io::Error> {
        let export_path = "/sys/class/gpio/export";
        let pin_dir = format!("/sys/class/gpio/gpio{pin}");

        if !std::path::Path::new(&pin_dir).exists() {
            std::fs::write(export_path, pin.to_string())?;
            // Brief delay for sysfs to create the node
            std::thread::sleep(std::time::Duration::from_millis(100));
        }

        std::fs::write(format!("{pin_dir}/direction"), direction)?;
        Ok(())
    }

    fn gpio_write(&self, pin: u8, value: bool) -> Result<(), std::io::Error> {
        std::fs::write(
            format!("/sys/class/gpio/gpio{pin}/value"),
            if value { "1" } else { "0" },
        )
    }

    fn gpio_read(&self, pin: u8) -> Result<bool, std::io::Error> {
        let val = std::fs::read_to_string(format!("/sys/class/gpio/gpio{pin}/value"))?;
        Ok(val.trim() == "1")
    }

    fn reset(&self) -> Result<(), std::io::Error> {
        self.gpio_write(self.rst_pin, true)?;
        std::thread::sleep(std::time::Duration::from_millis(200));
        self.gpio_write(self.rst_pin, false)?;
        std::thread::sleep(std::time::Duration::from_millis(10));
        self.gpio_write(self.rst_pin, true)?;
        std::thread::sleep(std::time::Duration::from_millis(200));
        Ok(())
    }

    fn wait_busy(&self) -> Result<(), std::io::Error> {
        // Wait until BUSY pin goes low (display ready)
        for _ in 0..400 {
            if !self.gpio_read(self.busy_pin)? {
                return Ok(());
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        warn!("E-ink busy timeout");
        Ok(())
    }

    fn spi_write(&self, data: &[u8]) -> Result<(), std::io::Error> {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .open(&self.spi_path)?;
        file.write_all(data)?;
        Ok(())
    }

    fn send_command(&self, cmd: u8) -> Result<(), std::io::Error> {
        self.gpio_write(self.dc_pin, false)?; // command mode
        self.spi_write(&[cmd])
    }

    fn send_data(&self, data: &[u8]) -> Result<(), std::io::Error> {
        self.gpio_write(self.dc_pin, true)?; // data mode
        self.spi_write(data)
    }

    /// Initialize the Waveshare 2.9" e-ink display (SSD1680 controller).
    fn init_display(&self) -> Result<(), std::io::Error> {
        self.wait_busy()?;
        self.send_command(0x12)?; // SW Reset
        self.wait_busy()?;

        self.send_command(0x01)?; // Driver Output Control
        self.send_data(&[0x27, 0x01, 0x00])?;

        self.send_command(0x11)?; // Data Entry Mode
        self.send_data(&[0x03])?;

        // Set RAM X address range
        self.send_command(0x44)?;
        self.send_data(&[0x00, 0x0F])?; // 0–15 (128/8 - 1)

        // Set RAM Y address range
        self.send_command(0x45)?;
        self.send_data(&[0x00, 0x00, 0x27, 0x01])?; // 0–295

        self.send_command(0x21)?; // Display Update Control
        self.send_data(&[0x00, 0x80])?;

        self.send_command(0x3C)?; // Border waveform
        self.send_data(&[0x05])?; // white border

        self.send_command(0x18)?; // Temperature sensor
        self.send_data(&[0x80])?; // internal

        self.wait_busy()?;
        Ok(())
    }

    /// Send a rendered frame to the display.
    fn update(&self, frame: &DisplayFrame) -> Result<(), std::io::Error> {
        let bitmap = frame.to_bitmap(self.width, self.height);

        // Set cursor to origin
        self.send_command(0x4E)?;
        self.send_data(&[0x00])?;
        self.send_command(0x4F)?;
        self.send_data(&[0x00, 0x00])?;

        // Write RAM (Black/White)
        self.send_command(0x24)?;
        self.send_data(&bitmap)?;

        // Trigger display refresh
        self.send_command(0x22)?;
        self.send_data(&[0xF7])?;
        self.send_command(0x20)?;
        self.wait_busy()?;

        Ok(())
    }
}

/// Minimal 5×7 bitmap font for e-ink rendering.
/// Returns the 7-row bitmap for a character, each row is 5 bits wide.
fn font_glyph(ch: char) -> [u8; 7] {
    match ch {
        ' ' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        'a' => [0x00, 0x00, 0x0E, 0x01, 0x0F, 0x11, 0x0F],
        'b' => [0x10, 0x10, 0x1E, 0x11, 0x11, 0x11, 0x1E],
        'c' => [0x00, 0x00, 0x0E, 0x11, 0x10, 0x11, 0x0E],
        'd' => [0x01, 0x01, 0x0F, 0x11, 0x11, 0x11, 0x0F],
        'e' => [0x00, 0x00, 0x0E, 0x11, 0x1F, 0x10, 0x0E],
        'f' => [0x06, 0x09, 0x08, 0x1C, 0x08, 0x08, 0x08],
        'g' => [0x00, 0x00, 0x0F, 0x11, 0x0F, 0x01, 0x0E],
        'h' => [0x10, 0x10, 0x16, 0x19, 0x11, 0x11, 0x11],
        'i' => [0x04, 0x00, 0x0C, 0x04, 0x04, 0x04, 0x0E],
        'j' => [0x02, 0x00, 0x06, 0x02, 0x02, 0x12, 0x0C],
        'k' => [0x10, 0x10, 0x12, 0x14, 0x18, 0x14, 0x12],
        'l' => [0x0C, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        'm' => [0x00, 0x00, 0x1A, 0x15, 0x15, 0x11, 0x11],
        'n' => [0x00, 0x00, 0x16, 0x19, 0x11, 0x11, 0x11],
        'o' => [0x00, 0x00, 0x0E, 0x11, 0x11, 0x11, 0x0E],
        'p' => [0x00, 0x00, 0x1E, 0x11, 0x1E, 0x10, 0x10],
        'q' => [0x00, 0x00, 0x0F, 0x11, 0x0F, 0x01, 0x01],
        'r' => [0x00, 0x00, 0x16, 0x19, 0x10, 0x10, 0x10],
        's' => [0x00, 0x00, 0x0E, 0x10, 0x0E, 0x01, 0x1E],
        't' => [0x08, 0x08, 0x1C, 0x08, 0x08, 0x09, 0x06],
        'u' => [0x00, 0x00, 0x11, 0x11, 0x11, 0x13, 0x0D],
        'v' => [0x00, 0x00, 0x11, 0x11, 0x11, 0x0A, 0x04],
        'w' => [0x00, 0x00, 0x11, 0x11, 0x15, 0x15, 0x0A],
        'x' => [0x00, 0x00, 0x11, 0x0A, 0x04, 0x0A, 0x11],
        'y' => [0x00, 0x00, 0x11, 0x11, 0x0F, 0x01, 0x0E],
        'z' => [0x00, 0x00, 0x1F, 0x02, 0x04, 0x08, 0x1F],
        'A' => [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        'B' => [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        'C' => [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        'D' => [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
        'E' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        'F' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        'G' => [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0E],
        'H' => [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        'I' => [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        'J' => [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        'K' => [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        'L' => [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        'M' => [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        'N' => [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
        'O' => [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        'P' => [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        'Q' => [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        'R' => [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        'S' => [0x0E, 0x11, 0x10, 0x0E, 0x01, 0x11, 0x0E],
        'T' => [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        'U' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        'V' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        'W' => [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
        'X' => [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        'Y' => [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
        'Z' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        '0' => [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        '1' => [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        '2' => [0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F],
        '3' => [0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E],
        '4' => [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        '5' => [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        '6' => [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        '7' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        '8' => [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        '9' => [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        '%' => [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
        '─' | '-' => [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        '●' => [0x00, 0x0E, 0x1F, 0x1F, 0x1F, 0x0E, 0x00],
        '○' => [0x00, 0x0E, 0x11, 0x11, 0x11, 0x0E, 0x00],
        '.' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        ':' => [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        _ => [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // unknown → blank
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_display_frame_to_text() {
        let frame = DisplayFrame {
            lines: vec!["  noisey".to_string(), "  vol 80%".to_string()],
        };
        let text = frame.to_text();
        assert!(text.contains("noisey"));
        assert!(text.contains("vol 80%"));
    }

    #[test]
    fn test_bitmap_dimensions() {
        let frame = DisplayFrame {
            lines: vec!["test".to_string()],
        };
        let bitmap = frame.to_bitmap(296, 128);
        assert_eq!(bitmap.len(), (296 * 128 + 7) / 8);
    }

    #[test]
    fn test_font_glyph_space_is_blank() {
        let glyph = font_glyph(' ');
        assert!(glyph.iter().all(|&row| row == 0));
    }

    #[test]
    fn test_bmp_is_valid() {
        let frame = DisplayFrame {
            lines: vec!["  noisey".to_string(), "  vol 50%".to_string()],
        };
        let bmp = frame.to_bmp(EINK_WIDTH, EINK_HEIGHT);

        // Check BMP magic bytes
        assert_eq!(&bmp[0..2], b"BM");

        // Check bits per pixel = 1
        let bpp = u16::from_le_bytes([bmp[28], bmp[29]]);
        assert_eq!(bpp, 1);

        // Check dimensions
        let w = i32::from_le_bytes([bmp[18], bmp[19], bmp[20], bmp[21]]);
        let h = i32::from_le_bytes([bmp[22], bmp[23], bmp[24], bmp[25]]);
        assert_eq!(w, EINK_WIDTH as i32);
        assert_eq!(h, EINK_HEIGHT as i32);

        // Check file size matches actual data
        let file_size = u32::from_le_bytes([bmp[2], bmp[3], bmp[4], bmp[5]]);
        assert_eq!(file_size as usize, bmp.len());

        // Palette: index 0 should be black, index 1 should be white
        let palette_offset = 14 + 40; // after file header + DIB header
        assert_eq!(&bmp[palette_offset..palette_offset + 3], &[0, 0, 0]); // black
        assert_eq!(
            &bmp[palette_offset + 4..palette_offset + 7],
            &[0xFF, 0xFF, 0xFF]
        ); // white
    }

    #[test]
    fn test_bmp_has_black_pixels() {
        let frame = DisplayFrame {
            lines: vec!["test".to_string()],
        };
        let bmp = frame.to_bmp(EINK_WIDTH, EINK_HEIGHT);
        let data_offset = u32::from_le_bytes([bmp[10], bmp[11], bmp[12], bmp[13]]) as usize;
        let pixel_data = &bmp[data_offset..];

        // Not all white — some text was rendered as black pixels (cleared bits)
        assert!(pixel_data.iter().any(|&b| b != 0xFF));
    }
}
