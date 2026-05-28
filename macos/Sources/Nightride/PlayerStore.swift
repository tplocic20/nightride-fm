import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingText: String = ""

    private let player = AVPlayer()
    private var startedAt: Date?
    private var meta: MetaStream?
    private var rateObserver: NSKeyValueObservation?
    private let discord = DiscordRPC(clientID: "1396017162425991279")

    init() {
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let rate = change.newValue ?? 0
            Task { @MainActor [weak self] in
                self?.isPlaying = rate != 0
                self?.refreshNowPlaying()
            }
        }
    }

    deinit { rateObserver?.invalidate() }

    // MARK: – User intent

    func play(_ station: Station) {
        current = station
        startedAt = Date()
        nowPlayingText = ""

        let item = AVPlayerItem(url: station.streamURL)
        player.replaceCurrentItem(with: item)
        player.play()

        startMetaIfNeeded()
        refreshNowPlaying()
        discord.update(activity: discordActivity())
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if let cur = current {
            // Resuming a live stream from a stale buffer usually drops out.
            // Re-open the URL to get a fresh connection.
            play(cur)
        } else if let first = Stations.all.first {
            play(first)
        }
    }

    func pause() {
        player.pause()
        refreshNowPlaying()
        discord.update(activity: nil)
    }

    func next() { step(+1) }
    func prev() { step(-1) }

    private func step(_ delta: Int) {
        let list = Stations.all
        guard !list.isEmpty else { return }
        let baseIdx = current.flatMap { c in list.firstIndex(where: { $0.id == c.id }) } ?? -1
        let nextIdx = ((baseIdx + delta) % list.count + list.count) % list.count
        play(list[nextIdx])
    }

    // MARK: – Metadata

    private func startMetaIfNeeded() {
        if meta != nil { return }
        meta = MetaStream { [weak self] updates in
            Task { @MainActor [weak self] in
                self?.handleMeta(updates)
            }
        }
        meta?.start()
    }

    private func handleMeta(_ updates: [String: String]) {
        guard let cur = current, let title = updates[cur.id], !title.isEmpty else { return }
        nowPlayingText = title
        refreshNowPlaying()
        discord.update(activity: discordActivity())
    }

    // MARK: – Now Playing widget

    private func refreshNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let cur = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        let (track, artist) = splitTitle(nowPlayingText, station: cur)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let start = startedAt {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Date().timeIntervalSince(start)
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func splitTitle(_ raw: String, station: Station) -> (track: String, artist: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return (station.name, "Nightride FM")
        }
        if let dash = trimmed.range(of: " - ") {
            let artist = String(trimmed[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            let track  = String(trimmed[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (track, "\(artist) — \(station.name)")
        }
        return (trimmed, station.name)
    }

    // MARK: – Discord

    private func discordActivity() -> DiscordRPC.Activity? {
        guard let cur = current, isPlaying else { return nil }
        let (track, artist) = splitTitle(nowPlayingText, station: cur)
        return DiscordRPC.Activity(
            details: "Listening to \(cur.name)",
            state: artist,
            startTimestamp: startedAt,
            largeImage: cur.id == "nightride" ? "nrfm" : cur.id,
            largeText: track
        )
    }
}
