import SwiftUI

struct SoundGridView: View {
    @Environment(NoiseyStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Environment
                    environmentSection

                    sectionDivider

                    // Layer balance
                    balanceSection

                    sectionDivider

                    // Sleep timer
                    SleepTimerView()

                    sectionDivider

                    // Schedule
                    ScheduleView()

                    sectionDivider

                    // Speaker output
                    speakerSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("balance")

            VStack(spacing: 12) {
                BalanceSlider(label: "nature", icon: "leaf.fill", value: store.natureBalance) {
                    store.setBalance(.nature, to: $0)
                }
                BalanceSlider(label: "tone", icon: "waveform.path", value: store.toneBalance) {
                    store.setBalance(.tone, to: $0)
                }
                BalanceSlider(label: "chatter", icon: "bird.fill", value: store.chatterBalance) {
                    store.setBalance(.chatter, to: $0)
                }
            }
        }
    }

    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("speaker")

            HStack {
                Text("select speaker")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                RoutePickerView()
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular)
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("environment")

            HStack(spacing: 8) {
                ForEach(World.allCases, id: \.self) { world in
                    let config = WorldConfig.config(for: world)
                    let isActive = world == store.currentWorld

                    Button {
                        guard !isActive else { return }
                        store.switchWorld(to: world)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: environmentIcon(for: config.skyObjectType))
                                .font(.system(size: 22, weight: .medium))

                            Text(config.displayName.lowercased())
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        isActive
                            ? .regular.tint(config.accentColor.opacity(0.25))
                            : .regular
                    )
                }
            }
        }
    }

    private func environmentIcon(for type: WorldConfig.SkyObjectType) -> String {
        switch type {
        case .moon: return "moon.fill"
        case .sun: return "sun.max.fill"
        case .firefly: return "sparkles"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

