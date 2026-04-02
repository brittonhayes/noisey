import SwiftUI

/// Top-down twilight pond for the dusk world background.
/// Dark water fills the screen with lilypads that glow in response to actual frog audio amplitude.
struct FireflyFieldView: View {
    let volume: Float

    @Environment(NoiseyStore.self) private var store

    private var frogsActive: Bool {
        store.activeSound?.id == "evening-frogs"
    }

    private static let pads: [PondLilypad] = [
        PondLilypad(id: 0,  x: 0.12, y: 0.20, size: 28, phaseOffset: 0.0,  sensitivity: 1.0),
        PondLilypad(id: 1,  x: 0.75, y: 0.15, size: 22, phaseOffset: 1.2,  sensitivity: 0.7),
        PondLilypad(id: 2,  x: 0.40, y: 0.35, size: 32, phaseOffset: 2.5,  sensitivity: 1.2),
        PondLilypad(id: 3,  x: 0.22, y: 0.50, size: 24, phaseOffset: 3.8,  sensitivity: 0.8),
        PondLilypad(id: 4,  x: 0.62, y: 0.45, size: 20, phaseOffset: 0.9,  sensitivity: 1.1),
        PondLilypad(id: 5,  x: 0.88, y: 0.33, size: 18, phaseOffset: 5.1,  sensitivity: 0.6),
        PondLilypad(id: 6,  x: 0.50, y: 0.12, size: 26, phaseOffset: 4.0,  sensitivity: 0.9),
        PondLilypad(id: 7,  x: 0.15, y: 0.72, size: 20, phaseOffset: 2.0,  sensitivity: 0.75),
        PondLilypad(id: 8,  x: 0.72, y: 0.65, size: 24, phaseOffset: 1.6,  sensitivity: 1.15),
        PondLilypad(id: 9,  x: 0.35, y: 0.78, size: 18, phaseOffset: 3.2,  sensitivity: 0.85),
        PondLilypad(id: 10, x: 0.55, y: 0.62, size: 22, phaseOffset: 4.5,  sensitivity: 0.65),
        PondLilypad(id: 11, x: 0.85, y: 0.55, size: 16, phaseOffset: 0.4,  sensitivity: 1.0),
        PondLilypad(id: 12, x: 0.30, y: 0.88, size: 20, phaseOffset: 5.5,  sensitivity: 0.9),
        PondLilypad(id: 13, x: 0.65, y: 0.82, size: 26, phaseOffset: 2.8,  sensitivity: 0.7),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let frogsOn = frogsActive
                // Audio-driven intensity: scale RMS into a usable 0…1 range.
                // Procedural generators output quiet signals, so amplify aggressively.
                let raw = Double(store.audioLevel)
                let level = frogsOn ? min(1.0, raw * 40.0) : 0

                for pad in Self.pads {
                    let px = pad.x * size.width
                    let py = pad.y * size.height
                    let s = pad.size

                    // Lilypad — dark green oval (always visible)
                    let padRect = CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)
                    let padPath = Path(ellipseIn: padRect)
                    context.fill(padPath, with: .color(Color(red: 0.10, green: 0.25, blue: 0.12).opacity(0.6)))

                    if frogsOn {
                        // Each pad responds to audio level with its own sensitivity and
                        // a slow phase drift so they don't all flash in perfect unison.
                        let drift = sin(t * 0.3 + pad.phaseOffset) * 0.15
                        let intensity = min(1.0, max(0, level * pad.sensitivity + drift))

                        let glowAlpha = 0.05 + intensity * 0.55

                        // Soft green glow
                        let glowSize = s * 2.5
                        let glowRect = CGRect(x: px - glowSize / 2, y: py - glowSize / 2, width: glowSize, height: glowSize)
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(Color(red: 0.30, green: 0.85, blue: 0.40).opacity(glowAlpha * 0.5))
                        )

                        // Bright center
                        let brightAlpha = 0.10 + intensity * 0.70
                        let brightSize = s * 0.5
                        let brightRect = CGRect(x: px - brightSize / 2, y: py - brightSize / 2, width: brightSize, height: brightSize)
                        context.fill(
                            Path(ellipseIn: brightRect),
                            with: .color(Color(red: 0.45, green: 1.0, blue: 0.55).opacity(brightAlpha))
                        )
                    } else {
                        // Very faint idle glow
                        let dimPulse = (sin((t + pad.phaseOffset) * 0.15) + 1) / 2
                        let dimAlpha = 0.01 + dimPulse * 0.03
                        let dimSize = s * 0.4
                        let dimRect = CGRect(x: px - dimSize / 2, y: py - dimSize / 2, width: dimSize, height: dimSize)
                        context.fill(
                            Path(ellipseIn: dimRect),
                            with: .color(Color(red: 0.30, green: 0.60, blue: 0.35).opacity(dimAlpha))
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct PondLilypad {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let phaseOffset: Double
    let sensitivity: Double
}
