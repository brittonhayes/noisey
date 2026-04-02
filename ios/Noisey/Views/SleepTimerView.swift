import SwiftUI

struct SleepTimerView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var selectedMinutes: Int? = nil

    private let presets: [(String, Int)] = [
        ("15m", 15),
        ("30m", 30),
        ("1h", 60),
        ("2h", 120),
        ("4h", 240),
        ("8h", 480),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("sleep")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer()

                if let timer = store.sleepTimer {
                    let mins = timer.remainingSecs / 60
                    let secs = timer.remainingSecs % 60
                    HStack(spacing: 6) {
                        Text("\(mins):\(String(format: "%02d", secs))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button {
                            selectedMinutes = nil
                            store.setSleepTimer(minutes: 0)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.1) { label, minutes in
                    Button {
                        selectedMinutes = minutes
                        store.setSleepTimer(minutes: minutes)
                    } label: {
                        Text(label)
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .glassEffect(
                                selectedMinutes == minutes
                                    ? .regular.interactive(true).tint(.white.opacity(0.12))
                                    : .regular.interactive(true)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
