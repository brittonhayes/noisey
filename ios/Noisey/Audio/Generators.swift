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

        return max(-1.0, min(1.0, filtered * envelope))
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
        return max(-1.0, min(1.0, mix))
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
        return max(-1.0, min(1.0, mix))
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
        return max(-1.0, min(1.0, filtered * amp * 0.8))
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
        }
    }
}
