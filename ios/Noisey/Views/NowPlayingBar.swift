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
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular)

            Spacer()

            // Now playing label
            if let sound = store.activeSound {
                Text(sound.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isLight ? .black.opacity(0.5) : .secondary)
                    .transition(.opacity)
            }

            Spacer()

            // Play/pause button
            Button {
                if let active = store.activeSound {
                    store.toggleSound(id: active.id)
                } else if let first = store.sounds.first {
                    store.toggleSound(id: first.id)
                }
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(store.isPlaying ? (isLight ? .white : .black) : iconColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .background(store.isPlaying ? (isLight ? .black : .white) : .clear, in: Circle())
            .glassEffect(store.isPlaying ? .regular.tint(isLight ? .black : .white) : .regular, in: Circle())
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: store.isPlaying)
    }
}
