import SwiftUI

struct SoundCardView: View {
    @Environment(NoiseyStore.self) private var store
    let sound: SoundEntry
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: sound))
                    .font(.footnote)
                    .foregroundStyle(isActive ? .white : .secondary)

                Text(sound.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isActive ? .white : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassEffect(
                isActive
                    ? .regular.interactive(true).tint(store.currentWorldConfig.accentColor.opacity(0.35))
                    : .regular.interactive(true)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if sound.category == .custom {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete?()
                }
            }
        }
    }

    private func icon(for sound: SoundEntry) -> String {
        switch sound.id {
        case "midnight-forest": return "moon.stars"
        case "morning-birds": return "bird"
        case "evening-frogs": return "lizard"
        default: return sound.category == .custom ? "waveform" : "speaker.wave.2"
        }
    }
}
