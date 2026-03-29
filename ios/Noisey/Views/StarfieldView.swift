import SwiftUI

/// A twinkling starfield background that responds to master volume.
/// Matches the web UI: 150 stars, varied sizes, twinkle + drift animations,
/// brightness scales with volume but always faintly visible.
struct StarfieldView: View {
    let volume: Float

    private static let stars: [Star] = (0..<150).map { _ in
        let r = Double.random(in: 0...1)
        let size: CGFloat = r < 0.05 ? 2.5 : r < 0.2 ? 2 : r < 0.5 ? 1.5 : 1
        return Star(
            x: Double.random(in: 0...1),
            y: Double.random(in: 0...1),
            size: size,
            threshold: Double.random(in: 0...1),
            twinkleDuration: Double.random(in: 3...8),
            driftDuration: Double.random(in: 15...40),
            dx: Double.random(in: -1.5...1.5),
            dy: Double.random(in: -1.5...1.5),
            delay: Double.random(in: 0...10)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let vol = Double(volume)
                for star in Self.stars {
                    let ambient = star.size >= 2 ? 0.15 : star.size >= 1.5 ? 0.1 : 0.06
                    let adjustedThreshold = star.threshold * 0.6
                    let visibility = max(0, (vol - adjustedThreshold) / (1 - adjustedThreshold))
                    let volumeBrightness = visibility * (star.size >= 2 ? 0.85 : star.size >= 1.5 ? 0.7 : 0.5)
                    let baseBrightness = max(ambient, volumeBrightness)

                    // Twinkle: sinusoidal oscillation per star
                    let phase = (t + star.delay) / star.twinkleDuration * .pi * 2
                    let twinkle = (sin(phase) + 1) / 2 // 0..1
                    let low = baseBrightness * 0.35
                    let high = baseBrightness
                    let brightness = low + (high - low) * twinkle

                    // Drift
                    let driftPhase = (t + star.delay) / star.driftDuration * .pi * 2
                    let driftX = sin(driftPhase) * star.dx
                    let driftY = cos(driftPhase) * star.dy

                    let x = star.x * size.width + driftX
                    let y = star.y * size.height + driftY
                    let r = star.size / 2

                    let rect = CGRect(x: x - r, y: y - r, width: star.size, height: star.size)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(brightness))
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct Star {
    let x: Double
    let y: Double
    let size: CGFloat
    let threshold: Double
    let twinkleDuration: Double
    let driftDuration: Double
    let dx: Double
    let dy: Double
    let delay: Double
}
