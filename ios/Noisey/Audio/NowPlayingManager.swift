import MediaPlayer

@MainActor
final class NowPlayingManager {
    private var onTogglePlayPause: (() -> Void)?
    private var onStop: (() -> Void)?

    func setup(onTogglePlayPause: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onTogglePlayPause = onTogglePlayPause
        self.onStop = onStop

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.onStop?()
            return .success
        }
    }

    func updateNowPlaying(soundName: String?, isPlaying: Bool) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = soundName ?? "Noisey"
        info[MPMediaItemPropertyArtist] = "Ambient Sound"
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
