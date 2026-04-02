import SwiftUI

struct ScheduleView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var startTime = dateFrom(hour: 22, minute: 0)
    @State private var stopTime = dateFrom(hour: 7, minute: 0)
    @State private var enabled = false
    @State private var selectedSoundId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("schedule")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer()

                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }

            if enabled {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "moon.fill")
                            .font(.footnote)
                            .foregroundStyle(Color(red: 0.55, green: 0.50, blue: 0.90))
                            .frame(width: 20)
                        Text("bedtime")
                            .font(.subheadline)
                        Spacer()
                        DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)

                    HStack {
                        Image(systemName: "sunrise.fill")
                            .font(.footnote)
                            .foregroundStyle(Color(red: 1.0, green: 0.70, blue: 0.38))
                            .frame(width: 20)
                        Text("wake up")
                            .font(.subheadline)
                        Spacer()
                        DatePicker("", selection: $stopTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if !store.sounds.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(height: 0.5)
                            .padding(.horizontal, 14)

                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.footnote)
                                .foregroundStyle(Color(red: 0.40, green: 0.75, blue: 0.78))
                                .frame(width: 20)
                            Text("sound")
                                .font(.subheadline)
                            Spacer()
                            Picker("", selection: $selectedSoundId) {
                                ForEach(store.sounds) { sound in
                                    Text(sound.name).tag(sound.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .glassEffect(.regular)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: enabled)
        .onAppear { loadSchedule() }
        .onChange(of: enabled) { _, _ in saveSchedule() }
        .onChange(of: startTime) { _, _ in saveSchedule() }
        .onChange(of: stopTime) { _, _ in saveSchedule() }
        .onChange(of: selectedSoundId) { _, _ in saveSchedule() }
    }

    private func loadSchedule() {
        if let schedule = store.schedule {
            startTime = parseTime(schedule.startTime) ?? startTime
            stopTime = parseTime(schedule.stopTime) ?? stopTime
            selectedSoundId = schedule.soundId
            enabled = schedule.enabled
        } else if let first = store.sounds.first {
            selectedSoundId = first.id
        }
    }

    private func saveSchedule() {
        guard enabled, !selectedSoundId.isEmpty else {
            if !enabled, store.schedule != nil {
                store.deleteSchedule()
            }
            return
        }
        let schedule = Schedule(
            startTime: formatTime(startTime),
            stopTime: formatTime(stopTime),
            soundId: selectedSoundId,
            enabled: true
        )
        store.setSchedule(schedule)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parseTime(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: string)
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }
}

private func dateFrom(hour: Int, minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
}
