import Foundation

let sampleRate: UInt32 = 44100

// MARK: - Fast RNG (xoshiro128+)

/// Real-time safe PRNG. Avoids syscalls that Float.random(in:) would make via arc4random.
struct FastRNG {
    private var s0: UInt32
    private var s1: UInt32
    private var s2: UInt32
    private var s3: UInt32

    init(seed: UInt64 = 0) {
        // Use mach_absolute_time if no seed provided
        let s = seed != 0 ? seed : UInt64(mach_absolute_time())
        // SplitMix64 to initialize state from a single seed
        var z = s &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z = z ^ (z >> 31)
        s0 = UInt32(z & 0xFFFFFFFF)
        s1 = UInt32(z >> 32)
        z = (s &+ 0x9e3779b97f4a7c15 &* 2)
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z = z ^ (z >> 31)
        s2 = UInt32(z & 0xFFFFFFFF)
        s3 = UInt32(z >> 32)
    }

    mutating func next() -> UInt32 {
        let result = s0 &+ s3
        let t = s1 << 9
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = (s3 << 11) | (s3 >> 21) // rotl
        return result
    }

    /// Returns a Float in [-1, 1)
    mutating func nextBipolar() -> Float {
        let bits = next()
        // Convert to [0, 1) then scale to [-1, 1)
        let f = Float(bits >> 8) / Float(1 << 24) // [0, 1)
        return f * 2.0 - 1.0
    }

    /// Returns a Float in [min, max]
    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        let bits = next()
        let f = Float(bits >> 8) / Float(1 << 24)
        return range.lowerBound + f * (range.upperBound - range.lowerBound)
    }
}

// MARK: - White Noise

struct WhiteNoise {
    private var rng: FastRNG

    init() {
        rng = FastRNG()
    }

    mutating func nextSample() -> Float {
        rng.nextBipolar()
    }
}

// MARK: - Pink Noise (Voss-McCartney)

struct PinkNoise {
    private var rng: FastRNG
    private var rows = [Float](repeating: 0, count: 16)
    private var runningSum: Float = 0
    private var index: UInt32 = 0

    init() {
        rng = FastRNG()
        for i in 0..<16 {
            rows[i] = rng.nextBipolar()
            runningSum += rows[i]
        }
    }

    mutating func nextSample() -> Float {
        index = index &+ 1
        let trailing = min(Int(index.trailingZeroBitCount), 15)

        runningSum -= rows[trailing]
        rows[trailing] = rng.nextBipolar()
        runningSum += rows[trailing]

        let sample = runningSum / 16.0
        return max(-1.0, min(1.0, sample))
    }
}

// MARK: - Brown Noise (Random Walk)

struct BrownNoise {
    private var rng: FastRNG
    private var value: Float = 0

    init() {
        rng = FastRNG()
    }

    mutating func nextSample() -> Float {
        let step = rng.nextFloat(in: -0.04...0.04)
        value = max(-1.0, min(1.0, value + step))
        return value
    }
}

// MARK: - One-Pole Low-Pass Filter

struct OnePoleLP {
    private var state: Float = 0
    private let coeff: Float

    init(cutoffHz: Float) {
        let sr = Double(sampleRate)
        let rc = 1.0 / (Double.pi * 2.0 * Double(cutoffHz))
        let dt = 1.0 / sr
        let alpha = dt / (rc + dt)
        coeff = Float(alpha)
    }

    mutating func process(_ input: Float) -> Float {
        state += coeff * (input - state)
        return state
    }
}

// MARK: - Biquad Filter (Audio EQ Cookbook, Direct Form II Transposed)

struct Biquad {
    private var b0: Float
    private var b1: Float
    private var b2: Float
    private var a1: Float
    private var a2: Float
    private var z1: Float = 0
    private var z2: Float = 0

    static func lowPass(freq: Float, q: Float) -> Biquad {
        var bq = Biquad(b0: 0, b1: 0, b2: 0, a1: 0, a2: 0)
        bq.setLowPass(freq: freq, q: q)
        return bq
    }

    static func bandPass(freq: Float, q: Float) -> Biquad {
        let w0 = Float.pi * 2.0 * freq / Float(sampleRate)
        let sinW0 = sin(w0)
        let cosW0 = cos(w0)
        let alpha = sinW0 / (2.0 * q)

        let b0 = alpha
        let b1: Float = 0
        let b2 = -alpha
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha

        return Biquad(
            b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
            a1: a1 / a0, a2: a2 / a0
        )
    }

    mutating func setLowPass(freq: Float, q: Float) {
        let w0 = Float.pi * 2.0 * freq / Float(sampleRate)
        let sinW0 = sin(w0)
        let cosW0 = cos(w0)
        let alpha = sinW0 / (2.0 * q)

        let b1New = 1.0 - cosW0
        let b0New = b1New / 2.0
        let b2New = b0New
        let a0 = 1.0 + alpha
        let a1New = -2.0 * cosW0
        let a2New = 1.0 - alpha

        b0 = b0New / a0
        b1 = b1New / a0
        b2 = b2New / a0
        a1 = a1New / a0
        a2 = a2New / a0
        // Don't reset z1/z2 -- preserves continuity on parameter changes
    }

    mutating func process(_ input: Float) -> Float {
        let out = b0 * input + z1
        z1 = b1 * input - a1 * out + z2
        z2 = b2 * input - a2 * out
        return out
    }
}

// MARK: - Smoothed Random LFO

struct SmoothedRandom {
    private var rng: FastRNG
    var value: Float
    private var target: Float
    private var step: Float
    private var counter: UInt32
    private var interval: UInt32
    private let rangeMin: Float
    private let rangeMax: Float

    init(minRateHz: Float, maxRateHz: Float, rangeMin: Float, rangeMax: Float) {
        rng = FastRNG()
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
        let mid = (rangeMin + rangeMax) / 2.0
        let avgRate = (minRateHz + maxRateHz) / 2.0
        interval = UInt32(Float(sampleRate) / avgRate)
        value = mid
        target = rng.nextFloat(in: rangeMin...rangeMax)
        step = (target - mid) / Float(interval)
        counter = 0
    }

    mutating func nextValue() -> Float {
        counter += 1
        if counter >= interval {
            counter = 0
            target = rng.nextFloat(in: rangeMin...rangeMax)
            let rate = rng.nextFloat(in: 0.5...2.0)
            interval = max(64, UInt32(Float(interval) * rate))
            step = (target - value) / Float(interval)
        }
        value += step
        value = max(rangeMin, min(rangeMax, value))
        return value
    }
}

// MARK: - Smoothed Value (click-free volume/fade)

struct SmoothedValue {
    private(set) var current: Float
    var target: Float
    private let coeff: Float

    init(initial: Float, coeff: Float) {
        current = initial
        target = initial
        self.coeff = coeff
    }

    mutating func set(_ target: Float) {
        self.target = target
    }

    @discardableResult
    mutating func next() -> Float {
        current += coeff * (target - current)
        return current
    }

    var isSettled: Bool {
        abs(current - target) < 1e-6
    }
}
