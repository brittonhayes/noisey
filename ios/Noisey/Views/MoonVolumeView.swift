import SwiftUI

struct MoonVolumeView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var dragOffset: CGFloat = 0
    @State private var showHint = false

    private let moonSize: CGFloat = 180

    var body: some View {
        ZStack {
            // Glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(Double(store.masterVolume) * 0.15),
                            .clear
                        ],
                        center: .center,
                        startRadius: moonSize * 0.4,
                        endRadius: moonSize * 0.9
                    )
                )
                .frame(width: moonSize * 2, height: moonSize * 2)
                .blur(radius: 20)

            // Volume hint
            Text("\(Int(store.masterVolume * 100))")
                .font(.system(size: 96, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white.opacity(showHint ? 0.15 : 0))
                .animation(.easeOut(duration: 0.3), value: showHint)

            // Moon
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                let phase = CGFloat(store.masterVolume)

                // Full moon disc
                let moonPath = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(moonPath, with: .color(.white.opacity(0.9)))

                // Shadow overlay for crescent phase
                // Two-tone only: bright lit area + dark background shadow
                if phase < 1.0 {
                    let bgColor = Color(red: 0.067, green: 0.067, blue: 0.067)

                    // First, cover entire moon with the dark shadow color
                    context.drawLayer { ctx in
                        ctx.clip(to: moonPath)
                        ctx.fill(
                            Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                            with: .color(bgColor)
                        )
                    }

                    // Then draw the lit crescent on top as a single path
                    // terminatorRx: how far the terminator bulges from center
                    let terminatorRx = radius * abs(phase * 2 - 1)
                    let steps = 64

                    var litPath = Path()
                    // Left semicircle: the always-lit edge (southern hemisphere, lights left to right)
                    litPath.addArc(center: center, radius: radius,
                                   startAngle: .degrees(-90), endAngle: .degrees(90),
                                   clockwise: true)
                    // Terminator arc: from bottom back to top
                    for i in 0...steps {
                        let t = CGFloat(i) / CGFloat(steps)
                        let angle = CGFloat.pi / 2 - t * CGFloat.pi // pi/2 -> -pi/2
                        let y = center.y + radius * sin(angle)
                        let x: CGFloat
                        if phase >= 0.5 {
                            // Gibbous: terminator curves RIGHT of center (lit area > half)
                            x = center.x + terminatorRx * cos(angle)
                        } else {
                            // Crescent: terminator curves LEFT of center (lit area < half)
                            x = center.x - terminatorRx * cos(angle)
                        }
                        litPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    litPath.closeSubpath()

                    context.drawLayer { ctx in
                        ctx.clip(to: moonPath)
                        ctx.fill(litPath, with: .color(.white.opacity(0.9)))
                    }
                }

                // Surface texture dots
                let dotPositions: [(CGFloat, CGFloat, CGFloat)] = [
                    (-0.25, -0.3, 0.08),
                    (0.15, -0.15, 0.12),
                    (-0.1, 0.2, 0.06),
                    (0.3, 0.1, 0.05),
                    (-0.35, 0.05, 0.04),
                    (0.05, 0.35, 0.07),
                    (0.2, -0.35, 0.03),
                ]
                for (dx, dy, r) in dotPositions {
                    let dotCenter = CGPoint(
                        x: center.x + radius * dx,
                        y: center.y + radius * dy
                    )
                    let dotRadius = radius * r
                    let dotPath = Path(ellipseIn: CGRect(
                        x: dotCenter.x - dotRadius,
                        y: dotCenter.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    ))
                    context.fill(dotPath, with: .color(.white.opacity(0.06)))
                }
            }
            .frame(width: moonSize, height: moonSize)
            .scaleEffect(store.isDraggingVolume ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: store.isDraggingVolume)
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    store.isDraggingVolume = true
                    showHint = true

                    let delta = Float(-value.translation.height / 300)
                    let prev = Float(dragOffset / 300)
                    let newVolume = max(0, min(1, store.masterVolume + delta + prev))
                    dragOffset = value.translation.height
                    store.setVolume(newVolume)
                }
                .onEnded { _ in
                    dragOffset = 0
                    store.isDraggingVolume = false
                    withAnimation(.easeOut(duration: 0.8)) {
                        showHint = false
                    }
                }
        )
        // Subtle glow when playing (no animation)
        .shadow(
            color: store.isPlaying ? .white.opacity(0.08) : .clear,
            radius: store.isPlaying ? 30 : 0
        )
    }
}
