import SwiftUI

struct SunVolumeView: View {
    @Environment(NoiseyStore.self) private var store
    private let sunSize: CGFloat = 180

    var body: some View {
        ZStack {
            // Warm glow halo — rich golden amber
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.40).opacity(0.30),
                            Color(red: 1.0, green: 0.65, blue: 0.28).opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: sunSize * 0.25,
                        endRadius: sunSize * 1.3
                    )
                )
                .frame(width: sunSize * 2.5, height: sunSize * 2.5)
                .blur(radius: 35)

            // Sun with rays
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                // Rays
                let rayCount = 12
                let rayLength = radius * 0.7
                let rayWidth: CGFloat = 2.5

                for i in 0..<rayCount {
                    let angle = CGFloat(i) / CGFloat(rayCount) * .pi * 2 - .pi / 2
                    let innerR = radius + 4
                    let outerR = radius + rayLength

                    let start = CGPoint(
                        x: center.x + innerR * cos(angle),
                        y: center.y + innerR * sin(angle)
                    )
                    let end = CGPoint(
                        x: center.x + outerR * cos(angle),
                        y: center.y + outerR * sin(angle)
                    )

                    var rayPath = Path()
                    rayPath.move(to: start)
                    rayPath.addLine(to: end)

                    context.stroke(
                        rayPath,
                        with: .color(Color(red: 1.0, green: 0.82, blue: 0.35).opacity(0.8)),
                        lineWidth: rayWidth
                    )
                }

                // Sun disc
                let sunPath = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(sunPath, with: .color(
                    Color(red: 1.0, green: 0.84, blue: 0.36).opacity(0.95)
                ))

                // Inner bright core
                let coreRadius = radius * 0.6
                let corePath = Path(ellipseIn: CGRect(
                    x: center.x - coreRadius,
                    y: center.y - coreRadius,
                    width: coreRadius * 2,
                    height: coreRadius * 2
                ))
                context.fill(corePath, with: .color(
                    Color(red: 1.0, green: 0.94, blue: 0.72).opacity(0.42)
                ))
            }
            .frame(width: sunSize, height: sunSize)
        }
        .skyDrag()
        .shadow(
            color: store.isPlaying ? Color(red: 1.0, green: 0.84, blue: 0.40).opacity(0.15) : .clear,
            radius: store.isPlaying ? 45 : 0
        )
    }
}
