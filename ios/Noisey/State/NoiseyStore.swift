import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class NoiseyStore {
    var sounds: [SoundEntry] = []
    var masterVolume: Float = 0.5
    var sleepTimer: TimerStatus? = nil
    var schedule: Schedule? = nil
    var isSimulating: Bool = false
    var isConnected: Bool = false
    var isDraggingVolume: Bool = false

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    var hasServer: Bool {
        !serverURL.isEmpty
    }

    var activeSound: SoundEntry? {
        sounds.first { $0.active }
    }

    var isPlaying: Bool {
        activeSound != nil
    }

    private var client: NoiseyClient?
    private var pollTask: Task<Void, Never>?

    func connect() {
        guard let url = URL(string: serverURL) else { return }
        client = NoiseyClient(baseURL: url)
        startPolling()
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        client = nil
        isConnected = false
        sounds = []
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func poll() async {
        guard let client, !isDraggingVolume else { return }
        do {
            let status = try await client.status()
            sounds = status.sounds
            masterVolume = status.masterVolume
            sleepTimer = status.sleepTimer
            schedule = status.schedule
            isSimulating = status.simulate
            isConnected = true
        } catch {
            isConnected = false
        }
    }

    // MARK: - Actions

    func toggleSound(id: String) async {
        guard let client else { return }
        do {
            let status = try await client.toggleSound(id: id)
            applyStatus(status)
        } catch {}
    }

    func deleteSound(id: String) async {
        guard let client else { return }
        do {
            let status = try await client.deleteSound(id: id)
            applyStatus(status)
        } catch {}
    }

    func setVolume(_ volume: Float) async {
        guard let client else { return }
        do {
            let status = try await client.setVolume(volume)
            if !isDraggingVolume {
                applyStatus(status)
            }
        } catch {}
    }

    func setSleepTimer(minutes: Int) async {
        guard let client else { return }
        do {
            let status = try await client.setSleepTimer(minutes: minutes)
            applyStatus(status)
        } catch {}
    }

    func setSchedule(_ schedule: Schedule) async {
        guard let client else { return }
        do {
            let status = try await client.setSchedule(schedule)
            applyStatus(status)
        } catch {}
    }

    func deleteSchedule() async {
        guard let client else { return }
        do {
            let status = try await client.deleteSchedule()
            applyStatus(status)
        } catch {}
    }

    func uploadSound(fileURL: URL, name: String?, description: String?) async {
        guard let client else { return }
        do {
            _ = try await client.uploadSound(fileURL: fileURL, name: name, description: description)
            await poll()
        } catch {}
    }

    private func applyStatus(_ status: StatusResponse) {
        sounds = status.sounds
        masterVolume = status.masterVolume
        sleepTimer = status.sleepTimer
        schedule = status.schedule
        isSimulating = status.simulate
        isConnected = true
    }
}
