import AVFoundation
import Combine
import MediaPlayer
import Network
import UIKit

@MainActor
final class PlayerStore: ObservableObject {
    static let shared = PlayerStore()

    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlaying: TrackMeta?

    private let player = AVPlayer()
    private var startedAt: Date?
    /// Reads the live station's now-playing line from the MP3 stream's in-band ICY
    /// `StreamTitle` (see `open`). Because it rides the same buffer as the audio it
    /// lands in step with what the listener hears — no fixed offset to guess at.
    private lazy var icyReader = ICYMetadataReader { [weak self] title in
        Task { @MainActor [weak self] in self?.handleICYTitle(title) }
    }
    private var meta: MetaStream?
    /// Latest known track per station id — kept warm so selecting a station
    /// shows its current track instantly, instead of waiting for the next change.
    /// Published so the CarPlay station list can show every station's live track
    /// and patch its rows when the feed updates.
    @Published private(set) var latestMeta: [String: TrackMeta] = [:]
    private var rateObserver: NSKeyValueObservation?

    // MARK: Reconnect state
    /// The listener's intent. A dropped stream is re-opened only while this is set.
    private var wantsPlay = false
    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var itemObservers: [NSObjectProtocol] = []
    private var statusObserver: NSKeyValueObservation?
    private let pathMonitor = NWPathMonitor()

    /// Seconds of audio to collect before playback starts — a cushion that rides
    /// out dead zones (driving, border crossings). 0 = start immediately.
    @Published var bufferSeconds = UserDefaults.standard.integer(forKey: "bufferSeconds") {
        didSet { UserDefaults.standard.set(bufferSeconds, forKey: "bufferSeconds") }
    }
    private var startTask: Task<Void, Never>?

    init() {
        configureAudioSession()

        // Remember the last station so a fresh launch (phone or CarPlay) can
        // resume with one tap instead of picking from the list again.
        if let id = UserDefaults.standard.string(forKey: "lastStationId"),
           let station = Stations.all.first(where: { $0.id == id }) {
            current = station
            // Publish station name + logo to Now Playing (CarPlay / Lock Screen)
            // immediately, in paused state, so the car shows the station before
            // any audio is started.
            refreshNowPlaying()
        }

        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let rate = change.newValue ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Keep showing "playing" while a dropped stream reconnects.
                self.isPlaying = rate != 0 || self.retryTask != nil || self.startTask != nil
                if rate != 0 { self.retryAttempt = 0 }
                self.refreshNowPlaying()
            }
        }
        // Network back (tunnel exit, cell handover): reconnect now, skip backoff.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.retryTask != nil, let cur = self.current else { return }
                self.retryTask?.cancel(); self.retryTask = nil
                self.open(cur)
            }
        }
        pathMonitor.start(queue: .main)
        // Connect to the metadata feed at launch so every station's current
        // track is cached before the user ever hits play.
        startMeta()

        // Install transport commands here (once), not from a SwiftUI .onAppear —
        // the car can launch the app straight into CarPlay with no phone view,
        // and the Lock Screen / Now Playing / CarPlay buttons must still work.
        RemoteCommands.install(self)
    }

    deinit {
        rateObserver?.invalidate()
    }

    // MARK: – User intent

    func play(_ station: Station) {
        wantsPlay = true
        retryAttempt = 0
        current = station
        UserDefaults.standard.set(station.id, forKey: "lastStationId")
        startedAt = Date()
        // No cached seed here: latestMeta can be hours old after inactivity, and
        // a wrong artist that flips on play is worse than ~1s of blank. The
        // in-band ICY title fills this in as soon as audio is buffered.

        open(station)
        refreshNowPlaying()
    }

    private func open(_ station: Station) {
        retryTask?.cancel(); retryTask = nil
        let item = AVPlayerItem(url: station.streamURL)
        // Hold a cushion of audio so short dropouts (driving) play through.
        item.preferredForwardBufferDuration = Double(max(20, bufferSeconds + 10))
        watch(item)
        // Pull the live now-playing line from the stream's in-band ICY metadata so
        // it tracks the buffered audio (see `icyReader` / `handleICYTitle`).
        let icyOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        icyOutput.setDelegate(icyReader, queue: .main)
        item.add(icyOutput)
        player.replaceCurrentItem(with: item)
        startTask?.cancel(); startTask = nil
        guard bufferSeconds > 0 else { player.play(); return }
        // Hold playback until the cushion is filled; playing behind live keeps it.
        let target = Double(bufferSeconds)
        isPlaying = true
        startTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.player.currentItem === item else { return }
                let now = item.currentTime().seconds
                let ahead = item.loadedTimeRanges.map(\.timeRangeValue)
                    .filter { $0.containsTime(item.currentTime()) }
                    .map { $0.end.seconds - now }.max() ?? 0
                if ahead >= target {
                    self.startTask = nil
                    self.player.play()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if let cur = current {
            // Live streams resume poorly from a stale buffer — re-open.
            play(cur)
        } else if let first = Stations.all.first {
            play(first)
        }
    }

    func pause() {
        // Drop the displayed track: while inactive it would sit there looking
        // current when it's actually the last song heard (possibly hours old).
        // The brand name shows instead until the next play() streams fresh ICY.
        nowPlaying = nil
        wantsPlay = false
        retryTask?.cancel(); retryTask = nil
        startTask?.cancel(); startTask = nil
        player.pause()
        refreshNowPlaying()
    }

    func next() { step(+1) }
    func prev() { step(-1) }

    private func step(_ delta: Int) {
        let list = Stations.all
        guard !list.isEmpty else { return }
        // Nothing playing yet: sit just off whichever end the step comes from,
        // so next lands on the first station and prev on the last. A single
        // -1 sentinel would make prev skip the last one and land on Rekt.
        let baseIdx = current.flatMap { c in list.firstIndex(where: { $0.id == c.id }) }
            ?? (delta > 0 ? -1 : 0)
        let nextIdx = ((baseIdx + delta) % list.count + list.count) % list.count
        play(list[nextIdx])
    }

    // MARK: – Reconnect

    /// Re-open the stream whenever it dies: hard failure, the server closing the
    /// connection (a live stream "ending"), or a stall that outlasts the buffer.
    private func watch(_ item: AVPlayerItem) {
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        let nc = NotificationCenter.default
        itemObservers = [.AVPlayerItemFailedToPlayToEndTime, .AVPlayerItemDidPlayToEndTime]
            .map { nc.addObserver(forName: $0, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleReconnect() }
            } }
        // AVPlayer waits through a stall on its own; if it's still silent after
        // 10s the socket is likely dead, so reconnect.
        itemObservers.append(nc.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.player.currentItem === item, self.player.timeControlStatus != .playing else { return }
                self.scheduleReconnect()
            }
        })
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.scheduleReconnect() }
        }
    }

    /// Backoff 1, 2, 4, 8, 15, 15… seconds, forever, while the listener wants audio.
    private func scheduleReconnect() {
        guard wantsPlay, retryTask == nil, let station = current else { return }
        let delay = min(Double(1 << min(retryAttempt, 4)), 15)
        retryAttempt += 1
        isPlaying = true
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.wantsPlay else { return }
            self.open(station)
        }
    }

    // MARK: – Sleep timer

    /// Seconds left on the sleep timer, or nil when it's off.
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    private var sleepTask: Task<Void, Never>?

    /// Pause playback after `minutes`, fading volume over the last minute so
    /// the music goes out gently instead of cutting mid-song.
    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepTask = Task { [weak self] in
            var remaining = minutes * 60
            self?.sleepTimerRemaining = TimeInterval(remaining)
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                remaining -= 1
                self.sleepTimerRemaining = TimeInterval(remaining)
                if remaining <= 60 { self.player.volume = Float(remaining) / 60 }
            }
            self?.sleepTimerFired()
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerRemaining = nil
        player.volume = 1
    }

    private func sleepTimerFired() {
        pause()
        player.volume = 1
        sleepTimerRemaining = nil
        sleepTask = nil
    }

    // MARK: – Audio session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("AudioSession error: \(error)")
        }
    }

    // MARK: – Metadata

    private func startMeta() {
        guard meta == nil else { return }
        meta = MetaStream { [weak self] updates in
            Task { @MainActor [weak self] in
                self?.handleMeta(updates)
            }
        }
        meta?.start()
    }

    /// The `/meta` feed is the live edge (instant), so it only warms the per-station
    /// cache that feeds the station list / CarPlay browse and the instant display on
    /// station-switch. The live station's now-playing line is driven by the audio's
    /// in-band ICY metadata in `handleICYTitle`, not from here.
    private func handleMeta(_ updates: [String: TrackMeta]) {
        latestMeta.merge(updates) { _, new in new }
    }

    /// Apply an in-band ICY `StreamTitle` from the playing stream. It rides the same
    /// buffer as the audio, so the displayed track flips exactly when the listener
    /// hears the song change — no offset to tune.
    private func handleICYTitle(_ raw: String) {
        guard current != nil else { return }
        let track = TrackMeta(icyStreamTitle: raw)
        guard !track.isEmpty else { return }
        nowPlaying = track
        refreshNowPlaying()
    }

    // MARK: – Now Playing widget (Lock Screen + Control Center + CarPlay)

    private func refreshNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let cur = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        let track = nowPlaying ?? TrackMeta(artist: "", title: "")
        var info: [String: Any] = [
            // Lock screen reads: title (song) → artist → album (station).
            MPMediaItemPropertyTitle: track.title.isEmpty ? cur.name : track.title,
            MPMediaItemPropertyArtist: track.artist.isEmpty ? "Nightride FM" : track.artist,
            MPMediaItemPropertyAlbumTitle: "\(cur.name) · Nightride FM",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let art = artwork(for: cur) {
            info[MPMediaItemPropertyArtwork] = art
        }
        if let start = startedAt {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Date().timeIntervalSince(start)
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    // MARK: – Artwork

    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    /// The shared per-station cover (generated in /assets). Drives the
    /// lock-screen / Control Center / CarPlay art slot.
    private func artwork(for station: Station) -> MPMediaItemArtwork? {
        if let cached = artworkCache[station.id] { return cached }
        guard let image = Artwork.image(for: station) else { return nil }
        let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkCache[station.id] = art
        return art
    }
}
