import MediaPlayer
import SwiftUI

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

private struct SystemVolumeReceiver: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        DeviceVolumeController.shared.install()
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct ContentView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var showingSounds = false
    /// Drag progress from -1 (previous world) to 1 (next world).
    /// Drives the cross-fade blend between worlds instead of sliding pages.
    @State private var dragProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let worlds = World.allCases
            let currentIndex = worlds.firstIndex(of: store.currentWorld) ?? 0
            let progress = abs(dragProgress)

            // Determine which world we're blending toward
            let targetIndex: Int = {
                if dragProgress > 0 {
                    return min(currentIndex + 1, worlds.count - 1)
                } else if dragProgress < 0 {
                    return max(currentIndex - 1, 0)
                }
                return currentIndex
            }()

            let currentConfig = WorldConfig.config(for: worlds[currentIndex])
            let targetConfig = WorldConfig.config(for: worlds[targetIndex])
            let isTransitioning = targetIndex != currentIndex

            ZStack {
                // Background: blend between world gradients
                currentConfig.backgroundGradient
                if isTransitioning {
                    targetConfig.backgroundGradient
                        .opacity(progress)
                }

                // Particle layers: cross-fade
                particleLayer(for: currentConfig.skyObjectType)
                    .opacity(isTransitioning ? Double(1 - progress) : 1)

                if isTransitioning {
                    particleLayer(for: targetConfig.skyObjectType)
                        .opacity(Double(progress))
                }

                // Sky objects: cross-fade with scale + blur morph
                GeometryReader { skyGeo in
                    let vol = CGFloat(store.masterVolume)
                    // Keep the sky object above the page indicators at lowest volume
                    let bottomMargin: CGFloat = 160
                    let maxTravel = (skyGeo.size.height / 2 - bottomMargin)
                    let yOffset = (0.5 - vol) * maxTravel * 2

                    ZStack {
                        skyObject(for: currentConfig.skyObjectType)
                            .opacity(isTransitioning ? Double(1 - progress) : 1)
                            .scaleEffect(isTransitioning ? 1 - progress * 0.2 : 1)
                            .blur(radius: isTransitioning ? progress * 6 : 0)

                        if isTransitioning {
                            skyObject(for: targetConfig.skyObjectType)
                                .opacity(Double(progress))
                                .scaleEffect(0.8 + progress * 0.2)
                                .blur(radius: (1 - progress) * 6)
                        }
                    }
                    .position(
                        x: skyGeo.size.width / 2,
                        y: skyGeo.size.height / 2 + yOffset
                    )
                    .animation(
                        store.isDraggingVolume
                            ? .interactiveSpring(response: 0.15, dampingFraction: 0.8)
                            : .spring(response: 0.5, dampingFraction: 0.7),
                        value: store.masterVolume
                    )
                }

                // Overlay UI (stays fixed)
                VStack(spacing: 0) {
                    statusBar
                        .padding(.top, geo.safeAreaInsets.top + 8)

                    Spacer()

                    worldDots
                        .padding(.bottom, 12)

                    NowPlayingBar(showingSounds: $showingSounds)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard !store.isDraggingVolume else { return }
                        let pageWidth = geo.size.width
                        let raw = -value.translation.width / pageWidth

                        // Rubber-band at edges
                        if (currentIndex == 0 && raw < 0) ||
                           (currentIndex == worlds.count - 1 && raw > 0) {
                            dragProgress = raw * 0.25
                        } else {
                            dragProgress = max(-1, min(1, raw))
                        }
                    }
                    .onEnded { value in
                        guard !store.isDraggingVolume else {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                dragProgress = 0
                            }
                            return
                        }

                        let pageWidth = geo.size.width
                        let threshold: CGFloat = 0.2
                        let velocity = -(value.predictedEndTranslation.width - value.translation.width) / pageWidth

                        var shouldCommit = false
                        var newIndex = currentIndex

                        if dragProgress > threshold || velocity > 0.4 {
                            let next = min(currentIndex + 1, worlds.count - 1)
                            if next != currentIndex {
                                shouldCommit = true
                                newIndex = next
                            }
                        } else if dragProgress < -threshold || velocity < -0.4 {
                            let prev = max(currentIndex - 1, 0)
                            if prev != currentIndex {
                                shouldCommit = true
                                newIndex = prev
                            }
                        }

                        if shouldCommit {
                            let targetWorld = worlds[newIndex]
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                                dragProgress = dragProgress > 0 ? 1.0 : -1.0
                            } completion: {
                                // Commit the world change and reset instantly.
                                // currentWorld is now the target, so progress=0 is visually identical.
                                store.switchWorld(to: targetWorld)
                                dragProgress = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                dragProgress = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .background(SystemVolumeReceiver().frame(width: 0, height: 0))
        .sheet(isPresented: $showingSounds) {
            SoundGridView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    ZStack {
                        // World gradient bleeds through
                        store.currentWorldConfig.backgroundGradient
                        // Glass frost over the gradient
                        Rectangle().fill(.ultraThinMaterial)
                    }
                    .ignoresSafeArea()
                }
        }
        .preferredColorScheme(store.currentWorld == .day ? .light : .dark)
    }

    // MARK: - World layers

    @ViewBuilder
    private func particleLayer(for type: WorldConfig.SkyObjectType) -> some View {
        switch type {
        case .moon: StarfieldView(volume: store.masterVolume)
        case .sun: CloudFieldView(volume: store.masterVolume)
        case .firefly: FireflyFieldView(volume: store.masterVolume)
        }
    }

    @ViewBuilder
    private func skyObject(for type: WorldConfig.SkyObjectType) -> some View {
        switch type {
        case .moon: MoonVolumeView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sun: SunVolumeView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .firefly: EmptyView()
        }
    }

    // MARK: - Overlay UI

    private var statusBar: some View {
        HStack {
            if let timer = store.sleepTimer {
                let mins = timer.remainingSecs / 60
                let secs = timer.remainingSecs % 60
                Text("sleep \(mins)m \(secs)s")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("cancel") {
                    store.setSleepTimer(minutes: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private var worldDots: some View {
        HStack(spacing: 8) {
            ForEach(World.allCases, id: \.self) { world in
                let config = store.currentWorldConfig
                Circle()
                    .fill(store.currentWorld == world
                          ? config.accentColor.opacity(0.9)
                          : .white.opacity(0.25))
                    .frame(width: 6, height: 6)
                    .scaleEffect(store.currentWorld == world ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: store.currentWorld)
                    .onTapGesture {
                        guard world != store.currentWorld else { return }
                        let worlds = World.allCases
                        let currentIdx = worlds.firstIndex(of: store.currentWorld) ?? 0
                        let targetIdx = worlds.firstIndex(of: world) ?? 0
                        let direction: CGFloat = targetIdx > currentIdx ? 1 : -1

                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                            dragProgress = direction
                        } completion: {
                            store.switchWorld(to: world)
                            dragProgress = 0
                        }
                    }
            }
        }
    }
}
