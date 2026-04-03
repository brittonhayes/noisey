import Foundation

// MARK: - Shared: Chord Drone

/// A slow chord drone: anchored root tones with a drifting color tone,
/// dual low-pass filtering, and volume breathing via sine LFO.
/// Used by MidnightForest, MorningBirds, and EveningFrogs.
struct ChordDrone {
    struct Tone {
        var phase: Float = 0
        var currentFreq: Float
        var targetFreq: Float
        let amp: Float
        let glideCoeff: Float
        let h2: Float
        let h3: Float

        init(freq: Float, amp: Float, h2: Float, h3: Float) {
            currentFreq = freq
            targetFreq = freq
            self.amp = amp
            glideCoeff = 1.0 - 1.0 / (0.3 * Float(sampleRate))
            self.h2 = h2
            self.h3 = h3
        }

        mutating func setTarget(_ freq: Float) { targetFreq = freq }

        mutating func nextSample() -> Float {
            currentFreq = currentFreq * glideCoeff + targetFreq * (1.0 - glideCoeff)
            phase += currentFreq / Float(sampleRate)
            if phase > 1.0 { phase -= 1.0 }
            let p = phase * Float.pi * 2.0
            let osc = sin(p) + sin(p * 2.0) * h2 + sin(p * 3.0) * h3
            return osc * amp
        }
    }

    private let chords: [[Float]]
    private var tones: [Tone]
    private var lpA: OnePoleLP
    private var lpB: OnePoleLP
    private var chordIndex: Int = 0
    private var sampleCounter: UInt32 = 0
    private let changeSamples: UInt32
    private var volPhase: Double = 0
    private let volPhaseInc: Double
    private let volMin: Float
    private let volRange: Float

    /// - Parameters:
    ///   - chords: Array of chord voicings, each an array of frequencies.
    ///   - toneAmps: Per-tone amplitudes (must match chord voice count).
    ///   - lpCutoff: Low-pass cutoff for the dual filter.
    ///   - changePeriod: Seconds between chord changes.
    ///   - breathPeriod: Seconds for one full volume breathing cycle.
    ///   - volMin: Minimum volume in the breathing cycle.
    ///   - volRange: Volume swing (volMin + volRange at peak).
    ///   - h2: 2nd harmonic amplitude coefficient.
    ///   - h3: 3rd harmonic amplitude coefficient.
    init(chords: [[Float]], toneAmps: [Float], lpCutoff: Float,
         changePeriod: Float, breathPeriod: Float,
         volMin: Float, volRange: Float, h2: Float, h3: Float) {
        self.chords = chords
        self.volMin = volMin
        self.volRange = volRange
        let initial = chords[0]
        tones = zip(initial, toneAmps).map { Tone(freq: $0.0, amp: $0.1, h2: h2, h3: h3) }
        lpA = OnePoleLP(cutoffHz: lpCutoff)
        lpB = OnePoleLP(cutoffHz: lpCutoff)
        changeSamples = UInt32(changePeriod * Float(sampleRate))
        volPhaseInc = Double.pi * 2.0 / (Double(breathPeriod) * Double(sampleRate))
    }

    mutating func nextSample() -> Float {
        sampleCounter &+= 1
        if sampleCounter >= changeSamples {
            sampleCounter = 0
            chordIndex = (chordIndex + 1) % chords.count
            let chord = chords[chordIndex]
            for i in tones.indices { tones[i].setTarget(chord[i]) }
        }
        volPhase += volPhaseInc
        if volPhase > Double.pi * 2.0 { volPhase -= Double.pi * 2.0 }
        let vol = volMin + volRange * Float(cos(volPhase))
        var sum: Float = 0
        for i in tones.indices { sum += tones[i].nextSample() }
        return lpB.process(lpA.process(sum)) * vol
    }
}

// MARK: - Shared: Creature Voice

/// A sine-tone voice with bandpass + distance LP filtering, vibrato, detuning,
/// per-call gain randomization, and a configurable amplitude envelope.
/// Used for owls, birds, and frogs.
struct CreatureVoice {
    var rng: FastRNG
    var phase: Float = 0
    let baseFreq: Float
    var currentFreq: Float
    var callLength: UInt32
    var counter: UInt32 = 0
    var isActive: Bool = false
    var bp: Biquad
    var distanceLP: OnePoleLP
    let maxAmplitude: Float
    var callGain: Float = 1.0
    var vibrato: Vibrato
    let detuneMul: Float
    let density: Float
    /// Species index — voices with the same index share a momentum channel.
    let species: Int
    let gainRange: ClosedRange<Float>
    let freqRange: ClosedRange<Float>
    let callRange: ClosedRange<Float>
    let scale: Tonality.Scale
    let momentumSensitivity: Float
    let envelope: (Float) -> Float

    init(freq: Float, amp: Float, density: Float, species: Int,
         gainRange: ClosedRange<Float>, freqRange: ClosedRange<Float>,
         callRange: ClosedRange<Float>, lpCutoff: Float,
         vibratoRate: ClosedRange<Float>, vibratoDepth: ClosedRange<Float>,
         bpQ: Float, scale: Tonality.Scale, momentumSensitivity: Float,
         envelope: @escaping (Float) -> Float, seed: UInt64) {
        rng = FastRNG(seed: seed)
        baseFreq = freq
        currentFreq = freq
        maxAmplitude = amp
        self.density = density
        self.species = species
        self.gainRange = gainRange
        self.freqRange = freqRange
        self.callRange = callRange
        self.scale = scale
        self.momentumSensitivity = momentumSensitivity
        self.envelope = envelope
        callLength = UInt32(Float(sampleRate) * 0.6)
        bp = Biquad.bandPass(freq: freq, q: bpQ)
        distanceLP = OnePoleLP(cutoffHz: lpCutoff)
        vibrato = Vibrato(rateHz: rng.nextFloat(in: vibratoRate),
                          depthCents: rng.nextFloat(in: vibratoDepth),
                          rng: &rng)
        let cents = rng.nextFloat(in: -5...5)
        detuneMul = powf(2.0, cents / 1200.0)
    }

    mutating func onBeat(momentum: Float) -> Bool {
        if isActive { return false }
        let effectiveDensity = density + momentum * momentumSensitivity
        let roll = rng.nextFloat(in: 0.0...1.0)
        if roll < effectiveDensity {
            isActive = true
            counter = 0
            currentFreq = scale.randomTone(in: freqRange, rng: &rng)
            callLength = UInt32(rng.nextFloat(
                in: callRange.lowerBound * Float(sampleRate)...callRange.upperBound * Float(sampleRate)))
            callGain = rng.nextFloat(in: gainRange)
            return true
        }
        return false
    }

    mutating func nextSample() -> Float {
        guard isActive else { return 0 }
        counter += 1
        if counter >= callLength {
            isActive = false
            return 0
        }
        let t = Float(counter) / Float(callLength)
        let env = envelope(t)
        let vibMul = vibrato.nextMultiplier()
        phase += (currentFreq * detuneMul * vibMul) / Float(sampleRate)
        if phase > 1.0 { phase -= 1.0 }
        let raw = sin(phase * Float.pi * 2.0) * env * maxAmplitude * callGain
        return distanceLP.process(bp.process(raw))
    }
}

// MARK: - Shared: Beat Grid

/// Manages a 60 BPM / 16th-note grid with per-species momentum for
/// call-and-response behavior across creature voices.
struct BeatGrid {
    private let sixteenthSamples: UInt32 = UInt32(sampleRate) / 4
    private var beatClock: UInt32 = 0
    private var momentum: [Int: Float]
    private let decayRate: Float
    private let boostAmount: Float

    init(speciesCount: Int, decayRate: Float, boostAmount: Float) {
        var m: [Int: Float] = [:]
        for i in 0..<speciesCount { m[i] = 0 }
        momentum = m
        self.decayRate = decayRate
        self.boostAmount = boostAmount
    }

    mutating func tick(voices: inout [CreatureVoice]) {
        if beatClock == 0 {
            for key in momentum.keys { momentum[key]! *= decayRate }
            for i in voices.indices {
                let m = momentum[voices[i].species, default: 0]
                if voices[i].onBeat(momentum: m) {
                    for key in momentum.keys where key != voices[i].species {
                        momentum[key] = min(1.0, momentum[key, default: 0] + boostAmount)
                    }
                }
            }
        }
        beatClock += 1
        if beatClock >= sixteenthSamples { beatClock = 0 }
    }
}

// MARK: - Envelope Shapes

/// Reusable envelope functions for creature voices. Each takes t (0…1)
/// and returns amplitude (0…1).
enum Envelopes {
    // ── Owls ──

    /// Slow swell, sustained, gentle quadratic fade — resonant hoot.
    nonisolated(unsafe) static let deepHoot: (Float) -> Float = { t in
        if t < 0.15 { return t / 0.15 }
        if t < 0.65 { return 0.9 }
        let r = (t - 0.65) / 0.35
        return 0.9 * (1.0 - r * r)
    }

    /// Moderate attack, plateau, smooth linear release.
    nonisolated(unsafe) static let forestCall: (Float) -> Float = { t in
        if t < 0.10 { return t / 0.10 }
        if t < 0.60 { return 0.8 }
        let r = (t - 0.60) / 0.40
        return 0.8 * (1.0 - r)
    }

    /// Fast attack, quick exponential decay — brief and distant.
    nonisolated(unsafe) static let screech: (Float) -> Float = { t in
        if t < 0.06 { return t / 0.06 }
        let decayT = (t - 0.06) / 0.94
        return expf(-2.5 * decayT)
    }

    // ── Birds ──

    /// Slow attack, sustained plateau, gentle release — warm coo.
    nonisolated(unsafe) static let doveCoo: (Float) -> Float = { t in
        if t < 0.15 { return t / 0.15 }
        if t < 0.70 { return 0.85 }
        let r = (t - 0.70) / 0.30
        return 0.85 * (1.0 - r)
    }

    /// Fast attack, long exponential decay — fairy-chime, Zelda-like.
    nonisolated(unsafe) static let songbirdChirp: (Float) -> Float = { t in
        if t < 0.08 { return t / 0.08 }
        let decayT = (t - 0.08) / 0.92
        return expf(-1.8 * decayT)
    }

    /// Very fast attack, quick settle, short plateau, crisp release.
    nonisolated(unsafe) static let warblerTrill: (Float) -> Float = { t in
        if t < 0.05 { return t / 0.05 }
        if t < 0.15 {
            let d = (t - 0.05) / 0.10
            return 1.0 - d * 0.35
        }
        if t < 0.65 { return 0.65 }
        let r = (t - 0.65) / 0.35
        return 0.65 * (1.0 - r)
    }

    // ── Frogs ──

    /// Fast attack, settle, sustained plateau, smooth release.
    nonisolated(unsafe) static let frogCroak: (Float) -> Float = { t in
        if t < 0.08 { return t / 0.08 }
        if t < 0.20 {
            let d = (t - 0.08) / 0.12
            return 1.0 - d * 0.4
        }
        if t < 0.75 { return 0.6 }
        let r = (t - 0.75) / 0.25
        return 0.6 * (1.0 - r)
    }
}

// MARK: - Midnight Forest

/// Flagship night soundscape: dark wind through trees, a D Aeolian chord
/// drone, and sparse owl-like hoots at varying distances.
///
/// Three owl species create emergent call-and-response:
///   - **Deep owl**   — low, slow, resonant hoots (100-250 Hz)
///   - **Forest owl** — mid-range, moderate calls (250-500 Hz)
///   - **Screech**    — high, brief, distant cries (500-900 Hz)
struct MidnightForest {
    private var windNoise = BrownNoise()
    private var windLP = Biquad.lowPass(freq: 400.0, q: 0.6)
    private var windCutoffLFO = SmoothedRandom(minRateHz: 0.02, maxRateHz: 0.06, rangeMin: 150.0, rangeMax: 600.0)
    private var windAmpLFO = SmoothedRandom(minRateHz: 0.02, maxRateHz: 0.05, rangeMin: 0.25, rangeMax: 0.8)
    private var windCounter: UInt32 = 0
    private var voices: [CreatureVoice]
    private var drone: ChordDrone
    private var beat: BeatGrid

    init() {
        drone = ChordDrone(
            chords: [
                [73.4, 110.0, 146.8],   // D2  A2  D3  — home
                [73.4, 110.0, 130.8],   // D2  A2  C3  — b7, dark
                [73.4, 110.0, 174.6],   // D2  A2  F3  — minor 3rd
                [73.4, 110.0, 146.8],   // D2  A2  D3  — home
            ],
            toneAmps: [0.064, 0.048, 0.032],
            lpCutoff: 350.0, changePeriod: 20.0, breathPeriod: 30.0,
            volMin: 0.65, volRange: 0.35, h2: 0.5, h3: 0.25
        )

        let deep = 0, forest = 1, screechSpecies = 2
        voices = [
            // Deep owls — low, very sparse, long hoots
            CreatureVoice(freq: 146.8, amp: 0.14, density: 0.015, species: deep,
                          gainRange: 0.3...1.0, freqRange: 100...250,
                          callRange: 0.7...1.2, lpCutoff: 500.0,
                          vibratoRate: 0.3...0.7, vibratoDepth: 6...12,
                          bpQ: 1.0, scale: Tonality.nightChord, momentumSensitivity: 0.20,
                          envelope: Envelopes.deepHoot, seed: 701),
            CreatureVoice(freq: 110.0, amp: 0.10, density: 0.01, species: deep,
                          gainRange: 0.1...0.5, freqRange: 100...250,
                          callRange: 0.8...1.4, lpCutoff: 300.0,
                          vibratoRate: 0.3...0.7, vibratoDepth: 6...12,
                          bpQ: 1.0, scale: Tonality.nightChord, momentumSensitivity: 0.20,
                          envelope: Envelopes.deepHoot, seed: 702),
            // Forest owls — mid range
            CreatureVoice(freq: 293.7, amp: 0.10, density: 0.02, species: forest,
                          gainRange: 0.2...1.0, freqRange: 250...500,
                          callRange: 0.4...0.8, lpCutoff: 600.0,
                          vibratoRate: 0.3...0.7, vibratoDepth: 6...12,
                          bpQ: 1.0, scale: Tonality.nightChord, momentumSensitivity: 0.20,
                          envelope: Envelopes.forestCall, seed: 711),
            CreatureVoice(freq: 349.2, amp: 0.07, density: 0.015, species: forest,
                          gainRange: 0.1...0.4, freqRange: 250...500,
                          callRange: 0.5...0.9, lpCutoff: 400.0,
                          vibratoRate: 0.3...0.7, vibratoDepth: 6...12,
                          bpQ: 1.0, scale: Tonality.nightChord, momentumSensitivity: 0.20,
                          envelope: Envelopes.forestCall, seed: 712),
            // Screech owls — high, brief, rare
            CreatureVoice(freq: 587.3, amp: 0.06, density: 0.012, species: screechSpecies,
                          gainRange: 0.15...0.8, freqRange: 500...900,
                          callRange: 0.2...0.4, lpCutoff: 800.0,
                          vibratoRate: 0.3...0.7, vibratoDepth: 6...12,
                          bpQ: 1.0, scale: Tonality.nightChord, momentumSensitivity: 0.20,
                          envelope: Envelopes.screech, seed: 721),
            CreatureVoice(freq: 523.3, amp: 0.04, density: 0.008, species: screechSpecies,
                          gainRange: 0.05...0.3, freqRange: 500...900,
                          callRange: 0.15...0.35, lpCutoff: 450.0,
                          vibratoRate: 0.3...0.7, vibratoDepth: 6...12,
                          bpQ: 1.0, scale: Tonality.nightChord, momentumSensitivity: 0.20,
                          envelope: Envelopes.screech, seed: 722),
        ]
        beat = BeatGrid(speciesCount: 3, decayRate: 0.55, boostAmount: 0.4)
    }

    mutating func nextSample(natureBalance: Float = 1.0, toneBalance: Float = 1.0, chatterBalance: Float = 1.0) -> Float {
        beat.tick(voices: &voices)

        // Dark wind — brown noise with wandering cutoff
        windCounter &+= 1
        if windCounter % 64 == 0 {
            let cutoff = windCutoffLFO.nextValue()
            let q: Float = 0.4 + (cutoff - 150.0) / 900.0
            windLP.setLowPass(freq: cutoff, q: q)
        }
        let wAmp = windCounter % 64 == 0 ? windAmpLFO.nextValue() : windAmpLFO.value
        let wRaw = windNoise.nextSample()
        let wind = windLP.process(wRaw) * wAmp * 0.40

        let pad = drone.nextSample()

        var calls: Float = 0
        for i in voices.indices { calls += voices[i].nextSample() }

        return max(-1.0, min(1.0, wind * natureBalance + pad * toneBalance + calls * chatterBalance))
    }
}

// MARK: - Morning Birds

/// Warm sine chirps tuned to G Lydian / Gmaj9 chord tones over a soft
/// pink-noise forest-air bed and a slow chord drone.
///
/// Three species at varying distances create an emergent dawn chorus:
///   - **Dove**     — low, slow, warm coos (200-450 Hz)
///   - **Songbird** — mid-range, melodic chirps (400-900 Hz)
///   - **Warbler**  — high, quick, bright trills (900-1800 Hz)
struct MorningBirds {
    private var airNoise = PinkNoise()
    private var airLPlow = OnePoleLP(cutoffHz: 400.0)
    private var airLPhigh = OnePoleLP(cutoffHz: 1400.0)
    private var airAmp = SmoothedRandom(minRateHz: 0.02, maxRateHz: 0.06, rangeMin: 0.04, rangeMax: 0.12)
    private var airCounter: UInt32 = 0
    private var voices: [CreatureVoice]
    private var drone: ChordDrone
    private var beat: BeatGrid

    init() {
        drone = ChordDrone(
            chords: [
                [196.0, 293.7, 392.0],   // G3  D4  G4  — home
                [196.0, 293.7, 440.0],   // G3  D4  A4  — add9
                [196.0, 293.7, 493.9],   // G3  D4  B4  — major 3rd
                [196.0, 293.7, 370.0],   // G3  D4  F#4 — Lydian color
                [196.0, 293.7, 392.0],   // G3  D4  G4  — home
            ],
            toneAmps: [0.032, 0.024, 0.016],
            lpCutoff: 500.0, changePeriod: 16.0, breathPeriod: 20.0,
            volMin: 0.75, volRange: 0.25, h2: 0.4, h3: 0.2
        )

        let dove = 0, songbird = 1, warbler = 2
        voices = [
            // Doves — low and slow
            CreatureVoice(freq: 293.7, amp: 0.12, density: 0.025, species: dove,
                          gainRange: 0.3...1.0, freqRange: 200...450,
                          callRange: 0.5...0.9, lpCutoff: 600.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.doveCoo, seed: 111),
            CreatureVoice(freq: 247.0, amp: 0.10, density: 0.02, species: dove,
                          gainRange: 0.15...0.5, freqRange: 200...450,
                          callRange: 0.6...1.0, lpCutoff: 350.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.doveCoo, seed: 112),
            // Songbirds — mid range, backbone
            CreatureVoice(freq: 493.9, amp: 0.10, density: 0.045, species: songbird,
                          gainRange: 0.25...1.0, freqRange: 400...900,
                          callRange: 0.25...0.5, lpCutoff: 800.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.songbirdChirp, seed: 221),
            CreatureVoice(freq: 587.3, amp: 0.08, density: 0.035, species: songbird,
                          gainRange: 0.15...0.6, freqRange: 400...900,
                          callRange: 0.3...0.55, lpCutoff: 550.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.songbirdChirp, seed: 222),
            CreatureVoice(freq: 440.0, amp: 0.06, density: 0.03, species: songbird,
                          gainRange: 0.1...0.4, freqRange: 400...900,
                          callRange: 0.2...0.45, lpCutoff: 400.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.songbirdChirp, seed: 223),
            // Warblers — high, quick, bright
            CreatureVoice(freq: 880.0, amp: 0.072, density: 0.03, species: warbler,
                          gainRange: 0.2...1.0, freqRange: 900...1800,
                          callRange: 0.15...0.35, lpCutoff: 900.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.warblerTrill, seed: 331),
            CreatureVoice(freq: 740.0, amp: 0.048, density: 0.02, species: warbler,
                          gainRange: 0.1...0.4, freqRange: 900...1800,
                          callRange: 0.12...0.3, lpCutoff: 500.0,
                          vibratoRate: 0.8...1.8, vibratoDepth: 6...14,
                          bpQ: 1.0, scale: Tonality.dayChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.warblerTrill, seed: 332),
        ]
        beat = BeatGrid(speciesCount: 3, decayRate: 0.65, boostAmount: 0.5)
    }

    mutating func nextSample(natureBalance: Float = 1.0, toneBalance: Float = 1.0, chatterBalance: Float = 1.0) -> Float {
        beat.tick(voices: &voices)

        // Forest air — band-passed pink noise (400-1400 Hz) with slow swell
        airCounter &+= 1
        let aAmp = airCounter % 64 == 0 ? airAmp.nextValue() : airAmp.value
        let aRaw = airNoise.nextSample()
        let aLow = airLPlow.process(aRaw)
        let aBand = airLPhigh.process(aRaw - aLow)
        let air = aBand * aAmp

        let pad = drone.nextSample()

        var chirps: Float = 0
        for i in voices.indices { chirps += voices[i].nextSample() }

        return max(-1.0, min(1.0, air * natureBalance + pad * toneBalance + chirps * chatterBalance))
    }
}

// MARK: - Evening Frogs

/// Gentle warm tones tuned to open Bb major pentatonic voicings with slow
/// vibrato and long decay. A sine drone adds harmonic warmth underneath.
///
/// Three frog species create emergent rhythmic patterns:
///   - **Bullfrog** — low, slow, resonant (150-350 Hz)
///   - **Treefrog** — mid-range, moderate (400-800 Hz)
///   - **Peeper**   — high, quick, bright (800-1400 Hz)
struct EveningFrogs {
    private var windNoise = PinkNoise()
    private var windLPlow = OnePoleLP(cutoffHz: 300.0)
    private var windLPhigh = OnePoleLP(cutoffHz: 1200.0)
    private var windAmp = SmoothedRandom(minRateHz: 0.03, maxRateHz: 0.08, rangeMin: 0.032, rangeMax: 0.10)
    private var windCounter: UInt32 = 0
    private var voices: [CreatureVoice]
    private var drone: ChordDrone
    private var beat: BeatGrid

    init() {
        drone = ChordDrone(
            chords: [
                [116.5, 174.6, 233.1],  // Bb  F  Bb  — home
                [116.5, 174.6, 261.6],  // Bb  F  C   — add9
                [116.5, 174.6, 293.7],  // Bb  F  D   — major 3rd
                [116.5, 174.6, 233.1],  // Bb  F  Bb  — home
            ],
            toneAmps: [0.072, 0.056, 0.040],
            lpCutoff: 400.0, changePeriod: 16.0, breathPeriod: 25.0,
            volMin: 0.75, volRange: 0.25, h2: 0.5, h3: 0.33
        )

        let bullfrog = 0, treefrog = 1, peeper = 2
        voices = [
            // Bullfrogs — low and slow
            CreatureVoice(freq: 233.1, amp: 0.14, density: 0.04, species: bullfrog,
                          gainRange: 0.3...1.0, freqRange: 150...350,
                          callRange: 0.4...0.7, lpCutoff: 500.0,
                          vibratoRate: 0.4...0.9, vibratoDepth: 8...16,
                          bpQ: 1.2, scale: Tonality.duskChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.frogCroak, seed: 601),
            CreatureVoice(freq: 174.6, amp: 0.12, density: 0.03, species: bullfrog,
                          gainRange: 0.15...0.6, freqRange: 150...350,
                          callRange: 0.5...0.8, lpCutoff: 350.0,
                          vibratoRate: 0.4...0.9, vibratoDepth: 8...16,
                          bpQ: 1.2, scale: Tonality.duskChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.frogCroak, seed: 602),
            // Treefrogs — mid range
            CreatureVoice(freq: 466.2, amp: 0.112, density: 0.05, species: treefrog,
                          gainRange: 0.25...1.0, freqRange: 400...800,
                          callRange: 0.3...0.5, lpCutoff: 700.0,
                          vibratoRate: 0.4...0.9, vibratoDepth: 8...16,
                          bpQ: 1.2, scale: Tonality.duskChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.frogCroak, seed: 611),
            CreatureVoice(freq: 554.4, amp: 0.088, density: 0.04, species: treefrog,
                          gainRange: 0.1...0.5, freqRange: 400...800,
                          callRange: 0.25...0.45, lpCutoff: 500.0,
                          vibratoRate: 0.4...0.9, vibratoDepth: 8...16,
                          bpQ: 1.2, scale: Tonality.duskChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.frogCroak, seed: 612),
            // Peepers — high, tiny, quick
            CreatureVoice(freq: 698.5, amp: 0.072, density: 0.03, species: peeper,
                          gainRange: 0.2...1.0, freqRange: 800...1400,
                          callRange: 0.15...0.3, lpCutoff: 900.0,
                          vibratoRate: 0.4...0.9, vibratoDepth: 8...16,
                          bpQ: 1.2, scale: Tonality.duskChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.frogCroak, seed: 621),
            CreatureVoice(freq: 880.0, amp: 0.048, density: 0.02, species: peeper,
                          gainRange: 0.1...0.4, freqRange: 800...1400,
                          callRange: 0.12...0.25, lpCutoff: 600.0,
                          vibratoRate: 0.4...0.9, vibratoDepth: 8...16,
                          bpQ: 1.2, scale: Tonality.duskChord, momentumSensitivity: 0.25,
                          envelope: Envelopes.frogCroak, seed: 622),
        ]
        beat = BeatGrid(speciesCount: 3, decayRate: 0.65, boostAmount: 0.5)
    }

    mutating func nextSample(natureBalance: Float = 1.0, toneBalance: Float = 1.0, chatterBalance: Float = 1.0) -> Float {
        beat.tick(voices: &voices)

        // Gentle breeze — band-passed pink noise (300-1200Hz) with slow swell
        windCounter &+= 1
        let wAmp = windCounter % 64 == 0 ? windAmp.nextValue() : windAmp.value
        let wRaw = windNoise.nextSample()
        let wLow = windLPlow.process(wRaw)
        let wBand = windLPhigh.process(wRaw - wLow)
        let wind = wBand * wAmp

        let pad = drone.nextSample()

        var calls: Float = 0
        for i in voices.indices { calls += voices[i].nextSample() }

        return max(-1.0, min(1.0, wind * natureBalance + pad * toneBalance + calls * chatterBalance))
    }
}

// MARK: - Procedural Generator

/// Class wrapper that eliminates per-sample struct copying. Each generator
/// is captured by reference inside a closure, mutated in place at 44.1 kHz.
final class ProceduralGenerator {
    private let render: (Float, Float, Float) -> Float

    /// Layer balance values (0…1). Set from the mixer before each render pass.
    var natureBalance: Float = 1.0
    var toneBalance: Float = 1.0
    var chatterBalance: Float = 1.0

    private init(_ render: @escaping (Float, Float, Float) -> Float) {
        self.render = render
    }

    static func create(id: String) -> ProceduralGenerator? {
        switch id {
        case "midnight-forest":
            var gen = MidnightForest()
            return ProceduralGenerator { gen.nextSample(natureBalance: $0, toneBalance: $1, chatterBalance: $2) }
        case "morning-birds":
            var gen = MorningBirds()
            return ProceduralGenerator { gen.nextSample(natureBalance: $0, toneBalance: $1, chatterBalance: $2) }
        case "evening-frogs":
            var gen = EveningFrogs()
            return ProceduralGenerator { gen.nextSample(natureBalance: $0, toneBalance: $1, chatterBalance: $2) }
        default:
            return nil
        }
    }

    func nextSample() -> Float {
        render(natureBalance, toneBalance, chatterBalance)
    }
}
