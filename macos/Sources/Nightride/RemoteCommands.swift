import MediaPlayer

@MainActor
enum RemoteCommands {
    static func install(_ store: PlayerStore) {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { _ in
            Task { @MainActor in store.togglePlayPause() }
            return .success
        }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { _ in
            Task { @MainActor in store.pause() }
            return .success
        }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in store.togglePlayPause() }
            return .success
        }

        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { _ in
            Task { @MainActor in store.next() }
            return .success
        }

        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { _ in
            Task { @MainActor in store.prev() }
            return .success
        }

        // Disable scrubbing — this is a live stream.
        cc.seekForwardCommand.isEnabled = false
        cc.seekBackwardCommand.isEnabled = false
        cc.skipForwardCommand.isEnabled = false
        cc.skipBackwardCommand.isEnabled = false
        cc.changePlaybackPositionCommand.isEnabled = false
    }
}
