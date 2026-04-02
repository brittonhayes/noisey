import AVFoundation
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
    var isDraggingVolume: Bool = false
    var currentWorld: World = .night
    /// Smoothed audio amplitude from the engine (0…1), updated at ~15 Hz for visuals.
    var audioLevel: Float = 0

    private var volumePollTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?

    var activeSound: SoundEntry? {
        sounds.first { $0.active }
    }

    var isPlaying: Bool {
        activeSound != nil
    }

    var currentWorldConfig: WorldConfig {
        WorldConfig.config(for: currentWorld)
    }

    var currentWorldSounds: [SoundEntry] {
        let config = currentWorldConfig
        return sounds.filter { config.soundIDs.contains($0.id) || $0.category == .custom }
    }

    let engine = AudioEngine()
    private let nowPlayingManager = NowPlayingManager()
    private var sleepTimerTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var fileCache: [String: (samples: [Float], channels: Int)] = [:]

    init() {
        engine.setup()
        loadSounds()
        loadSchedule()
        startScheduleWatcher()
        observeDeviceVolume()
        startAudioLevelPolling()

        nowPlayingManager.setup(
            onTogglePlayPause: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.togglePlayPause()
                }
            },
            onStop: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.stopAll()
                }
            }
        )
    }

    // MARK: - Device Volume

    private func observeDeviceVolume() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)

        // Seed from current device volume
        masterVolume = session.outputVolume
        engine.setMasterVolume(masterVolume)

        // Poll device volume at ~10Hz — KVO on outputVolume is unreliable
        volumePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                // Skip polling while user is dragging to avoid fighting the gesture
                guard !self.isDraggingVolume else { continue }
                let vol = session.outputVolume
                if abs(vol - self.masterVolume) > 0.001 {
                    self.masterVolume = vol
                    self.engine.setMasterVolume(vol)
                }
            }
        }
    }

    // MARK: - Audio Level Metering

    private func startAudioLevelPolling() {
        audioLevelTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(66)) // ~15 Hz
                guard let self else { return }
                self.audioLevel = self.engine.rmsLevel
            }
        }
    }

    // MARK: - Sound Catalog

    private func loadSounds() {
        // Built-in procedural sounds
        let builtIn: [SoundEntry] = [
            // Night
            SoundEntry(id: "ocean-surf", name: "Ocean Surf", category: .nature, active: false),
            SoundEntry(id: "warm-rain", name: "Warm Rain", category: .nature, active: false),
            SoundEntry(id: "creek", name: "Creek", category: .nature, active: false),
            SoundEntry(id: "night-wind", name: "Night Wind", category: .nature, active: false),
            // Day
            SoundEntry(id: "morning-birds", name: "Morning Birds", category: .nature, active: false),
            SoundEntry(id: "forest-canopy", name: "Forest Canopy", category: .nature, active: false),
            SoundEntry(id: "meadow-breeze", name: "Meadow Breeze", category: .nature, active: false),
            // Dusk
            SoundEntry(id: "crickets", name: "Crickets", category: .nature, active: false),
            SoundEntry(id: "evening-frogs", name: "Evening Frogs", category: .nature, active: false),
            SoundEntry(id: "twilight-wind", name: "Twilight Wind", category: .nature, active: false),
        ]

        // Custom sounds from disk
        let custom = SoundFileManager.loadAllCustomSounds()

        sounds = builtIn + custom

        // Restore persisted world
        if let saved = UserDefaults.standard.string(forKey: "currentWorld"),
           let world = World(rawValue: saved) {
            currentWorld = world
        }
    }

    // MARK: - World

    func switchWorld(to world: World) {
        let oldConfig = currentWorldConfig
        currentWorld = world
        UserDefaults.standard.set(world.rawValue, forKey: "currentWorld")

        // If a sound from the old world is playing, crossfade to new world's default
        if let active = activeSound, oldConfig.soundIDs.contains(active.id) {
            let newConfig = currentWorldConfig
            toggleSound(id: active.id)   // stop old
            toggleSound(id: newConfig.defaultSoundID) // start new
        }
    }

    // MARK: - Playback

    func toggleSound(id: String) {
        // If this sound is already active, stop it
        if let idx = sounds.firstIndex(where: { $0.id == id }), sounds[idx].active {
            sounds[idx].active = false
            engine.stopSound(id: id)
            updateNowPlaying()
            return
        }

        // Stop all other sounds first
        for i in sounds.indices {
            if sounds[i].active {
                sounds[i].active = false
                engine.stopSound(id: sounds[i].id)
            }
        }

        // Start the new sound
        if let idx = sounds.firstIndex(where: { $0.id == id }) {
            sounds[idx].active = true

            if ProceduralGenerator.create(id: id) != nil {
                engine.play(id: id)
            } else {
                // File-based sound
                if let cached = fileCache[id] {
                    engine.playFile(id: id, samples: cached.samples, channels: cached.channels)
                } else if let decoded = SoundFileManager.decodedSamples(for: id) {
                    fileCache[id] = decoded
                    engine.playFile(id: id, samples: decoded.samples, channels: decoded.channels)
                }
            }

            updateNowPlaying()
        }
    }

    private func togglePlayPause() {
        if let active = activeSound {
            toggleSound(id: active.id)
        } else if let first = sounds.first {
            toggleSound(id: first.id)
        }
    }

    func stopAll() {
        for i in sounds.indices {
            sounds[i].active = false
        }
        engine.stopAll()
        updateNowPlaying()
    }

    func setVolume(_ volume: Float) {
        masterVolume = volume
        engine.setMasterVolume(volume)
        DeviceVolumeController.shared.setVolume(volume)
    }

    // MARK: - Sound Management

    func deleteSound(id: String) {
        if let idx = sounds.firstIndex(where: { $0.id == id }) {
            if sounds[idx].active {
                engine.stopSound(id: id)
            }
            sounds.remove(at: idx)
        }
        fileCache.removeValue(forKey: id)
        SoundFileManager.deleteSound(id: id)
    }

    func uploadSound(fileURL: URL, name: String?) {
        guard let entry = SoundFileManager.importSound(from: fileURL, name: name) else { return }
        sounds.append(entry)
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        guard minutes > 0 else {
            sleepTimer = nil
            return
        }

        let durationSecs = minutes * 60
        let endDate = Date().addingTimeInterval(TimeInterval(durationSecs))

        sleepTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = Int(endDate.timeIntervalSinceNow)
                if remaining <= 0 {
                    await MainActor.run {
                        self?.stopAll()
                        self?.sleepTimer = nil
                    }
                    return
                }
                await MainActor.run {
                    self?.sleepTimer = TimerStatus(remainingSecs: remaining, durationSecs: durationSecs)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Schedule

    func setSchedule(_ schedule: Schedule) {
        self.schedule = schedule
        saveSchedule()
        startScheduleWatcher()
    }

    func deleteSchedule() {
        schedule = nil
        scheduleTask?.cancel()
        scheduleTask = nil
        UserDefaults.standard.removeObject(forKey: "schedule")
    }

    private func saveSchedule() {
        guard let schedule else { return }
        if let data = try? JSONEncoder().encode(schedule) {
            UserDefaults.standard.set(data, forKey: "schedule")
        }
    }

    private func loadSchedule() {
        guard let data = UserDefaults.standard.data(forKey: "schedule"),
              let schedule = try? JSONDecoder().decode(Schedule.self, from: data) else { return }
        self.schedule = schedule
    }

    private func startScheduleWatcher() {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, let schedule = await self.schedule, schedule.enabled else { continue }

                let now = Date()
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: now)
                let minute = calendar.component(.minute, from: now)
                let currentMinutes = hour * 60 + minute

                let startParts = schedule.startTime.split(separator: ":").compactMap { Int($0) }
                let stopParts = schedule.stopTime.split(separator: ":").compactMap { Int($0) }
                guard startParts.count == 2, stopParts.count == 2 else { continue }

                let startMinutes = startParts[0] * 60 + startParts[1]
                let stopMinutes = stopParts[0] * 60 + stopParts[1]

                let inWindow: Bool
                if startMinutes <= stopMinutes {
                    inWindow = currentMinutes >= startMinutes && currentMinutes < stopMinutes
                } else {
                    // Overnight window (e.g., 22:00 - 07:00)
                    inWindow = currentMinutes >= startMinutes || currentMinutes < stopMinutes
                }

                await MainActor.run {
                    if inWindow && !self.isPlaying {
                        self.toggleSound(id: schedule.soundId)
                    } else if !inWindow && self.isPlaying {
                        self.stopAll()
                    }
                }
            }
        }
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        if let active = activeSound {
            nowPlayingManager.updateNowPlaying(soundName: active.name, isPlaying: true)
        } else {
            nowPlayingManager.clearNowPlaying()
        }
    }
}
