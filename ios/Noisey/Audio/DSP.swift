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

// MARK: - Comb Filter (for Freeverb)

/// Feedback comb filter with damping. Core building block of Freeverb.
struct CombFilter {
    private var buffer: [Float]
    private var index: Int = 0
    private var filterStore: Float = 0
    private var feedback: Float
    private var damp1: Float
    private var damp2: Float

    init(delayLength: Int, feedback: Float = 0.5, damping: Float = 0.5) {
        buffer = [Float](repeating: 0, count: delayLength)
        self.feedback = feedback
        damp1 = damping
        damp2 = 1.0 - damping
    }

    mutating func setFeedback(_ fb: Float) { feedback = fb }
    mutating func setDamping(_ d: Float) { damp1 = d; damp2 = 1.0 - d }

    mutating func process(_ input: Float) -> Float {
        let output = buffer[index]
        filterStore = output * damp2 + filterStore * damp1
        buffer[index] = input + filterStore * feedback
        index += 1
        if index >= buffer.count { index = 0 }
        return output
    }

    mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
        filterStore = 0
    }
}

// MARK: - Allpass Filter (for Freeverb)

/// Allpass filter for diffusion in Freeverb.
struct AllpassFilter {
    private var buffer: [Float]
    private var index: Int = 0
    private let feedback: Float = 0.5

    init(delayLength: Int) {
        buffer = [Float](repeating: 0, count: delayLength)
    }

    mutating func process(_ input: Float) -> Float {
        let buffered = buffer[index]
        let output = -input + buffered
        buffer[index] = input + buffered * feedback
        index += 1
        if index >= buffer.count { index = 0 }
        return output
    }

    mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
    }
}

// MARK: - Freeverb (Schroeder Reverb)

/// Mono Freeverb implementation. 8 parallel comb filters + 4 series allpass filters.
/// Classic algorithm that sounds great for ambient/atmospheric sounds.
struct Freeverb {
    private var combs: [CombFilter]
    private var allpasses: [AllpassFilter]
    private var wet: Float
    private var dry: Float

    /// - Parameters:
    ///   - roomSize: Feedback amount (0-1). Higher = longer tail. Default 0.7.
    ///   - damping: High-frequency damping (0-1). Higher = darker. Default 0.5.
    ///   - wet: Wet signal level (0-1).
    ///   - dry: Dry signal level (0-1).
    init(roomSize: Float = 0.7, damping: Float = 0.5, wet: Float = 0.3, dry: Float = 0.7) {
        // Freeverb comb filter delay lengths (tuned for 44100 Hz)
        let combLengths = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        // Allpass delay lengths
        let allpassLengths = [556, 441, 341, 225]

        combs = combLengths.map { CombFilter(delayLength: $0, feedback: roomSize, damping: damping) }
        allpasses = allpassLengths.map { AllpassFilter(delayLength: $0) }
        self.wet = wet
        self.dry = dry
    }

    mutating func setRoomSize(_ size: Float) {
        for i in combs.indices { combs[i].setFeedback(size) }
    }

    mutating func setDamping(_ d: Float) {
        for i in combs.indices { combs[i].setDamping(d) }
    }

    mutating func setMix(wet: Float, dry: Float) {
        self.wet = wet
        self.dry = dry
    }

    mutating func process(_ input: Float) -> Float {
        // Scale input to avoid saturation in the comb network
        let scaledInput = input * 0.015

        // Sum parallel comb filters (8 filters, each can contribute up to ±1)
        var combOut: Float = 0
        for i in combs.indices {
            combOut += combs[i].process(scaledInput)
        }

        // Series allpass filters for diffusion
        var output = combOut
        for i in allpasses.indices {
            output = allpasses[i].process(output)
        }

        return dry * input + wet * output
    }

    mutating func clear() {
        for i in combs.indices { combs[i].clear() }
        for i in allpasses.indices { allpasses[i].clear() }
    }
}

// MARK: - Feedback Delay

/// Simple mono delay with feedback. Uses a circular buffer.
struct FeedbackDelay {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private let delaySamples: Int
    private var feedback: Float
    private var wet: Float
    private var dry: Float

    /// - Parameters:
    ///   - timeMs: Delay time in milliseconds.
    ///   - feedback: Feedback amount (0-1). Higher = more repeats.
    ///   - wet: Wet signal level.
    ///   - dry: Dry signal level.
    init(timeMs: Float, feedback: Float = 0.3, wet: Float = 0.2, dry: Float = 0.8) {
        delaySamples = max(1, Int(timeMs * Float(sampleRate) / 1000.0))
        buffer = [Float](repeating: 0, count: delaySamples)
        self.feedback = feedback
        self.wet = wet
        self.dry = dry
    }

    mutating func process(_ input: Float) -> Float {
        let readIndex = writeIndex
        let delayed = buffer[readIndex]
        buffer[writeIndex] = input + delayed * feedback
        writeIndex += 1
        if writeIndex >= delaySamples { writeIndex = 0 }
        return dry * input + wet * delayed
    }

    mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
    }
}

// MARK: - Chorus

/// Mono chorus effect. A short modulated delay line creates pitch-shifting shimmer.
struct Chorus {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var lfoPhase: Float = 0
    private let lfoRate: Float      // Hz
    private let depthSamples: Float // modulation depth in samples
    private let baseDelay: Int      // center delay in samples
    private var wet: Float
    private var dry: Float

    /// - Parameters:
    ///   - rateHz: LFO speed in Hz (typical 0.2-2.0).
    ///   - depthMs: Modulation depth in ms (typical 1-10).
    ///   - wet: Wet signal level.
    ///   - dry: Dry signal level.
    init(rateHz: Float = 0.5, depthMs: Float = 5.0, wet: Float = 0.3, dry: Float = 0.7) {
        lfoRate = rateHz
        depthSamples = depthMs * Float(sampleRate) / 1000.0
        baseDelay = Int(depthSamples * 2) + 1 // ensure enough buffer for modulation
        let bufSize = baseDelay + Int(depthSamples) + 2
        buffer = [Float](repeating: 0, count: bufSize)
        self.wet = wet
        self.dry = dry
    }

    mutating func process(_ input: Float) -> Float {
        buffer[writeIndex] = input

        // LFO generates modulated read position
        let lfo = sinf(lfoPhase * Float.pi * 2.0)
        lfoPhase += lfoRate / Float(sampleRate)
        if lfoPhase >= 1.0 { lfoPhase -= 1.0 }

        let modDelay = Float(baseDelay) + lfo * depthSamples
        let readPos = Float(writeIndex) - modDelay
        let readPosWrapped = readPos < 0 ? readPos + Float(buffer.count) : readPos

        // Linear interpolation for sub-sample delay
        let idx0 = Int(readPosWrapped) % buffer.count
        let idx1 = (idx0 + 1) % buffer.count
        let frac = readPosWrapped - floorf(readPosWrapped)
        let delayed = buffer[idx0] * (1.0 - frac) + buffer[idx1] * frac

        writeIndex += 1
        if writeIndex >= buffer.count { writeIndex = 0 }

        return dry * input + wet * delayed
    }

    mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
    }
}

// MARK: - Vibrato (sine LFO pitch modulator)

/// Sine-wave LFO that returns a frequency multiplier for pitch vibrato.
/// Each instance starts at a random phase so multiple voices don't pulse in sync.
struct Vibrato {
    private var phase: Float
    private let rate: Float       // Hz
    private let depthCents: Float // ± cents of pitch deviation

    init(rateHz: Float, depthCents: Float, rng: inout FastRNG) {
        rate = rateHz
        self.depthCents = depthCents
        phase = rng.nextFloat(in: 0.0...1.0)
    }

    /// Returns a multiplier to apply to frequency (e.g. 1.003 or 0.997).
    mutating func nextMultiplier() -> Float {
        phase += rate / Float(sampleRate)
        if phase >= 1.0 { phase -= 1.0 }
        let cents = depthCents * sinf(phase * Float.pi * 2.0)
        return powf(2.0, cents / 1200.0)
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
