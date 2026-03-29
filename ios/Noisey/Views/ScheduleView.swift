import SwiftUI

struct ScheduleView: View {
    @Environment(NoiseyStore.self) private var store
    @State private var startTime = dateFrom(hour: 22, minute: 0)
    @State private var stopTime = dateFrom(hour: 7, minute: 0)
    @State private var enabled = false
    @State private var selectedSoundId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("schedule")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }

            if enabled {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "moon.fill")
                            .font(.footnote)
                            .foregroundStyle(.indigo)
                            .frame(width: 20)
                        Text("Bedtime")
                            .font(.footnote)
                        Spacer()
                        DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    HStack {
                        Image(systemName: "sunrise.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        Text("Wake Up")
                            .font(.footnote)
                        Spacer()
                        DatePicker("", selection: $stopTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    if !store.sounds.isEmpty {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.footnote)
                                .foregroundStyle(.teal)
                                .frame(width: 20)
                            Text("Sound")
                                .font(.footnote)
                            Spacer()
                            Picker("", selection: $selectedSoundId) {
                                ForEach(store.sounds) { sound in
                                    Text(sound.name).tag(sound.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.secondary)
                        }
                    }
                }
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
                Task { await store.deleteSchedule() }
            }
            return
        }
        let schedule = Schedule(
            startTime: formatTime(startTime),
            stopTime: formatTime(stopTime),
            soundId: selectedSoundId,
            enabled: true
        )
        Task { await store.setSchedule(schedule) }
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
