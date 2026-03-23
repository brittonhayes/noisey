use rand::rngs::SmallRng;
use rand::{Rng, SeedableRng};
use rodio::Source;
use std::time::Duration;

const SAMPLE_RATE: u32 = 44100;

// --- White Noise ---

pub struct WhiteNoise {
    rng: SmallRng,
}

impl WhiteNoise {
    pub fn new() -> Self {
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

impl Source for WhiteNoise {
    fn current_frame_len(&self) -> Option<usize> {
        None
    }

    fn channels(&self) -> u16 {
        1
    }

    fn sample_rate(&self) -> u32 {
        SAMPLE_RATE
    }

    fn total_duration(&self) -> Option<Duration> {
        None
    }
}

// --- Pink Noise (Voss-McCartney algorithm) ---

pub struct PinkNoise {
    rng: SmallRng,
    rows: [f32; 16],
    running_sum: f32,
    index: u32,
}

impl PinkNoise {
    pub fn new() -> Self {
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

impl Source for PinkNoise {
    fn current_frame_len(&self) -> Option<usize> {
        None
    }

    fn channels(&self) -> u16 {
        1
    }

    fn sample_rate(&self) -> u32 {
        SAMPLE_RATE
    }

    fn total_duration(&self) -> Option<Duration> {
        None
    }
}

// --- Brown Noise (Brownian / random walk) ---

pub struct BrownNoise {
    rng: SmallRng,
    value: f32,
}

impl BrownNoise {
    pub fn new() -> Self {
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

impl Source for BrownNoise {
    fn current_frame_len(&self) -> Option<usize> {
        None
    }

    fn channels(&self) -> u16 {
        1
    }

    fn sample_rate(&self) -> u32 {
        SAMPLE_RATE
    }

    fn total_duration(&self) -> Option<Duration> {
        None
    }
}
