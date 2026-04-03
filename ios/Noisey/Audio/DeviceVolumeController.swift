import MediaPlayer

/// Manages a hidden MPVolumeView so the app can both read and write device volume.
final class DeviceVolumeController: @unchecked Sendable {
    static let shared = DeviceVolumeController()

    private var volumeView: MPVolumeView?
    private var slider: UISlider?

    @MainActor
    func install() -> MPVolumeView {
        if let existing = volumeView { return existing }
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        volumeView = view
        // Find the hidden slider inside MPVolumeView
        slider = view.subviews.compactMap { $0 as? UISlider }.first
        return view
    }

    @MainActor
    func setVolume(_ value: Float) {
        // If slider isn't found yet, try again
        if slider == nil, let view = volumeView {
            slider = view.subviews.compactMap { $0 as? UISlider }.first
        }
        slider?.value = value
    }
}
