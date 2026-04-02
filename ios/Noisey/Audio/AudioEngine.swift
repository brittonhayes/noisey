import AVFoundation
import os

/// Per-sample smoothing coefficient (~5ms at 44100Hz).
private let smoothCoeff: Float = 1.0 / (0.005 * Float(sampleRate))

/// Fade-in duration in samples (~1.5s at 44100Hz).
private let fadeInSamples: Int = 66150
/// Fade-out duration in samples (~0.5s at 44100Hz).
private let fadeOutSamples: Int = 22050

/// Hardcoded warmth level (40%).
private let warmth: Float = 0.4

/// Crossfade duration in samples (~4s at 44100Hz) for seamless file looping.
let crossfadeSamples: Int = Int(sampleRate) * 4

/// Max expected buffer size from Core Audio.
private let maxFrameCount = 4096

// MARK: - Active Sound (class for reference semantics — no copies in render loop)

final class ActiveSound: @unchecked Sendable {
    let generator: ProceduralGenerator?
    let fileSamples: [Float]?
    let fileChannels: Int
    var filePosition: Int = 0
    var volume: SmoothedValue
    var fade: Float = 0
    var fadeDelta: Float
    var pendingRemove: Bool = false

    init(generator: ProceduralGenerator, fadeDelta: Float) {
        self.generator = generator
        self.fileSamples = nil
        self.fileChannels = 0
        self.volume = SmoothedValue(initial: 1.0, coeff: smoothCoeff)
        self.fadeDelta = fadeDelta
    }

    init(samples: [Float], channels: Int, fadeDelta: Float) {
        self.generator = nil
        self.fileSamples = samples
        self.fileChannels = channels
        self.volume = SmoothedValue(initial: 1.0, coeff: smoothCoeff)
        self.fadeDelta = fadeDelta
    }

    func fillMono(_ buf: UnsafeMutablePointer<Float>, count: Int) {
        if let gen = generator {
            for i in 0..<count {
                buf[i] = gen.nextSample()
            }
        } else if let samples = fileSamples, !samples.isEmpty {
            let ch = fileChannels
            for i in 0..<count {
                var mono: Float = 0
                for c in 0..<ch {
                    mono += samples[(filePosition + c) % samples.count]
                }
                buf[i] = mono / Float(ch)
                filePosition = (filePosition + ch) % samples.count
            }
        } else {
            for i in 0..<count { buf[i] = 0 }
        }
    }
}

// MARK: - Mixer State

final class MixerState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var sounds: [String: ActiveSound] = [:]
    private var masterVolume = SmoothedValue(initial: 0.5, coeff: smoothCoeff)
    private var warmthFilterL: Biquad
    private var warmthFilterR: Biquad

    // Pre-allocated scratch buffers (avoid heap alloc in render callback)
    private var monoBuf = [Float](repeating: 0, count: maxFrameCount)
    private var masterRamp = [Float](repeating: 0, count: maxFrameCount)

    init() {
        let cutoff = MixerState.warmthToCutoff(warmth)
        warmthFilterL = Biquad.lowPass(freq: cutoff, q: 0.707)
        warmthFilterR = Biquad.lowPass(freq: cutoff, q: 0.707)
    }

    private static func warmthToCutoff(_ w: Float) -> Float {
        300.0 * powf(20000.0 / 300.0, 1.0 - w)
    }

    func setMasterVolume(_ vol: Float) {
        lock.withLock { masterVolume.set(vol) }
    }

    func play(id: String, sound: ActiveSound) {
        lock.withLock { sounds[id] = sound }
    }

    func stop(id: String) {
        lock.withLock {
            guard let sound = sounds[id] else { return }
            sound.fadeDelta = -1.0 / Float(fadeOutSamples)
            sound.pendingRemove = true
        }
    }

    func stopAll() {
        lock.withLock {
            for sound in sounds.values {
                sound.fadeDelta = -1.0 / Float(fadeOutSamples)
                sound.pendingRemove = true
            }
        }
    }

    func isPlaying(id: String) -> Bool {
        lock.withLock {
            guard let sound = sounds[id] else { return false }
            return !sound.pendingRemove
        }
    }

    /// Called from the audio render callback. Fills the mono mix buffer,
    /// then the caller copies to L/R channels.
    func render(into output: UnsafeMutablePointer<Float>, frameCount: Int) {
        // Zero output
        for i in 0..<frameCount { output[i] = 0 }

        nonisolated(unsafe) let out = output
        lock.withLock {
            if sounds.isEmpty && masterVolume.isSettled { return }

            // Pre-compute master volume ramp
            for i in 0..<frameCount {
                masterRamp[i] = masterVolume.next()
            }

            for (_, active) in sounds {
                active.fillMono(&monoBuf, count: frameCount)

                for i in 0..<frameCount {
                    let vol = active.volume.next()
                    let fade = max(0, min(1, active.fade + active.fadeDelta))
                    active.fade = fade
                    out[i] += monoBuf[i] * vol * fade * masterRamp[i]
                }
            }

            // Remove sounds whose fade-out completed
            let keysToRemove = sounds.keys.filter { sounds[$0]!.pendingRemove && sounds[$0]!.fade <= 0 }
            for key in keysToRemove {
                sounds.removeValue(forKey: key)
            }

            // Apply warmth filter (mono) and clamp
            for i in 0..<frameCount {
                out[i] = warmthFilterL.process(out[i])
                out[i] = max(-1.0, min(1.0, out[i]))
            }
        }
    }
}

// MARK: - Audio Engine

final class AudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let mixer = MixerState()
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    func setup() {
        configureAudioSession()
        setupNotifications()
        buildGraph()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AudioEngine: failed to configure session: \(error)")
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    try? self?.engine.start()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            if self?.engine.isRunning == false && self?.isRunning == true {
                try? self?.engine.start()
            }
        }
    }

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2)!
        // Pre-allocate a mono scratch buffer for the render callback
        let scratchBuf = UnsafeMutablePointer<Float>.allocate(capacity: maxFrameCount)
        scratchBuf.initialize(repeating: 0, count: maxFrameCount)

        let node = AVAudioSourceNode(format: format) { [mixer] _, _, frameCount, bufferList -> OSStatus in
            let count = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)

            // Render mono mix into scratch buffer
            mixer.render(into: scratchBuf, frameCount: count)

            // Copy mono to all channel buffers (non-interleaved format)
            for bufIdx in 0..<abl.count {
                guard let chData = abl[bufIdx].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<count {
                    chData[i] = scratchBuf[i]
                }
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            print("AudioEngine: failed to start: \(error)")
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    // MARK: - Public API

    func play(id: String) {
        guard let gen = ProceduralGenerator.create(id: id) else { return }
        let sound = ActiveSound(
            generator: gen,
            fadeDelta: 1.0 / Float(fadeInSamples)
        )
        mixer.play(id: id, sound: sound)
        start()
    }

    func playFile(id: String, samples: [Float], channels: Int) {
        let sound = ActiveSound(
            samples: samples,
            channels: channels,
            fadeDelta: 1.0 / Float(fadeInSamples)
        )
        mixer.play(id: id, sound: sound)
        start()
    }

    func stopSound(id: String) {
        mixer.stop(id: id)
    }

    func stopAll() {
        mixer.stopAll()
    }

    func setMasterVolume(_ volume: Float) {
        mixer.setMasterVolume(volume)
    }

    func isPlaying(id: String) -> Bool {
        mixer.isPlaying(id: id)
    }
}
