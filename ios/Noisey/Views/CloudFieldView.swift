import SwiftUI

/// Soft drifting cloud shapes for the day world background.
struct CloudFieldView: View {
    let volume: Float

    private static let clouds: [Cloud] = (0..<20).map { _ in
        Cloud(
            x: Double.random(in: -0.2...1.2),
            y: Double.random(in: 0...1),
            width: CGFloat.random(in: 60...180),
            height: CGFloat.random(in: 20...50),
            opacity: Double.random(in: 0.04...0.12),
            speed: Double.random(in: 0.002...0.008),
            delay: Double.random(in: 0...100)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let vol = Double(volume)

                for cloud in Self.clouds {
                    let visibility = max(0.3, vol)

                    // Drift horizontally, wrap around
                    let rawX = cloud.x + (t + cloud.delay) * cloud.speed
                    let wrappedX = rawX.truncatingRemainder(dividingBy: 1.4) - 0.2
                    let x = wrappedX * Double(size.width)
                    let y = cloud.y * Double(size.height)

                    let rect = CGRect(
                        x: x - Double(cloud.width) / 2,
                        y: y - Double(cloud.height) / 2,
                        width: Double(cloud.width),
                        height: Double(cloud.height)
                    )

                    let cloudPath = Path(roundedRect: rect, cornerRadius: cloud.height / 2)
                    context.fill(
                        cloudPath,
                        with: .color(.white.opacity(cloud.opacity * visibility))
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct Cloud {
    let x: Double
    let y: Double
    let width: CGFloat
    let height: CGFloat
    let opacity: Double
    let speed: Double
    let delay: Double
}
