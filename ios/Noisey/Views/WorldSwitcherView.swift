import MediaPlayer
import SwiftUI

private struct SystemVolumeReceiver: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        DeviceVolumeController.shared.install()
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct WorldSwitcherView: View {
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
                        y: skyGeo.size.height / 2
                    )
                }

                // Overlay UI (stays fixed)
                VStack(spacing: 0) {
                    statusBar
                        .padding(.top, geo.safeAreaInsets.top + 8)

                    Spacer()

                    NowPlayingBar(
                        showingSounds: $showingSounds
                    )
                    .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                }
            }
            .contentShape(Rectangle())
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
        .onChange(of: store.currentWorld) {
            // Reset drag progress when world changes from settings
            dragProgress = 0
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

}
