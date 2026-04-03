import SwiftUI

/// Sheet content for picking a world — large tappable icons with labels.
struct WorldPickerSheet: View {
    @Environment(NoiseyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var dragProgress: CGFloat

    private let worlds = World.allCases

    var body: some View {
        VStack(spacing: 20) {
            Text("environment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)
                .padding(.top, 8)

            HStack(spacing: 12) {
                ForEach(worlds, id: \.self) { world in
                    let config = WorldConfig.config(for: world)
                    let isActive = world == store.currentWorld

                    Button {
                        guard !isActive else {
                            dismiss()
                            return
                        }
                        transitionTo(world)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: iconName(for: config.skyObjectType))
                                .font(.system(size: 28, weight: .medium))

                            Text(config.displayName.lowercased())
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private func transitionTo(_ world: World) {
        let currentIndex = worlds.firstIndex(of: store.currentWorld) ?? 0
        let targetIdx = worlds.firstIndex(of: world) ?? 0
        let direction: CGFloat = targetIdx > currentIndex ? 1 : -1

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            dragProgress = direction
        } completion: {
            store.switchWorld(to: world)
            dragProgress = 0
        }
    }

    private func iconName(for type: WorldConfig.SkyObjectType) -> String {
        switch type {
        case .moon: return "moon.fill"
        case .sun: return "sun.max.fill"
        case .firefly: return "sparkles"
        }
    }
}
