import AVFoundation
import Combine
import MediaPlayer
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
                self?.isPlaying = rate != 0
                self?.refreshNowPlaying()
            }
        }
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
        let item = AVPlayerItem(url: station.streamURL)
        // Pull the live now-playing line from the stream's in-band ICY metadata so
        // it tracks the buffered audio (see `icyReader` / `handleICYTitle`).
        let icyOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        icyOutput.setDelegate(icyReader, queue: .main)
        item.add(icyOutput)
        player.replaceCurrentItem(with: item)
        player.play()
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
        player.pause()
        refreshNowPlaying()
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
