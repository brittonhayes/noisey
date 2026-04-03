import SwiftUI

/// Top-down twilight pond for the dusk world background.
/// Dark water fills the screen with lilypads that glow in response to actual frog audio amplitude.
struct FireflyFieldView: View {
    let volume: Float

    @Environment(NoiseyStore.self) private var store
    @State private var lilypad = WaterDragController()

    private var frogsActive: Bool {
        store.activeSound?.id == "evening-frogs"
    }

    private static let pads: [PondLilypad] = [
        PondLilypad(id: 0,  x: 0.12, y: 0.20, size: 28, phaseOffset: 0.0,  sensitivity: 1.0,  rotation: 15),
        PondLilypad(id: 1,  x: 0.75, y: 0.15, size: 22, phaseOffset: 1.2,  sensitivity: 0.7,  rotation: -30),
        PondLilypad(id: 2,  x: 0.40, y: 0.35, size: 32, phaseOffset: 2.5,  sensitivity: 1.2,  rotation: 55),
        PondLilypad(id: 3,  x: 0.22, y: 0.50, size: 24, phaseOffset: 3.8,  sensitivity: 0.8,  rotation: -10),
        PondLilypad(id: 4,  x: 0.62, y: 0.45, size: 20, phaseOffset: 0.9,  sensitivity: 1.1,  rotation: 80),
        PondLilypad(id: 5,  x: 0.88, y: 0.33, size: 18, phaseOffset: 5.1,  sensitivity: 0.6,  rotation: -65),
        PondLilypad(id: 6,  x: 0.50, y: 0.12, size: 26, phaseOffset: 4.0,  sensitivity: 0.9,  rotation: 40),
        PondLilypad(id: 7,  x: 0.15, y: 0.72, size: 20, phaseOffset: 2.0,  sensitivity: 0.75, rotation: -45),
        PondLilypad(id: 8,  x: 0.72, y: 0.65, size: 24, phaseOffset: 1.6,  sensitivity: 1.15, rotation: 20),
        PondLilypad(id: 9,  x: 0.35, y: 0.78, size: 18, phaseOffset: 3.2,  sensitivity: 0.85, rotation: -80),
        PondLilypad(id: 10, x: 0.55, y: 0.62, size: 22, phaseOffset: 4.5,  sensitivity: 0.65, rotation: 60),
        PondLilypad(id: 11, x: 0.85, y: 0.55, size: 16, phaseOffset: 0.4,  sensitivity: 1.0,  rotation: -20),
        PondLilypad(id: 12, x: 0.30, y: 0.88, size: 20, phaseOffset: 5.5,  sensitivity: 0.9,  rotation: 35),
        PondLilypad(id: 13, x: 0.65, y: 0.82, size: 26, phaseOffset: 2.8,  sensitivity: 0.7,  rotation: -55),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background lilypads canvas
                TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let frogsOn = frogsActive
                        let raw = Double(store.audioLevel)
                        let level = frogsOn ? min(1.0, raw * 40.0) : 0

                        for pad in Self.pads {
                            let px = pad.x * size.width
                            let py = pad.y * size.height
                            let s = pad.size

                            // Draw lilypad with notch and veins
                            drawLilypad(
                                in: &context,
                                at: CGPoint(x: px, y: py),
                                size: s,
                                rotation: pad.rotation,
                                hueShift: Double(pad.id) * 0.02
                            )

                            if frogsOn {
                                let drift = sin(t * 0.3 + pad.phaseOffset) * 0.15
                                let intensity = min(1.0, max(0, level * pad.sensitivity + drift))
                                let glowAlpha = 0.05 + intensity * 0.55

                                let glowSize = s * 2.5
                                let glowRect = CGRect(x: px - glowSize / 2, y: py - glowSize / 2,
                                                      width: glowSize, height: glowSize)
                                context.fill(
                                    Path(ellipseIn: glowRect),
                                    with: .color(Color(red: 0.30, green: 0.85, blue: 0.40)
                                        .opacity(glowAlpha * 0.5))
                                )

                                let brightAlpha = 0.10 + intensity * 0.70
                                let brightSize = s * 0.5
                                let brightRect = CGRect(x: px - brightSize / 2, y: py - brightSize / 2,
                                                        width: brightSize, height: brightSize)
                                context.fill(
                                    Path(ellipseIn: brightRect),
                                    with: .color(Color(red: 0.45, green: 1.0, blue: 0.55)
                                        .opacity(brightAlpha))
                                )
                            } else {
                                let dimPulse = (sin((t + pad.phaseOffset) * 0.15) + 1) / 2
                                let dimAlpha = 0.01 + dimPulse * 0.03
                                let dimSize = s * 0.4
                                let dimRect = CGRect(x: px - dimSize / 2, y: py - dimSize / 2,
                                                     width: dimSize, height: dimSize)
                                context.fill(
                                    Path(ellipseIn: dimRect),
                                    with: .color(Color(red: 0.30, green: 0.60, blue: 0.35)
                                        .opacity(dimAlpha))
                                )
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }

                // Draggable lilypad with flower
                DraggableLilypad(
                    controller: lilypad,
                    frogsActive: frogsActive
                )
                .position(lilypad.position)
                .onAppear {
                    lilypad.setBounds(CGRect(origin: .zero, size: geo.size))
                    lilypad.drag(to: CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5))
                }
                .onChange(of: geo.size) { _, newSize in
                    lilypad.setBounds(CGRect(origin: .zero, size: newSize))
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Draw a smooth oval lilypad with subtle radial veins into the canvas.
    private func drawLilypad(
        in context: inout GraphicsContext,
        at center: CGPoint,
        size s: CGFloat,
        rotation degrees: Double,
        hueShift: Double
    ) {
        let rx = s / 2
        let ry = s * 0.42

        let padRect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
        let padPath = Path(ellipseIn: padRect)

        // Rotate around center
        let rot = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
        let rotatedPad = padPath.applying(rot)

        // Vary green slightly per pad
        let g = 0.25 + hueShift
        context.fill(rotatedPad, with: .color(Color(red: 0.10, green: g, blue: 0.12).opacity(0.7)))

        // Lighter edge highlight
        context.stroke(rotatedPad, with: .color(Color(red: 0.14, green: g + 0.08, blue: 0.16).opacity(0.35)),
                        lineWidth: 0.8)

        // Curved veins radiating from center
        let veinCount = 6
        for v in 0..<veinCount {
            let vAngle = Double(v) / Double(veinCount) * 2 * .pi
            let endX = center.x + cos(vAngle) * rx * 0.78
            let endY = center.y + sin(vAngle) * ry * 0.78
            // Control point offset perpendicular to the vein direction for a slight curve
            let perpX = -sin(vAngle) * rx * 0.15
            let perpY = cos(vAngle) * ry * 0.15

            var veinPath = Path()
            veinPath.move(to: center)
            veinPath.addQuadCurve(
                to: CGPoint(x: endX, y: endY),
                control: CGPoint(x: (center.x + endX) / 2 + perpX,
                                 y: (center.y + endY) / 2 + perpY)
            )
            let rotatedVein = veinPath.applying(rot)
            context.stroke(rotatedVein, with: .color(Color(red: 0.08, green: 0.20, blue: 0.10).opacity(0.35)),
                            lineWidth: 0.5)
        }
    }
}

// MARK: - Draggable Lilypad

private struct DraggableLilypad: View {
    var controller: WaterDragController
    let frogsActive: Bool

    @Environment(NoiseyStore.self) private var store
    @State private var dragStart: CGPoint = .zero

    private let padSize: CGFloat = 180

    var body: some View {
        ZStack {
            if frogsActive {
                let level = min(1.0, Double(store.audioLevel) * 40.0)
                Ellipse()
                    .fill(Color(red: 0.30, green: 0.85, blue: 0.40).opacity(0.12 + level * 0.25))
                    .frame(width: padSize * 1.8, height: padSize * 1.8)
                    .blur(radius: 30)
            }

            Ellipse()
                .fill(Color(red: 0.12, green: 0.32, blue: 0.14))
                .frame(width: padSize, height: padSize * 0.85)
                .overlay(
                    Ellipse()
                        .stroke(Color(red: 0.16, green: 0.40, blue: 0.18).opacity(0.5), lineWidth: 1.5)
                        .frame(width: padSize, height: padSize * 0.85)
                )
                .overlay(
                    VeinLines()
                        .stroke(Color(red: 0.08, green: 0.22, blue: 0.10), lineWidth: 1)
                        .frame(width: padSize * 0.65, height: padSize * 0.55)
                )

            TinyFlower(petalSize: padSize * 0.09)
                .offset(x: padSize * 0.18, y: -padSize * 0.22)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == .zero {
                        dragStart = controller.position
                    }
                    controller.drag(to: CGPoint(
                        x: dragStart.x + value.translation.width,
                        y: dragStart.y + value.translation.height
                    ))
                }
                .onEnded { value in
                    dragStart = .zero
                    controller.release(velocity: CGPoint(
                        x: value.predictedEndTranslation.width - value.translation.width,
                        y: value.predictedEndTranslation.height - value.translation.height
                    ))
                }
        )
    }
}

// MARK: - Shapes

/// Curved veins radiating outward from center — no central split.
private struct VeinLines: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let cx = rect.midX
            let cy = rect.midY
            let rx = rect.width / 2
            let ry = rect.height / 2
            let count = 7
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi
                let endX = cx + cos(angle) * rx * 0.88
                let endY = cy + sin(angle) * ry * 0.88
                let perpX = -sin(angle) * rx * 0.18
                let perpY = cos(angle) * ry * 0.18
                p.move(to: CGPoint(x: cx, y: cy))
                p.addQuadCurve(
                    to: CGPoint(x: endX, y: endY),
                    control: CGPoint(x: (cx + endX) / 2 + perpX,
                                     y: (cy + endY) / 2 + perpY)
                )
            }
        }
    }
}

private struct TinyFlower: View {
    var petalSize: CGFloat = 6

    var body: some View {
        ZStack {
            // Petals
            ForEach(0..<5, id: \.self) { i in
                Ellipse()
                    .fill(Color(red: 1.0, green: 0.85, blue: 0.92))
                    .frame(width: petalSize, height: petalSize * 1.6)
                    .offset(y: -petalSize * 0.8)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            // Center
            Circle()
                .fill(Color(red: 1.0, green: 0.82, blue: 0.30))
                .frame(width: petalSize * 0.85, height: petalSize * 0.85)
        }
    }
}

private struct PondLilypad {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let phaseOffset: Double
    let sensitivity: Double
    let rotation: Double
}
