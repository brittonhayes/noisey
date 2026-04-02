import SwiftUI

struct MoonVolumeView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var dragOffset: CGFloat = 0
    @State private var showHint = false
    private let moonSize: CGFloat = 180

    var body: some View {
        ZStack {
            // Glow halo — cool silver-blue
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.72, green: 0.78, blue: 1.0).opacity(Double(store.masterVolume) * 0.22),
                            Color(red: 0.55, green: 0.60, blue: 0.95).opacity(Double(store.masterVolume) * 0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: moonSize * 0.25,
                        endRadius: moonSize * 1.3
                    )
                )
                .frame(width: moonSize * 2.5, height: moonSize * 2.5)
                .blur(radius: 30)

            // Volume hint
            Text("\(Int(store.masterVolume * 100))")
                .font(.system(size: 96, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white.opacity(showHint ? 0.15 : 0))
                .animation(.easeOut(duration: 0.3), value: showHint)

            // Moon disc
            Circle()
                .fill(Color(red: 0.92, green: 0.94, blue: 1.0).opacity(0.92))
                .frame(width: moonSize, height: moonSize)
                .overlay {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2
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
                }
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
            color: store.isPlaying ? Color(red: 0.72, green: 0.78, blue: 1.0).opacity(0.14) : .clear,
            radius: store.isPlaying ? 40 : 0
        )
    }
}
