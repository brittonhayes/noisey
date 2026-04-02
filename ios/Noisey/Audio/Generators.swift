import Foundation

// MARK: - Ocean Surf

/// Gentle ocean: brown noise shaped by two overlapping smooth envelopes
/// at different periods, with a soft low-pass for warmth.
struct OceanSurf {
    private var noise = BrownNoise()
    private var lp = OnePoleLP(cutoffHz: 900.0)
    private var phase: (Double, Double) = (0, 0)
    private let phaseInc: (Double, Double)

    init() {
        let sr = Double(sampleRate)
        phaseInc = (
            Double.pi * 2.0 / (10.0 * sr),
            Double.pi * 2.0 / (14.0 * sr)
        )
    }

    mutating func nextSample() -> Float {
        let raw = noise.nextSample()
        let filtered = lp.process(raw)

        let envA = (1.0 - cos(phase.0)) * 0.5
        let envB = (1.0 - cos(phase.1)) * 0.5
        let envelope = Float(max(envA, envB))

        phase.0 += phaseInc.0
        if phase.0 > Double.pi * 2.0 { phase.0 -= Double.pi * 2.0 }
        phase.1 += phaseInc.1
        if phase.1 > Double.pi * 2.0 { phase.1 -= Double.pi * 2.0 }

        return max(-1.0, min(1.0, filtered * envelope * 0.10))
    }
}

// MARK: - Warm Rain

/// Natural rain: pink noise with a wide LP for full-spectrum fidelity,
/// plus a gentle high-frequency texture layer for droplet detail.
struct WarmRain {
    private var washNoise = PinkNoise()
    private var washLP = OnePoleLP(cutoffHz: 3500.0)
    private var detailNoise = WhiteNoise()
    private var detailLP = OnePoleLP(cutoffHz: 6000.0)

    mutating func nextSample() -> Float {
        let washRaw = washNoise.nextSample()
        let wash = washLP.process(washRaw)

        let detailRaw = detailNoise.nextSample()
        let detail = detailLP.process(detailRaw)

        let mix = wash * 0.7 + detail * 0.08
        return max(-1.0, min(1.0, mix * 0.08))
    }
}

// MARK: - Creek Brook

/// Gentle stream: layered filtered noise bands with slow random amplitude
/// modulation. A low brown noise bed provides body while bandpass-filtered
/// pink noise layers with wandering amplitude create the bubbling texture.
struct CreekBrook {
    private var bedNoise = BrownNoise()
    private var bedLP = OnePoleLP(cutoffHz: 400.0)

    private var midNoise = PinkNoise()
    private var midBP = Biquad.bandPass(freq: 800.0, q: 0.8)
    private var midAmp = SmoothedRandom(minRateHz: 0.3, maxRateHz: 0.8, rangeMin: 0.15, rangeMax: 0.5)

    private var highNoise = WhiteNoise()
    private var highBP = Biquad.bandPass(freq: 2200.0, q: 1.0)
    private var highAmp = SmoothedRandom(minRateHz: 0.5, maxRateHz: 1.5, rangeMin: 0.05, rangeMax: 0.3)

    private var shimmerNoise = WhiteNoise()
    private var shimmerBP = Biquad.bandPass(freq: 4000.0, q: 1.2)
    private var shimmerAmp = SmoothedRandom(minRateHz: 0.8, maxRateHz: 2.0, rangeMin: 0.0, rangeMax: 0.15)

    private var sampleCounter: UInt32 = 0

    mutating func nextSample() -> Float {
        sampleCounter &+= 1

        let midVol: Float
        let highVol: Float
        let shimmerVol: Float

        if sampleCounter % 64 == 0 {
            midVol = midAmp.nextValue()
            highVol = highAmp.nextValue()
            shimmerVol = shimmerAmp.nextValue()
        } else {
            midVol = midAmp.value
            highVol = highAmp.value
            shimmerVol = shimmerAmp.value
        }

        let bedRaw = bedNoise.nextSample()
        let bed = bedLP.process(bedRaw) * 0.25

        let midRaw = midNoise.nextSample()
        let mid = midBP.process(midRaw) * midVol

        let highRaw = highNoise.nextSample()
        let high = highBP.process(highRaw) * highVol

        let shimmerRaw = shimmerNoise.nextSample()
        let shimmer = shimmerBP.process(shimmerRaw) * shimmerVol

        let mix = bed + mid + high + shimmer
        return max(-1.0, min(1.0, mix * 0.10))
    }
}

// MARK: - Night Wind

/// White noise through a resonant biquad LP with cutoff modulated by a slow
/// random walk. Amplitude modulated by a separate slow LFO. Gentle breeze.
struct NightWind {
    private var noise = WhiteNoise()
    private var filter = Biquad.lowPass(freq: 600.0, q: 0.7)
    private var cutoffLFO = SmoothedRandom(minRateHz: 0.05, maxRateHz: 0.2, rangeMin: 200.0, rangeMax: 1200.0)
    private var ampLFO = SmoothedRandom(minRateHz: 0.03, maxRateHz: 0.08, rangeMin: 0.3, rangeMax: 0.9)
    private var sampleCounter: UInt32 = 0

    mutating func nextSample() -> Float {
        sampleCounter &+= 1

        if sampleCounter % 64 == 0 {
            let cutoff = cutoffLFO.nextValue()
            let q: Float = 0.5 + (cutoff - 200.0) / 2000.0
            filter.setLowPass(freq: cutoff, q: q)
        }

        let amp: Float = sampleCounter % 64 == 0 ? ampLFO.nextValue() : ampLFO.value

        let raw = noise.nextSample()
        let filtered = filter.process(raw)
        return max(-1.0, min(1.0, filtered * amp * 0.8 * 0.10))
    }
}

// MARK: - Morning Birds

/// Warm sine tones tuned to Gmaj9 chord over a soft pink noise forest-air bed.
/// Zelda-inspired: wide register, long decay tails, gentle vibrato, spacious and nostalgic.
struct MorningBirds {
    private var airNoise = PinkNoise()
    private var airLP = OnePoleLP(cutoffHz: 1200.0)
    private var voices: [BirdVoice]
    private var sampleCounter: UInt32 = 0

    struct BirdVoice {
        var rng: FastRNG
        var phase: Float = 0
        var freq: Float
        var chirpLength: UInt32     // samples per chirp
        var silenceLength: UInt32   // samples between chirps
        var counter: UInt32 = 0
        var isChirping: Bool = false
        var amplitude: Float
        var vibrato: Vibrato
        let detuneMul: Float        // per-voice detuning (±3-5 cents)

        init(baseFreq: Float, seed: UInt64) {
            rng = FastRNG(seed: seed)
            freq = baseFreq
            chirpLength = UInt32(Float(sampleRate) * 0.35)
            silenceLength = UInt32(rng.nextFloat(in: Float(sampleRate) * 2.5...Float(sampleRate) * 7.0))
            amplitude = rng.nextFloat(in: 0.012...0.03)
            vibrato = Vibrato(rateHz: rng.nextFloat(in: 0.8...1.8),
                              depthCents: rng.nextFloat(in: 6...14),
                              rng: &rng)
            let cents = rng.nextFloat(in: -5...5)
            detuneMul = powf(2.0, cents / 1200.0)
        }

        mutating func nextSample() -> Float {
            counter += 1
            if isChirping {
                if counter >= chirpLength {
                    counter = 0
                    isChirping = false
                    silenceLength = UInt32(rng.nextFloat(in: Float(sampleRate) * 3.0...Float(sampleRate) * 8.0))
                    // Pick next chirp pitch from Gmaj9 chord tones
                    freq = Tonality.dayChord.randomTone(in: 250...1800, rng: &rng)
                    return 0
                }
                let t = Float(counter) / Float(chirpLength)
                // Fast attack (~10%), long exponential decay — Zelda fairy-chime envelope
                let env: Float
                if t < 0.1 {
                    env = t / 0.1  // quick linear attack
                } else {
                    let decayT = (t - 0.1) / 0.9
                    env = expf(-1.6 * decayT)  // very long nostalgic decay
                }
                let vibMul = vibrato.nextMultiplier()
                phase += (freq * detuneMul * vibMul) / Float(sampleRate)
                if phase > 1.0 { phase -= 1.0 }
                return sin(phase * Float.pi * 2.0) * env * amplitude
            } else {
                if counter >= silenceLength {
                    counter = 0
                    isChirping = true
                    chirpLength = UInt32(rng.nextFloat(in: Float(sampleRate) * 0.3...Float(sampleRate) * 0.7))
                }
                return 0
            }
        }
    }

    init() {
        let seeds: [UInt64] = [111, 222, 333, 444, 555, 666, 777]
        // Gmaj9 chord tones spanning G3–D6 for wide, nostalgic voicing
        let freqs: [Float] = [
            196.0,   // G3  — low warmth
            220.0,   // A3  — the 9th, dreamy tension
            392.0,   // G4
            493.9,   // B4
            587.3,   // D5
            740.0,   // F#5
            880.0,   // A5  — high 9th sparkle
        ]
        voices = zip(freqs, seeds).map { BirdVoice(baseFreq: $0.0, seed: $0.1) }
    }

    mutating func nextSample() -> Float {
        let airRaw = airNoise.nextSample()
        let air = airLP.process(airRaw) * 0.12

        var chirps: Float = 0
        for i in voices.indices {
            chirps += voices[i].nextSample()
        }

        return max(-1.0, min(1.0, (air + chirps) * 0.35))
    }
}

// MARK: - Forest Canopy

/// Pink noise through a wide bandpass for body, with slow amplitude gusts
/// and a secondary high-frequency leaf-detail layer.
struct ForestCanopy {
    private var bodyNoise = PinkNoise()
    private var bodyBP = Biquad.bandPass(freq: 800.0, q: 0.5)
    private var gustAmp = SmoothedRandom(minRateHz: 0.02, maxRateHz: 0.1, rangeMin: 0.3, rangeMax: 0.7)

    private var leafNoise = WhiteNoise()
    private var leafBP = Biquad.bandPass(freq: 3000.0, q: 0.8)
    private var leafAmp = SmoothedRandom(minRateHz: 0.1, maxRateHz: 0.4, rangeMin: 0.02, rangeMax: 0.12)

    private var sampleCounter: UInt32 = 0

    mutating func nextSample() -> Float {
        sampleCounter &+= 1

        let gust: Float
        let leaf: Float
        if sampleCounter % 64 == 0 {
            gust = gustAmp.nextValue()
            leaf = leafAmp.nextValue()
        } else {
            gust = gustAmp.value
            leaf = leafAmp.value
        }

        let bodyRaw = bodyNoise.nextSample()
        let body = bodyBP.process(bodyRaw) * gust

        let leafRaw = leafNoise.nextSample()
        let leafFiltered = leafBP.process(leafRaw) * leaf

        return max(-1.0, min(1.0, (body + leafFiltered) * 0.10))
    }
}

// MARK: - Meadow Breeze

/// Band-limited white noise (200Hz HP + 2000Hz LP) with very slow amplitude
/// modulation. Clean and airy.
struct MeadowBreeze {
    private var noise = WhiteNoise()
    private var hpLP = OnePoleLP(cutoffHz: 200.0)  // used to subtract for HP effect
    private var outputLP = OnePoleLP(cutoffHz: 2000.0)  // final band limiting
    private var ampLFO = SmoothedRandom(minRateHz: 0.01, maxRateHz: 0.05, rangeMin: 0.3, rangeMax: 0.7)
    private var sampleCounter: UInt32 = 0

    mutating func nextSample() -> Float {
        sampleCounter &+= 1

        let amp: Float = sampleCounter % 64 == 0 ? ampLFO.nextValue() : ampLFO.value

        let raw = noise.nextSample()
        // High-pass: subtract low frequencies
        let lowPart = hpLP.process(raw)
        let highPassed = raw - lowPart
        // Low-pass for band limiting
        let bandLimited = outputLP.process(highPassed)

        return max(-1.0, min(1.0, bandLimited * amp * 0.6 * 0.15))
    }
}

// MARK: - Crickets

/// Warm tonal pulses tuned to Bbm7 chord with gentle vibrato and long decay.
/// Zelda-inspired: soft, unhurried, spacious.
struct Crickets {
    private var bedNoise = PinkNoise()
    private var bedLP = OnePoleLP(cutoffHz: 1000.0)
    private var voices: [CricketVoice]

    struct CricketVoice {
        var rng: FastRNG
        var phase: Float = 0
        var freq: Float
        var chirpOnSamples: UInt32
        var chirpOffSamples: UInt32
        var counter: UInt32 = 0
        var isOn: Bool = false
        let amplitude: Float
        var vibrato: Vibrato
        let detuneMul: Float

        init(freq: Float, onMs: Float, offMs: Float, amp: Float, seed: UInt64) {
            rng = FastRNG(seed: seed)
            self.freq = freq
            self.amplitude = amp
            chirpOnSamples = UInt32(onMs * Float(sampleRate) / 1000.0)
            chirpOffSamples = UInt32(offMs * Float(sampleRate) / 1000.0)
            vibrato = Vibrato(rateHz: rng.nextFloat(in: 0.6...1.4),
                              depthCents: rng.nextFloat(in: 4...10),
                              rng: &rng)
            let cents = rng.nextFloat(in: -4...4)
            detuneMul = powf(2.0, cents / 1200.0)
        }

        mutating func nextSample() -> Float {
            counter += 1
            if isOn {
                if counter >= chirpOnSamples {
                    counter = 0
                    isOn = false
                    chirpOffSamples = UInt32(rng.nextFloat(in: 2000...5000) * Float(sampleRate) / 1000.0)
                    // Pick next pitch from Bbm7 chord tones
                    freq = Tonality.duskChord.randomTone(in: 800...2000, rng: &rng)
                    return 0
                }
                let vibMul = vibrato.nextMultiplier()
                phase += (freq * detuneMul * vibMul) / Float(sampleRate)
                if phase > 1.0 { phase -= 1.0 }
                let t = Float(counter) / Float(chirpOnSamples)
                // Fast attack, long exponential decay
                let env: Float
                if t < 0.08 {
                    env = t / 0.08
                } else {
                    let decayT = (t - 0.08) / 0.92
                    env = expf(-3.0 * decayT)
                }
                return sin(phase * Float.pi * 2.0) * env * amplitude
            } else {
                if counter >= chirpOffSamples {
                    counter = 0
                    isOn = true
                    chirpOnSamples = UInt32(rng.nextFloat(in: 180...400) * Float(sampleRate) / 1000.0)
                }
                return 0
            }
        }
    }

    init() {
        // Bbm7 chord tones: Bb5, Db6, F6, Ab6
        voices = [
            CricketVoice(freq: 932.3, onMs: 250, offMs: 3000, amp: 0.025, seed: 501),   // Bb5
            CricketVoice(freq: 1108.7, onMs: 300, offMs: 3500, amp: 0.02, seed: 502),   // Db6
            CricketVoice(freq: 1396.9, onMs: 200, offMs: 4000, amp: 0.018, seed: 503),  // F6
            CricketVoice(freq: 1661.2, onMs: 220, offMs: 3200, amp: 0.02, seed: 504),   // Ab6
        ]
    }

    mutating func nextSample() -> Float {
        let bedRaw = bedNoise.nextSample()
        let bed = bedLP.process(bedRaw) * 0.04

        var chirps: Float = 0
        for i in voices.indices {
            chirps += voices[i].nextSample()
        }

        return max(-1.0, min(1.0, bed + chirps))
    }
}

// MARK: - Evening Frogs

/// Gentle warm tones tuned to open Bb major pentatonic voicings with slow vibrato
/// and long decay. Calm and zen — no minor intervals, just roots, 5ths, and 9ths.
/// A barely-there sine drone adds harmonic warmth underneath.
///
/// Frog calls are quantized to a 60 BPM beat grid. Each beat, each voice
/// randomly decides whether to croak — creating emergent rhythmic patterns
/// that lock to the pulse but never repeat.
struct EveningFrogs {
    private var windNoise = PinkNoise()
    private var windLPlow = OnePoleLP(cutoffHz: 300.0)   // subtract for HP effect
    private var windLPhigh = OnePoleLP(cutoffHz: 1200.0)  // cap the top end
    private var windAmp = SmoothedRandom(minRateHz: 0.03, maxRateHz: 0.08, rangeMin: 0.02, rangeMax: 0.06)
    private var windCounter: UInt32 = 0
    private var voices: [FrogVoice]
    private var drone: ChordDrone
    /// Samples per 16th note at 60 BPM (smallest grid unit)
    private let sixteenthSamples: UInt32 = UInt32(sampleRate) / 4 // 11025 samples
    private var beatClock: UInt32 = 0
    /// Per-kind momentum: when a frog of one kind croaks, it boosts
    /// momentum for the *other* kinds — call and response between species.
    private var momentum: [FrogKind: Float] = [.bullfrog: 0, .treefrog: 0, .peeper: 0]

    /// Soft pad with open pentatonic voicings — roots, 5ths, and 9ths only.
    /// No minor intervals. Glides gently every ~16 seconds.
    struct ChordDrone {
        /// Bb and F anchored — top voice floats between bright, open tones.
        /// Every voicing is consonant and resolved.
        static let chords: [[Float]] = [
            [116.5, 174.6, 233.1],  // Bb  F  Bb  — pure octave/5th, home
            [116.5, 174.6, 261.6],  // Bb  F  C   — add9, open and calm
            [116.5, 174.6, 293.7],  // Bb  F  D   — major 3rd up top, bright
            [116.5, 174.6, 233.1],  // Bb  F  Bb  — settle back home
        ]

        struct Tone {
            var phase: Float = 0
            var currentFreq: Float
            var targetFreq: Float
            let amp: Float
            let glideCoeff: Float

            init(freq: Float, amp: Float) {
                currentFreq = freq
                targetFreq = freq
                self.amp = amp
                glideCoeff = 1.0 - 1.0 / (0.3 * Float(sampleRate))
            }

            mutating func setTarget(_ freq: Float) {
                targetFreq = freq
            }

            mutating func nextSample() -> Float {
                currentFreq = currentFreq * glideCoeff + targetFreq * (1.0 - glideCoeff)

                phase += currentFreq / Float(sampleRate)
                if phase > 1.0 { phase -= 1.0 }
                let p = phase * Float.pi * 2.0
                let osc = sin(p) + sin(p * 2.0) * 0.5 + sin(p * 3.0) * 0.33
                return osc * amp
            }
        }

        var tones: [Tone]
        var lpA: OnePoleLP
        var lpB: OnePoleLP
        var chordIndex: Int = 0
        var sampleCounter: UInt32 = 0
        let changeSamples: UInt32
        var volPhase: Double = 0
        let volPhaseInc: Double  // slow sine LFO for volume breathing

        init() {
            tones = [
                Tone(freq: 116.5, amp: 0.018),  // bass
                Tone(freq: 174.6, amp: 0.014),  // mid
                Tone(freq: 233.1, amp: 0.010),  // high
            ]
            lpA = OnePoleLP(cutoffHz: 400.0)
            lpB = OnePoleLP(cutoffHz: 400.0)
            changeSamples = UInt32(16.0 * Float(sampleRate))
            // ~25 second full cycle — very slow breathing
            volPhaseInc = Double.pi * 2.0 / (25.0 * Double(sampleRate))
        }

        mutating func nextSample() -> Float {
            sampleCounter &+= 1
            if sampleCounter >= changeSamples {
                sampleCounter = 0
                chordIndex = (chordIndex + 1) % ChordDrone.chords.count
                let chord = ChordDrone.chords[chordIndex]
                for i in tones.indices {
                    tones[i].setTarget(chord[i])
                }
            }

            // Volume breathes between 0.5 and 1.0
            volPhase += volPhaseInc
            if volPhase > Double.pi * 2.0 { volPhase -= Double.pi * 2.0 }
            let vol = Float(0.75 + 0.25 * cos(volPhase))

            var sum: Float = 0
            for i in tones.indices {
                sum += tones[i].nextSample()
            }
            return lpB.process(lpA.process(sum)) * vol
        }
    }

    /// Three species of frog, each with distinct character.
    enum FrogKind: Hashable {
        /// Low, slow, resonant — the big one in the pond
        case bullfrog
        /// Mid-range, moderate pace — the most common voice
        case treefrog
        /// High, quick, bright — tiny and distant
        case peeper
    }

    struct FrogVoice {
        var rng: FastRNG
        var phase: Float = 0
        let baseFreq: Float
        var currentFreq: Float
        var burstLength: UInt32
        var counter: UInt32 = 0
        var isCalling: Bool = false
        var bp: Biquad
        var distanceLP: OnePoleLP
        let maxAmplitude: Float
        /// Per-croak dynamic gain — randomized each time the frog fires
        var croakGain: Float = 1.0
        var vibrato: Vibrato
        let detuneMul: Float
        let density: Float
        let kind: FrogKind
        /// Range for per-croak gain randomization (simulates distance/energy)
        let gainRange: ClosedRange<Float>
        /// Frequency range this species picks from
        let freqRange: ClosedRange<Float>
        /// Burst length range in seconds
        let burstRange: ClosedRange<Float>

        init(freq: Float, amp: Float, density: Float, kind: FrogKind,
             gainRange: ClosedRange<Float>, freqRange: ClosedRange<Float>,
             burstRange: ClosedRange<Float>, lpCutoff: Float, seed: UInt64) {
            rng = FastRNG(seed: seed)
            baseFreq = freq
            currentFreq = freq
            maxAmplitude = amp
            self.density = density
            self.kind = kind
            self.gainRange = gainRange
            self.freqRange = freqRange
            self.burstRange = burstRange
            burstLength = UInt32(Float(sampleRate) * 0.35)
            bp = Biquad.bandPass(freq: freq, q: 1.2)
            distanceLP = OnePoleLP(cutoffHz: lpCutoff)
            vibrato = Vibrato(rateHz: rng.nextFloat(in: 0.4...0.9),
                              depthCents: rng.nextFloat(in: 8...16),
                              rng: &rng)
            let cents = rng.nextFloat(in: -5...5)
            detuneMul = powf(2.0, cents / 1200.0)
        }

        /// Called on each 16th-note boundary. `momentum` is this voice's
        /// species-specific momentum from other species calling.
        /// Returns true if this voice started a croak.
        mutating func onBeat(momentum: Float) -> Bool {
            if isCalling { return false }
            let effectiveDensity = density + momentum * 0.25
            let roll = rng.nextFloat(in: 0.0...1.0)
            if roll < effectiveDensity {
                isCalling = true
                counter = 0
                currentFreq = Tonality.duskChord.randomTone(in: freqRange, rng: &rng)
                burstLength = UInt32(rng.nextFloat(in: burstRange.lowerBound * Float(sampleRate)...burstRange.upperBound * Float(sampleRate)))
                // Randomize this croak's volume — some whisper-quiet, some full
                croakGain = rng.nextFloat(in: gainRange)
                return true
            }
            return false
        }

        mutating func nextSample() -> Float {
            if isCalling {
                counter += 1
                if counter >= burstLength {
                    isCalling = false
                    return 0
                }
                let t = Float(counter) / Float(burstLength)
                let env: Float
                if t < 0.08 {
                    env = t / 0.08
                } else if t < 0.20 {
                    let d = (t - 0.08) / 0.12
                    env = 1.0 - d * 0.4
                } else if t < 0.75 {
                    env = 0.6
                } else {
                    let r = (t - 0.75) / 0.25
                    env = 0.6 * (1.0 - r)
                }
                let vibMul = vibrato.nextMultiplier()
                phase += (currentFreq * detuneMul * vibMul) / Float(sampleRate)
                if phase > 1.0 { phase -= 1.0 }
                let raw = sin(phase * Float.pi * 2.0) * env * maxAmplitude * croakGain
                return distanceLP.process(bp.process(raw))
            } else {
                return 0
            }
        }
    }

    init() {
        // Multiple voices per species at varying "distances" (LP cutoff + gain range).
        // Bullfrogs: low, slow, boomy — some close, some far
        // Treefrogs: mid, moderate — the backbone
        // Peepers:   high, quick, bright — tiny and distant
        voices = [
            // Bullfrogs — low and slow
            FrogVoice(freq: 233.1, amp: 0.035, density: 0.04, kind: .bullfrog,
                      gainRange: 0.3...1.0, freqRange: 150...350,
                      burstRange: 0.4...0.7, lpCutoff: 500.0, seed: 601),
            FrogVoice(freq: 174.6, amp: 0.03, density: 0.03, kind: .bullfrog,
                      gainRange: 0.15...0.6, freqRange: 150...350,
                      burstRange: 0.5...0.8, lpCutoff: 350.0, seed: 602),  // far away

            // Treefrogs — mid range
            FrogVoice(freq: 466.2, amp: 0.028, density: 0.05, kind: .treefrog,
                      gainRange: 0.25...1.0, freqRange: 400...800,
                      burstRange: 0.3...0.5, lpCutoff: 700.0, seed: 611),
            FrogVoice(freq: 554.4, amp: 0.022, density: 0.04, kind: .treefrog,
                      gainRange: 0.1...0.5, freqRange: 400...800,
                      burstRange: 0.25...0.45, lpCutoff: 500.0, seed: 612),  // distant

            // Peepers — high, tiny, quick
            FrogVoice(freq: 698.5, amp: 0.018, density: 0.03, kind: .peeper,
                      gainRange: 0.2...1.0, freqRange: 800...1400,
                      burstRange: 0.15...0.3, lpCutoff: 900.0, seed: 621),
            FrogVoice(freq: 880.0, amp: 0.012, density: 0.02, kind: .peeper,
                      gainRange: 0.1...0.4, freqRange: 800...1400,
                      burstRange: 0.12...0.25, lpCutoff: 600.0, seed: 622),  // very far
        ]
        drone = ChordDrone()
    }

    mutating func nextSample() -> Float {
        // Beat clock — tick all voices on 16th-note boundaries
        if beatClock == 0 {
            // Decay all momentum channels
            for kind in [FrogKind.bullfrog, .treefrog, .peeper] {
                momentum[kind, default: 0] *= 0.65
            }
            // Each voice reads momentum for its own kind, and if it fires
            // it boosts the other kinds (call → response across species)
            for i in voices.indices {
                let kindMomentum = momentum[voices[i].kind, default: 0]
                if voices[i].onBeat(momentum: kindMomentum) {
                    for kind in [FrogKind.bullfrog, .treefrog, .peeper] where kind != voices[i].kind {
                        momentum[kind, default: 0] = min(1.0, momentum[kind, default: 0] + 0.5)
                    }
                }
            }
        }
        beatClock += 1
        if beatClock >= sixteenthSamples { beatClock = 0 }

        // Gentle breeze — band-passed pink noise (300-1200Hz) with slow swell
        windCounter &+= 1
        let wAmp = windCounter % 64 == 0 ? windAmp.nextValue() : windAmp.value
        let wRaw = windNoise.nextSample()
        let wLow = windLPlow.process(wRaw)
        let wBand = windLPhigh.process(wRaw - wLow)  // HP at 300, LP at 1200
        let wind = wBand * wAmp

        let pad = drone.nextSample()

        var calls: Float = 0
        for i in voices.indices {
            calls += voices[i].nextSample()
        }

        return max(-1.0, min(1.0, wind + pad + calls))
    }
}

// MARK: - Twilight Wind

/// Like NightWind but warmer: lower cutoff range, deeper amplitude modulation,
/// slower LFO rates. A deep, enveloping evening breeze.
struct TwilightWind {
    private var noise = WhiteNoise()
    private var filter = Biquad.lowPass(freq: 400.0, q: 0.7)
    private var cutoffLFO = SmoothedRandom(minRateHz: 0.02, maxRateHz: 0.06, rangeMin: 150.0, rangeMax: 600.0)
    private var ampLFO = SmoothedRandom(minRateHz: 0.02, maxRateHz: 0.06, rangeMin: 0.15, rangeMax: 1.0)
    private var sampleCounter: UInt32 = 0

    mutating func nextSample() -> Float {
        sampleCounter &+= 1

        if sampleCounter % 64 == 0 {
            let cutoff = cutoffLFO.nextValue()
            let q: Float = 0.5 + (cutoff - 150.0) / 900.0
            filter.setLowPass(freq: cutoff, q: q)
        }

        let amp: Float = sampleCounter % 64 == 0 ? ampLFO.nextValue() : ampLFO.value

        let raw = noise.nextSample()
        let filtered = filter.process(raw)
        return max(-1.0, min(1.0, filtered * amp * 0.8 * 0.10))
    }
}

// MARK: - Procedural Generator

/// Class wrapper for generators. Reference semantics means no copying on every sample.
/// The generator structs mutate in-place through the class indirection.
final class ProceduralGenerator {
    private enum Kind {
        case oceanSurf(OceanSurf)
        case warmRain(WarmRain)
        case creekBrook(CreekBrook)
        case nightWind(NightWind)
        case morningBirds(MorningBirds)
        case forestCanopy(ForestCanopy)
        case meadowBreeze(MeadowBreeze)
        case crickets(Crickets)
        case eveningFrogs(EveningFrogs)
        case twilightWind(TwilightWind)
    }

    private var kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    static func create(id: String) -> ProceduralGenerator? {
        switch id {
        case "ocean-surf": return ProceduralGenerator(kind: .oceanSurf(OceanSurf()))
        case "warm-rain": return ProceduralGenerator(kind: .warmRain(WarmRain()))
        case "creek": return ProceduralGenerator(kind: .creekBrook(CreekBrook()))
        case "night-wind": return ProceduralGenerator(kind: .nightWind(NightWind()))
        case "morning-birds": return ProceduralGenerator(kind: .morningBirds(MorningBirds()))
        case "forest-canopy": return ProceduralGenerator(kind: .forestCanopy(ForestCanopy()))
        case "meadow-breeze": return ProceduralGenerator(kind: .meadowBreeze(MeadowBreeze()))
        case "crickets": return ProceduralGenerator(kind: .crickets(Crickets()))
        case "evening-frogs": return ProceduralGenerator(kind: .eveningFrogs(EveningFrogs()))
        case "twilight-wind": return ProceduralGenerator(kind: .twilightWind(TwilightWind()))
        default: return nil
        }
    }

    func nextSample() -> Float {
        switch kind {
        case .oceanSurf(var gen):
            let s = gen.nextSample()
            kind = .oceanSurf(gen)
            return s
        case .warmRain(var gen):
            let s = gen.nextSample()
            kind = .warmRain(gen)
            return s
        case .creekBrook(var gen):
            let s = gen.nextSample()
            kind = .creekBrook(gen)
            return s
        case .nightWind(var gen):
            let s = gen.nextSample()
            kind = .nightWind(gen)
            return s
        case .morningBirds(var gen):
            let s = gen.nextSample()
            kind = .morningBirds(gen)
            return s
        case .forestCanopy(var gen):
            let s = gen.nextSample()
            kind = .forestCanopy(gen)
            return s
        case .meadowBreeze(var gen):
            let s = gen.nextSample()
            kind = .meadowBreeze(gen)
            return s
        case .crickets(var gen):
            let s = gen.nextSample()
            kind = .crickets(gen)
            return s
        case .eveningFrogs(var gen):
            let s = gen.nextSample()
            kind = .eveningFrogs(gen)
            return s
        case .twilightWind(var gen):
            let s = gen.nextSample()
            kind = .twilightWind(gen)
            return s
        }
    }
}
