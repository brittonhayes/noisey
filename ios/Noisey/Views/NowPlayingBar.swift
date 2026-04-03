import SwiftUI

struct NowPlayingBar: View {
    @Environment(NoiseyStore.self) private var store
    @Binding var showingSounds: Bool

    private var isLight: Bool {
        store.currentWorld == .day
    }

    private var iconColor: Color {
        isLight ? .black.opacity(0.65) : .white.opacity(0.85)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Sounds button
            Button {
                showingSounds = true
            } label: {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .circle)

            // Play/pause button
            Button {
                if let active = store.activeSound {
                    store.toggleSound(id: active.id)
                } else if let first = store.sounds.first {
                    store.toggleSound(id: first.id)
                }
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(store.isPlaying ? .primary : iconColor)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(
                store.isPlaying
                    ? .regular.tint(store.currentWorldConfig.accentColor.opacity(0.35))
                    : .regular,
                in: .circle
            )
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: store.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: store.currentWorld)
    }

}
