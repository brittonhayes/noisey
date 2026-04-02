import AVFoundation
import Foundation

struct SoundFileManager {
    private static var soundsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Import a sound file into the app's sounds directory.
    /// Returns a SoundEntry for the imported sound, or nil on failure.
    static func importSound(from sourceURL: URL, name: String?) -> SoundEntry? {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()
        let id = stem.lowercased().replacingOccurrences(of: " ", with: "-")
        let destURL = soundsDirectory.appendingPathComponent("\(id).\(ext)")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("SoundFileManager: failed to copy file: \(error)")
            return nil
        }

        // Validate by decoding
        guard decodeFile(at: destURL) != nil else {
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }

        let displayName = name ?? humanizeFilename(stem)

        return SoundEntry(
            id: id,
            name: displayName,
            category: .custom,
            active: false
        )
    }

    /// Delete a custom sound file.
    static func deleteSound(id: String) {
        let dir = soundsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for entry in entries {
            let url = dir.appendingPathComponent(entry)
            let stem = url.deletingPathExtension().lastPathComponent
            if stem == id {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Load all custom sounds from disk.
    static func loadAllCustomSounds() -> [SoundEntry] {
        let dir = soundsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }

        let audioExtensions = Set(["wav", "mp3", "m4a", "aac", "flac", "ogg", "aiff"])
        var sounds: [SoundEntry] = []

        for entry in entries.sorted() {
            let url = dir.appendingPathComponent(entry)
            let ext = url.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }

            let stem = url.deletingPathExtension().lastPathComponent
            sounds.append(SoundEntry(
                id: stem,
                name: humanizeFilename(stem),
                category: .custom,
                active: false
            ))
        }

        return sounds
    }

    /// Decode a sound file to raw samples for playback.
    /// Returns (samples, channelCount) or nil on failure.
    static func decodedSamples(for id: String) -> (samples: [Float], channels: Int)? {
        let dir = soundsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }

        for entry in entries {
            let url = dir.appendingPathComponent(entry)
            let stem = url.deletingPathExtension().lastPathComponent
            if stem == id {
                return decodeFile(at: url)
            }
        }
        return nil
    }

    /// Decode an audio file using AVAudioFile and bake crossfade for seamless looping.
    private static func decodeFile(at url: URL) -> (samples: [Float], channels: Int)? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return nil
        }

        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)

        // Interleave channels
        var samples = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            for ch in 0..<channels {
                guard let channelData = buffer.floatChannelData?[ch] else { return nil }
                samples[frame * channels + ch] = channelData[frame]
            }
        }

        // Bake crossfade for seamless looping
        samples = bakeCrossfade(samples, channels: channels)

        return (samples, channels)
    }

    /// Bake a crossfade into the sample buffer for seamless looping.
    /// Equal-power cosine curve, matching the Rust implementation.
    private static func bakeCrossfade(_ samples: [Float], channels: Int) -> [Float] {
        var samples = samples
        let totalFrames = samples.count / channels
        let crossfadeFrames = min(crossfadeSamples, totalFrames / 3)

        // Too short to crossfade meaningfully (<100ms)
        if crossfadeFrames < Int(sampleRate) / 10 {
            return samples
        }

        let halfPi = Float.pi / 2.0

        for i in 0..<crossfadeFrames {
            let t = Float(i) / Float(crossfadeFrames)
            let gainOut = sin(halfPi * (1.0 - t))
            let gainIn = sin(halfPi * t)

            for c in 0..<channels {
                let tailIdx = (totalFrames - crossfadeFrames + i) * channels + c
                let headIdx = i * channels + c
                samples[tailIdx] = samples[tailIdx] * gainOut + samples[headIdx] * gainIn
            }
        }

        // Trim the head region that's now baked into the tail crossfade
        let trimStart = crossfadeFrames * channels
        samples.removeFirst(trimStart)

        return samples
    }

    private static func humanizeFilename(_ stem: String) -> String {
        stem.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
