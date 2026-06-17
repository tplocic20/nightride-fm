import AVFoundation
import AppKit
import Combine
import MediaPlayer
import SwiftUI

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlaying: TrackMeta?

    /// HLS by default; MP3 as the fallback transport (see StreamSource).
    /// Flipping it mid-play re-opens the live station on the new source.
    @Published var source: StreamSource = .saved {
        didSet {
            guard source != oldValue else { return }
            source.save()
            if let cur = current, isPlaying { play(cur) }
        }
    }

    private let player = AVPlayer()
    private var startedAt: Date?
    /// Watches the live item's load status so we can fall back HLS→MP3 (see `open`).
    private var itemObserver: NSKeyValueObservation?
    /// Fires if HLS hasn't started playing within a few seconds, so we fail over
    /// to MP3 ourselves instead of waiting for AVPlayer's long internal timeout.
    private var startupWatchdog: Timer?
    private var meta: MetaStream?
    /// Latest known track per station id — kept warm so selecting a station
    /// shows its current track instantly, instead of waiting for the next change.
    private var latestMeta: [String: TrackMeta] = [:]
    private var rateObserver: NSKeyValueObservation?

    init() {
        // Start at the live edge with minimal pre-buffering — the same way the
        // website's web player does. The default (true) makes AVPlayer fill a
        // buffer before emitting any audio, which on a live HLS feed can stall
        // the start for tens of seconds; for live radio we'd rather start now.
        player.automaticallyWaitsToMinimizeStalling = false

        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let rate = change.newValue ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                withAnimation(Theme.transition) { self.isPlaying = rate != 0 }
                if rate != 0 { self.startupWatchdog?.invalidate() }  // started → no failover
                self.refreshNowPlaying()
            }
        }
        // Connect to the metadata feed at launch so every station's current
        // track is cached before the user ever hits play.
        startMeta()
    }

    deinit {
        rateObserver?.invalidate()
        itemObserver?.invalidate()
        startupWatchdog?.invalidate()
    }

    // MARK: – User intent

    func play(_ station: Station) {
        // Flip the selection OUTSIDE the animation so the station list's `/`→`>`
        // glyph and colour change instantly (no cross-dissolve). Only the track
        // change is animated, so the header growth — and the list sliding with it —
        // still runs on the shared curve, and the selected/previous rows glide in
        // step with the others instead of snapping.
        current = station
        withAnimation(Theme.transition) {
            nowPlaying = latestMeta[station.id]   // reflect cached track immediately
        }
        startedAt = Date()

        open(station, on: source)
        refreshNowPlaying()
    }

    /// Open a station on a specific transport, watching the new item for a load
    /// failure so we can fall back HLS→MP3 automatically — nightride.fm has moved
    /// the HLS path before, and the fixed-bitrate MP3 endpoint is the stable
    /// safety net. The fallback fires once per open: if MP3 also fails, or the
    /// user has already switched stations, the error just surfaces.
    private func open(_ station: Station, on transport: StreamSource) {
        startupWatchdog?.invalidate()
        let item = AVPlayerItem(url: station.streamURL(for: transport))
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.failOver(station, from: transport) }
        }
        player.replaceCurrentItem(with: item)
        player.play()

        // AVPlayer can sit buffering a stalled HLS connection for ~30–60s before
        // it declares the item .failed — far too long to make the user wait. If
        // HLS hasn't actually started within a few seconds, fail over to the
        // instant-start MP3 stream ourselves.
        if transport == .hls {
            startupWatchdog = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.player.timeControlStatus != .playing else { return }
                    self.failOver(station, from: .hls)
                }
            }
        }
    }

    /// Single HLS→MP3 fallback: only if the failed/stalled transport was HLS and
    /// the user hasn't moved on. If MP3 also fails, the error just surfaces.
    private func failOver(_ station: Station, from transport: StreamSource) {
        guard transport == .hls, current?.id == station.id else { return }
        startupWatchdog?.invalidate()
        open(station, on: .mp3)
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
        startupWatchdog?.invalidate()  // a deliberate pause must not trigger failover
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

    private func handleMeta(_ updates: [String: TrackMeta]) {
        latestMeta.merge(updates) { _, new in new }
        // Only refresh the UI / widgets when the change touches the live station.
        guard let cur = current, let track = updates[cur.id] else { return }
        withAnimation(Theme.transition) { nowPlaying = track }
        refreshNowPlaying()
    }

    // MARK: – Now Playing widget (Control Center / media keys / lock screen)

    private func refreshNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let cur = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        let track = nowPlaying ?? .init(artist: "", title: "", album: "")
        var info: [String: Any] = [
            // Now Playing reads: title (song) → artist → album (station).
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
    /// Control Center / Now Playing art slot.
    private func artwork(for station: Station) -> MPMediaItemArtwork? {
        if let cached = artworkCache[station.id] { return cached }
        guard let image = Artwork.image(for: station) else { return nil }
        let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkCache[station.id] = art
        return art
    }
}
