import AVKit
import SwiftUI

struct NowPlayingBar: View {
    @Environment(NoiseyStore.self) private var store
    @Binding var showingSounds: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Sounds button
            Button {
                showingSounds = true
            } label: {
                Image(systemName: "slider.vertical.3")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(true))
            }
            .buttonStyle(.plain)

            Spacer()

            // Now playing label
            if let sound = store.activeSound {
                Text(sound.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()

            // AirPlay route picker
            RoutePickerView()
                .frame(width: 44, height: 44)

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
                    .foregroundStyle(store.isPlaying ? .black : .white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .background(store.isPlaying ? .white : .clear, in: Circle())
                    .glassEffect(store.isPlaying ? .regular.interactive(true).tint(.white) : .regular.interactive(true), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: store.isPlaying)
    }
}

// MARK: - AVRoutePickerView Wrapper

struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
