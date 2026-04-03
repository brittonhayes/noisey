@preconcurrency import Motion
import SwiftUI

/// Wraps a Motion SpringAnimation to drive the sky object's Y offset.
/// Drag moves the object; release springs it back to center.
/// Volume is NOT affected — it's controlled only by hardware buttons.
@Observable
@MainActor
final class SkyDragController {
    var offset: CGPoint = .zero

    private let spring: SpringAnimation<CGPoint>

    init() {
        let s = SpringAnimation<CGPoint>(response: 0.50, dampingRatio: 0.75)
        s.updateValue(to: .zero, postValueChanged: false)
        s.toValue = .zero
        self.spring = s

        s.onValueChanged { [weak self] newValue in
            self?.offset = newValue
        }
    }

    func drag(translation: CGSize) {
        spring.stop()
        offset = CGPoint(x: translation.width, y: translation.height)
        spring.updateValue(to: offset, postValueChanged: false)
    }

    func release(velocity: CGSize) {
        spring.velocity = CGPoint(x: velocity.width, y: velocity.height)
        spring.toValue = .zero
        spring.start()
    }
}

/// Attaches a drag gesture that moves the sky object freely via a Motion spring.
/// On release the object springs back to center. Does not affect volume.
struct SkyDragModifier: ViewModifier {
    @State private var controller = SkyDragController()

    func body(content: Content) -> some View {
        content
            .offset(x: controller.offset.x, y: controller.offset.y)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        controller.drag(translation: value.translation)
                    }
                    .onEnded { value in
                        let vel = CGSize(
                            width: value.predictedEndTranslation.width - value.translation.width,
                            height: value.predictedEndTranslation.height - value.translation.height
                        )
                        controller.release(velocity: vel)
                    }
            )
    }
}

extension View {
    func skyDrag() -> some View {
        modifier(SkyDragModifier())
    }
}

// MARK: - Water Drag (Lilypad)

/// Drives a lilypad's position using Motion's DecayAnimation.
/// Drag moves it 1:1; release lets it coast to a stop like it's floating on water.
@Observable
@MainActor
final class WaterDragController {
    var position: CGPoint = .zero

    private let decay: DecayAnimation<CGPoint>
    private var bounds: CGRect = .zero

    init(initial: CGPoint = .zero) {
        position = initial
        let d = DecayAnimation<CGPoint>()
        d.updateValue(to: initial, postValueChanged: false)
        self.decay = d

        d.onValueChanged { [weak self] newValue in
            guard let self else { return }
            // Keep within bounds
            self.position = self.clamped(newValue)
        }
    }

    func setBounds(_ rect: CGRect) {
        bounds = rect
    }

    func drag(to point: CGPoint) {
        decay.stop()
        position = clamped(point)
        decay.updateValue(to: position, postValueChanged: false)
    }

    func release(velocity: CGPoint) {
        decay.velocity = velocity
        decay.start()
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        guard bounds.width > 0 else { return p }
        let margin: CGFloat = 40
        return CGPoint(
            x: min(bounds.maxX - margin, max(bounds.minX + margin, p.x)),
            y: min(bounds.maxY - margin, max(bounds.minY + margin, p.y))
        )
    }
}
