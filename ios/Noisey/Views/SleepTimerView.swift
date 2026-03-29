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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("sleep")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if let timer = store.sleepTimer {
                    let mins = timer.remainingSecs / 60
                    let secs = timer.remainingSecs % 60
                    HStack(spacing: 4) {
                        Text("\(mins):\(String(format: "%02d", secs))")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                        Button {
                            Task {
                                selectedMinutes = nil
                                await store.setSleepTimer(minutes: 0)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(presets, id: \.1) { label, minutes in
                    Button {
                        Task {
                            selectedMinutes = minutes
                            await store.setSleepTimer(minutes: minutes)
                        }
                    } label: {
                        Text(label)
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedMinutes == minutes
                                    ? Color.white.opacity(0.12)
                                    : Color.clear
                            )
                            .glassEffect(.regular.interactive(true))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
