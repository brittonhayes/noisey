import Foundation

// MARK: - Effects Preset

/// Defines the curated effect parameters for a sound. Each sound gets its own
/// sonic character through this preset.
struct EffectsPreset {
    // Reverb
    let reverbRoomSize: Float   // 0-1, feedback amount
    let reverbDamping: Float    // 0-1, high-freq damping
    let reverbWet: Float        // 0-1
    let reverbDry: Float        // 0-1

    // Delay
    let delayTimeMs: Float      // delay time in ms
    let delayFeedback: Float    // 0-1
    let delayWet: Float         // 0-1
    let delayDry: Float         // 0-1

    // Chorus
    let chorusRateHz: Float     // LFO rate
    let chorusDepthMs: Float    // modulation depth
    let chorusWet: Float        // 0-1
    let chorusDry: Float        // 0-1

    // Post-processing
    let outputGain: Float       // final gain adjustment

    /// No effects — clean pass-through.
    static let bypass = EffectsPreset(
        reverbRoomSize: 0, reverbDamping: 0, reverbWet: 0, reverbDry: 1,
        delayTimeMs: 0, delayFeedback: 0, delayWet: 0, delayDry: 1,
        chorusRateHz: 0, chorusDepthMs: 0, chorusWet: 0, chorusDry: 1,
        outputGain: 1.0
    )
}

// MARK: - Effects Chain

/// Per-sound effects processor. Composes reverb → delay → chorus in series.
/// Created from a preset — all parameters are baked at init time for real-time safety.
struct EffectsChain {
    private var reverb: Freeverb?
    private var delay: FeedbackDelay?
    private var chorus: Chorus?
    private let outputGain: Float

    init(preset: EffectsPreset) {
        outputGain = preset.outputGain

        // Only allocate effects that are actually used (wet > 0)
        if preset.reverbWet > 0 {
            reverb = Freeverb(
                roomSize: preset.reverbRoomSize,
                damping: preset.reverbDamping,
                wet: preset.reverbWet,
                dry: preset.reverbDry
            )
        }

        if preset.delayWet > 0 && preset.delayTimeMs > 0 {
            delay = FeedbackDelay(
                timeMs: preset.delayTimeMs,
                feedback: preset.delayFeedback,
                wet: preset.delayWet,
                dry: preset.delayDry
            )
        }

        if preset.chorusWet > 0 {
            chorus = Chorus(
                rateHz: preset.chorusRateHz,
                depthMs: preset.chorusDepthMs,
                wet: preset.chorusWet,
                dry: preset.chorusDry
            )
        }
    }

    mutating func process(_ sample: Float) -> Float {
        var out = sample

        if reverb != nil { out = reverb!.process(out) }
        if delay != nil { out = delay!.process(out) }
        if chorus != nil { out = chorus!.process(out) }

        out *= outputGain
        return max(-1.0, min(1.0, out))
    }
}

// MARK: - Sound Presets

/// Curated effect presets for each built-in sound. These are designed to
/// enhance the character of each generator — making ocean surf feel vast,
/// birds feel spacious, crickets feel intimate, etc.
enum SoundPresets {
    static func preset(for soundID: String) -> EffectsPreset {
        switch soundID {

        // ── Night World ──────────────────────────────────────────────

        case "midnight-forest":
            // Deep, enveloping darkness — very long reverb tail, subtle delay for
            // owl echo, slow chorus for uneasy spatial width
            return EffectsPreset(
                reverbRoomSize: 0.92, reverbDamping: 0.5, reverbWet: 0.40, reverbDry: 0.60,
                delayTimeMs: 220, delayFeedback: 0.12, delayWet: 0.08, delayDry: 0.92,
                chorusRateHz: 0.12, chorusDepthMs: 5.0, chorusWet: 0.18, chorusDry: 0.82,
                outputGain: 1.0
            )

        // ── Day World ────────────────────────────────────────────────

        case "morning-birds":
            // Warm, spacious Zelda-inspired — long reverb tail, gentle delay echoes, soft chorus shimmer
            return EffectsPreset(
                reverbRoomSize: 0.82, reverbDamping: 0.55, reverbWet: 0.45, reverbDry: 0.55,
                delayTimeMs: 220, delayFeedback: 0.25, delayWet: 0.15, delayDry: 0.85,
                chorusRateHz: 0, chorusDepthMs: 0, chorusWet: 0, chorusDry: 1,
                outputGain: 0.85
            )

        // ── Dusk World ───────────────────────────────────────────────

        case "evening-frogs":
            // Very wet reverb — frogs sound distant, across a field
            return EffectsPreset(
                reverbRoomSize: 0.85, reverbDamping: 0.6, reverbWet: 0.7, reverbDry: 0.3,
                delayTimeMs: 250, delayFeedback: 0.2, delayWet: 0.15, delayDry: 0.85,
                chorusRateHz: 0, chorusDepthMs: 0, chorusWet: 0, chorusDry: 1,
                outputGain: 0.8
            )

        default:
            // Custom/file-based sounds get a gentle room reverb
            return EffectsPreset(
                reverbRoomSize: 0.45, reverbDamping: 0.5, reverbWet: 0.15, reverbDry: 0.85,
                delayTimeMs: 0, delayFeedback: 0, delayWet: 0, delayDry: 1,
                chorusRateHz: 0, chorusDepthMs: 0, chorusWet: 0, chorusDry: 1,
                outputGain: 1.0
            )
        }
    }
}
