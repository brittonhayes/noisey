import SwiftUI

/// Amber dusk moon — floats above the twilight pond background.
struct FireflyVolumeView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var dragOffset: CGFloat = 0
    @State private var showHint = false
    private let moonSize: CGFloat = 140

    var body: some View {
        ZStack {
            // Warm glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.90, blue: 0.70).opacity(Double(store.masterVolume) * 0.22),
                            Color(red: 0.75, green: 0.45, blue: 0.55).opacity(Double(store.masterVolume) * 0.07),
                            .clear
                        ],
                        center: .center,
                        startRadius: moonSize * 0.25,
                        endRadius: moonSize * 1.3
                    )
                )
                .frame(width: moonSize * 2.5, height: moonSize * 2.5)
                .blur(radius: 28)

            // Volume hint
            Text("\(Int(store.masterVolume * 100))")
                .font(.system(size: 96, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white.opacity(showHint ? 0.15 : 0))
                .animation(.easeOut(duration: 0.3), value: showHint)

            // Moon disc — warm amber
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                let warmWhite = Color(red: 1.0, green: 0.90, blue: 0.78)
                let amber = Color(red: 1.0, green: 0.62, blue: 0.44)

                // Disc
                let moonPath = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(moonPath, with: .color(amber.opacity(0.9)))

                // Surface highlights
                let dots: [(CGFloat, CGFloat, CGFloat)] = [
                    (-0.25, -0.3, 0.08),
                    (0.15, -0.15, 0.12),
                    (-0.1, 0.2, 0.06),
                    (0.3, 0.1, 0.05),
                    (-0.35, 0.05, 0.04),
                    (0.05, 0.35, 0.07),
                ]
                for (dx, dy, r) in dots {
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
                    context.fill(dotPath, with: .color(warmWhite.opacity(0.08)))
                }
            }
            .frame(width: moonSize, height: moonSize)
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
        .shadow(
            color: store.isPlaying ? Color(red: 1.0, green: 0.62, blue: 0.44).opacity(0.14) : .clear,
            radius: store.isPlaying ? 35 : 0
        )
    }
}
