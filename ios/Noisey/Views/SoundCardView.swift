import SwiftUI

struct SoundCardView: View {
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
                    ? .regular.interactive(true).tint(.white.opacity(0.3))
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
        case "ocean-surf": return "water.waves"
        case "warm-rain": return "cloud.rain"
        case "creek": return "drop.triangle"
        case "night-wind": return "wind"
        default: return sound.category == .custom ? "waveform" : "speaker.wave.2"
        }
    }
}
