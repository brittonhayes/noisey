use rand::rngs::SmallRng;
use rand::{Rng, SeedableRng};

pub const SAMPLE_RATE: u32 = 44100;

/// A trait for audio sources that produce f32 samples.
pub trait SoundSource: Iterator<Item = f32> + Send {}

// ============================================================
// DSP Primitives
// ============================================================

// --- White Noise ---

struct WhiteNoise {
    rng: SmallRng,
}

impl WhiteNoise {
    fn new() -> Self {
        Self {
            rng: SmallRng::from_entropy(),
        }
    }
}

impl Iterator for WhiteNoise {
    type Item = f32;
    fn next(&mut self) -> Option<f32> {
        Some(self.rng.gen_range(-1.0..1.0))
    }
}

// --- One-Pole Low-Pass Filter ---

struct OnePoleLP {
    state: f32,
    coeff: f32,
}

impl OnePoleLP {
    fn new(cutoff_hz: f32) -> Self {
        let sr = SAMPLE_RATE as f64;
        let rc = 1.0 / (std::f64::consts::TAU * cutoff_hz as f64);
        let dt = 1.0 / sr;
        let alpha = dt / (rc + dt);
        Self {
            state: 0.0,
            coeff: alpha as f32,
        }
    }

    fn process(&mut self, input: f32) -> f32 {
        self.state += self.coeff * (input - self.state);
        self.state
    }
}

// --- Biquad Filter (Audio EQ Cookbook) ---

#[derive(Clone)]
pub struct Biquad {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    // Direct Form II Transposed state
    z1: f32,
    z2: f32,
}

impl Biquad {
    pub fn low_pass(freq: f32, q: f32) -> Self {
        let mut bq = Self {
            b0: 0.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            z1: 0.0,
            z2: 0.0,
        };
        bq.set_low_pass(freq, q);
        bq
    }

    fn band_pass(freq: f32, q: f32) -> Self {
        let w0 = std::f32::consts::TAU * freq / SAMPLE_RATE as f32;
        let (sin_w0, cos_w0) = w0.sin_cos();
        let alpha = sin_w0 / (2.0 * q);

        let b0 = alpha;
        let b1 = 0.0;
        let b2 = -alpha;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_w0;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            z1: 0.0,
            z2: 0.0,
        }
    }

    pub fn set_low_pass(&mut self, freq: f32, q: f32) {
        let w0 = std::f32::consts::TAU * freq / SAMPLE_RATE as f32;
        let (sin_w0, cos_w0) = w0.sin_cos();
        let alpha = sin_w0 / (2.0 * q);

        let b1 = 1.0 - cos_w0;
        let b0 = b1 / 2.0;
        let b2 = b0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_w0;
        let a2 = 1.0 - alpha;

        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = a1 / a0;
        self.a2 = a2 / a0;
        // Don't reset z1/z2 — preserves continuity on parameter changes
    }

    pub fn process(&mut self, input: f32) -> f32 {
        let out = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * out + self.z2;
        self.z2 = self.b2 * input - self.a2 * out;
        out
    }
}

// --- Smoothed Random LFO ---

struct SmoothedRandom {
    rng: SmallRng,
    value: f32,
    target: f32,
    step: f32,
    counter: u32,
    interval: u32,
    range_min: f32,
    range_max: f32,
}

impl SmoothedRandom {
    /// Create a smoothed random LFO that changes direction at a rate
    /// between `min_rate_hz` and `max_rate_hz`, outputting values in
    /// `[range_min, range_max]`.
    fn new(min_rate_hz: f32, max_rate_hz: f32, range_min: f32, range_max: f32) -> Self {
        let mut rng = SmallRng::from_entropy();
        let mid = (range_min + range_max) / 2.0;
        let avg_rate = (min_rate_hz + max_rate_hz) / 2.0;
        let interval = (SAMPLE_RATE as f32 / avg_rate) as u32;
        let target = rng.gen_range(range_min..=range_max);
        let step = (target - mid) / interval as f32;
        Self {
            rng,
            value: mid,
            target,
            step,
            counter: 0,
            interval,
            range_min,
            range_max,
        }
    }

    fn next_value(&mut self) -> f32 {
        self.counter += 1;
        if self.counter >= self.interval {
            self.counter = 0;
            // Pick new target and interval
            self.target = self.rng.gen_range(self.range_min..=self.range_max);
            let rate = self.rng.gen_range(0.5_f32..2.0);
            self.interval = ((self.interval as f32) * rate).max(64.0) as u32;
            self.step = (self.target - self.value) / self.interval as f32;
        }
        self.value += self.step;
        self.value = self.value.clamp(self.range_min, self.range_max);
        self.value
    }
}

// ============================================================
// Base Noise Generators (used internally by the 5 sounds)
// ============================================================

// --- Pink Noise (Voss-McCartney algorithm) ---

pub(crate) struct PinkNoise {
    rng: SmallRng,
    rows: [f32; 16],
    running_sum: f32,
    index: u32,
}

impl PinkNoise {
    pub(crate) fn new() -> Self {
        let mut rng = SmallRng::from_entropy();
        let mut rows = [0.0f32; 16];
        let mut running_sum = 0.0;
        for row in &mut rows {
            *row = rng.gen_range(-1.0..1.0);
            running_sum += *row;
        }
        Self {
            rng,
            rows,
            running_sum,
            index: 0,
        }
    }
}

impl Iterator for PinkNoise {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        self.index = self.index.wrapping_add(1);
        let trailing = self.index.trailing_zeros() as usize;
        let row_idx = trailing.min(self.rows.len() - 1);
        self.running_sum -= self.rows[row_idx];
        self.rows[row_idx] = self.rng.gen_range(-1.0..1.0);
        self.running_sum += self.rows[row_idx];
        let sample = self.running_sum / 16.0;
        Some(sample.clamp(-1.0, 1.0))
    }
}

// --- Brown Noise (Brownian / random walk) ---

pub(crate) struct BrownNoise {
    rng: SmallRng,
    value: f32,
}

impl BrownNoise {
    pub(crate) fn new() -> Self {
        Self {
            rng: SmallRng::from_entropy(),
            value: 0.0,
        }
    }
}

impl Iterator for BrownNoise {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        let step = self.rng.gen_range(-0.04..0.04);
        self.value = (self.value + step).clamp(-1.0, 1.0);
        Some(self.value)
    }
}

// ============================================================
// The 4 Sleep Sounds
// ============================================================

// --- 1. Ocean Surf ---

/// Gentle ocean: brown noise shaped by two overlapping smooth envelopes
/// at different periods, with a soft low-pass for warmth. No harsh processing.
pub struct OceanSurf {
    noise: BrownNoise,
    lp: OnePoleLP,
    phase: [f64; 2],
    phase_inc: [f64; 2],
}

impl OceanSurf {
    pub fn new() -> Self {
        let sr = SAMPLE_RATE as f64;
        Self {
            noise: BrownNoise::new(),
            lp: OnePoleLP::new(900.0),
            phase: [0.0, 0.0],
            phase_inc: [
                std::f64::consts::TAU / (10.0 * sr),
                std::f64::consts::TAU / (14.0 * sr),
            ],
        }
    }
}

impl Iterator for OceanSurf {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        let raw = self.noise.next().unwrap_or(0.0);
        let filtered = self.lp.process(raw);

        // Two smooth overlapping envelopes
        let env_a = (1.0 - self.phase[0].cos()) * 0.5;
        let env_b = (1.0 - self.phase[1].cos()) * 0.5;
        let envelope = env_a.max(env_b) as f32;

        // Advance phases
        for i in 0..2 {
            self.phase[i] += self.phase_inc[i];
            if self.phase[i] > std::f64::consts::TAU {
                self.phase[i] -= std::f64::consts::TAU;
            }
        }

        Some((filtered * envelope).clamp(-1.0, 1.0))
    }
}

impl SoundSource for OceanSurf {}

// --- 2. Warm Rain ---

/// Natural rain: pink noise with a wide LP for full-spectrum fidelity,
/// plus a gentle high-frequency texture layer for droplet detail.
pub struct WarmRain {
    wash_noise: PinkNoise,
    wash_lp: OnePoleLP,

    detail_noise: WhiteNoise,
    detail_lp: OnePoleLP,
}

impl WarmRain {
    pub fn new() -> Self {
        Self {
            wash_noise: PinkNoise::new(),
            wash_lp: OnePoleLP::new(3500.0),

            detail_noise: WhiteNoise::new(),
            detail_lp: OnePoleLP::new(6000.0),
        }
    }
}

impl Iterator for WarmRain {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        let wash_raw = self.wash_noise.next().unwrap_or(0.0);
        let wash = self.wash_lp.process(wash_raw);

        let detail_raw = self.detail_noise.next().unwrap_or(0.0);
        let detail = self.detail_lp.process(detail_raw);

        let mix = wash * 0.7 + detail * 0.08;
        Some(mix.clamp(-1.0, 1.0))
    }
}

impl SoundSource for WarmRain {}

// --- 3. Creek ---

/// Gentle stream: layered filtered noise bands with slow random amplitude
/// modulation. A low brown noise bed provides body while bandpass-filtered
/// pink noise layers with wandering amplitude create the bubbling texture.
pub struct CreekBrook {
    bed_noise: BrownNoise,
    bed_lp: OnePoleLP,

    mid_noise: PinkNoise,
    mid_bp: Biquad,
    mid_amp: SmoothedRandom,

    high_noise: WhiteNoise,
    high_bp: Biquad,
    high_amp: SmoothedRandom,

    shimmer_noise: WhiteNoise,
    shimmer_bp: Biquad,
    shimmer_amp: SmoothedRandom,

    sample_counter: u32,
}

impl CreekBrook {
    pub fn new() -> Self {
        Self {
            bed_noise: BrownNoise::new(),
            bed_lp: OnePoleLP::new(400.0),

            mid_noise: PinkNoise::new(),
            mid_bp: Biquad::band_pass(800.0, 0.8),
            mid_amp: SmoothedRandom::new(0.3, 0.8, 0.15, 0.5),

            high_noise: WhiteNoise::new(),
            high_bp: Biquad::band_pass(2200.0, 1.0),
            high_amp: SmoothedRandom::new(0.5, 1.5, 0.05, 0.3),

            shimmer_noise: WhiteNoise::new(),
            shimmer_bp: Biquad::band_pass(4000.0, 1.2),
            shimmer_amp: SmoothedRandom::new(0.8, 2.0, 0.0, 0.15),

            sample_counter: 0,
        }
    }
}

impl Iterator for CreekBrook {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        self.sample_counter += 1;

        // Update amplitude LFOs every 64 samples
        let (mid_vol, high_vol, shimmer_vol) = if self.sample_counter.is_multiple_of(64) {
            (
                self.mid_amp.next_value(),
                self.high_amp.next_value(),
                self.shimmer_amp.next_value(),
            )
        } else {
            (
                self.mid_amp.value,
                self.high_amp.value,
                self.shimmer_amp.value,
            )
        };

        // Low bed: steady brown noise rumble
        let bed_raw = self.bed_noise.next().unwrap_or(0.0);
        let bed = self.bed_lp.process(bed_raw) * 0.25;

        // Mid band: filtered pink noise with wandering amplitude
        let mid_raw = self.mid_noise.next().unwrap_or(0.0);
        let mid = self.mid_bp.process(mid_raw) * mid_vol;

        // High band: filtered white noise, more variation
        let high_raw = self.high_noise.next().unwrap_or(0.0);
        let high = self.high_bp.process(high_raw) * high_vol;

        // Shimmer: very high, very quiet, fast-varying
        let shimmer_raw = self.shimmer_noise.next().unwrap_or(0.0);
        let shimmer = self.shimmer_bp.process(shimmer_raw) * shimmer_vol;

        let mix = bed + mid + high + shimmer;
        Some(mix.clamp(-1.0, 1.0))
    }
}

impl SoundSource for CreekBrook {}

// --- 4. Night Wind ---

/// White noise through a resonant biquad LP with cutoff modulated by a slow
/// random walk. Amplitude modulated by a separate slow LFO. Gentle breeze.
pub struct NightWind {
    noise: WhiteNoise,
    filter: Biquad,
    cutoff_lfo: SmoothedRandom,
    amp_lfo: SmoothedRandom,
    sample_counter: u32,
}

impl NightWind {
    pub fn new() -> Self {
        Self {
            noise: WhiteNoise::new(),
            filter: Biquad::low_pass(600.0, 0.7),
            cutoff_lfo: SmoothedRandom::new(0.05, 0.2, 200.0, 1200.0),
            amp_lfo: SmoothedRandom::new(0.03, 0.08, 0.3, 0.9),
            sample_counter: 0,
        }
    }
}

impl Iterator for NightWind {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        self.sample_counter += 1;

        if self.sample_counter.is_multiple_of(64) {
            let cutoff = self.cutoff_lfo.next_value();
            let q = 0.5 + (cutoff - 200.0) / 2000.0;
            self.filter.set_low_pass(cutoff, q);
        }

        let amp = if self.sample_counter.is_multiple_of(64) {
            self.amp_lfo.next_value()
        } else {
            self.amp_lfo.value
        };

        let raw = self.noise.next().unwrap_or(0.0);
        let filtered = self.filter.process(raw);
        Some((filtered * amp * 0.8).clamp(-1.0, 1.0))
    }
}

impl SoundSource for NightWind {}

// ============================================================
// Tests
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn test_generator_range(name: &str, mut gen: impl Iterator<Item = f32>) {
        let samples: Vec<f32> = gen.by_ref().take(44100 * 3).collect();
        for (i, &s) in samples.iter().enumerate() {
            assert!(
                (-1.0..=1.0).contains(&s),
                "{name}: sample {i} out of range: {s}"
            );
            assert!(!s.is_nan(), "{name}: sample {i} is NaN");
        }
    }

    fn test_generator_not_silent(name: &str, mut gen: impl Iterator<Item = f32>) {
        let samples: Vec<f32> = gen.by_ref().take(44100 * 3).collect();
        let rms = (samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32).sqrt();
        assert!(rms > 0.001, "{name}: appears silent (RMS={rms})");
    }

    #[test]
    fn ocean_surf_range() {
        test_generator_range("OceanSurf", OceanSurf::new());
    }

    #[test]
    fn ocean_surf_not_silent() {
        test_generator_not_silent("OceanSurf", OceanSurf::new());
    }

    #[test]
    fn warm_rain_range() {
        test_generator_range("WarmRain", WarmRain::new());
    }

    #[test]
    fn warm_rain_not_silent() {
        test_generator_not_silent("WarmRain", WarmRain::new());
    }

    #[test]
    fn creek_range() {
        test_generator_range("CreekBrook", CreekBrook::new());
    }

    #[test]
    fn creek_not_silent() {
        test_generator_not_silent("CreekBrook", CreekBrook::new());
    }

    #[test]
    fn night_wind_range() {
        test_generator_range("NightWind", NightWind::new());
    }

    #[test]
    fn night_wind_not_silent() {
        test_generator_not_silent("NightWind", NightWind::new());
    }

    #[test]
    fn biquad_stability() {
        let mut filter = Biquad::low_pass(1000.0, 0.707);
        let mut rng = SmallRng::seed_from_u64(42);
        for _ in 0..44100 {
            let input = rng.gen_range(-1.0_f32..1.0);
            let out = filter.process(input);
            assert!(!out.is_nan(), "Biquad output NaN");
            assert!(!out.is_infinite(), "Biquad output infinite");
        }
    }

    #[test]
    fn biquad_update_stability() {
        let mut filter = Biquad::low_pass(5000.0, 0.707);
        let mut rng = SmallRng::seed_from_u64(42);
        for i in 0..44100 {
            if i % 64 == 0 {
                let freq = 300.0 + (i as f32 / 44100.0) * 19700.0;
                filter.set_low_pass(freq, 0.707);
            }
            let input = rng.gen_range(-1.0_f32..1.0);
            let out = filter.process(input);
            assert!(
                !out.is_nan(),
                "Biquad output NaN after update at sample {i}"
            );
        }
    }

    #[test]
    fn smoothed_random_bounds() {
        let mut lfo = SmoothedRandom::new(0.1, 0.5, 100.0, 500.0);
        for i in 0..44100 * 5 {
            let val = lfo.next_value();
            assert!(
                (100.0..=500.0).contains(&val),
                "SmoothedRandom out of bounds at sample {i}: {val}"
            );
        }
    }
}
