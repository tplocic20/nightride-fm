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

    /// Pinned to MP3. The HLS transport (StreamSource.hls, `streamURL(for:)`,
    /// the HLS→MP3 failover in `open`) is kept in the codebase for the future
    /// but is intentionally unreachable at runtime: Apple's native HLS handling
    /// of the live feed was unstable, while the fixed-bitrate MP3 stream is
    /// solid (incl. in-car), so we ship MP3-only with no transport picker and
    /// ignore any saved StreamSource. Restore `.saved`/`@Published` + the picker
    /// to re-enable HLS.
    let source: StreamSource = .mp3

    private let player = AVPlayer()
    private var startedAt: Date?
    /// Watches the live item's load status so we can fall back HLS→MP3 (see `open`).
    private var itemObserver: NSKeyValueObservation?
    /// Reads the live station's now-playing line from the MP3 stream's in-band ICY
    /// `StreamTitle` (see `open`). Because it rides the same buffer as the audio it
    /// lands in step with what the listener hears — no fixed offset to guess at.
    private lazy var icyReader = ICYMetadataReader { [weak self] title in
        Task { @MainActor [weak self] in self?.handleICYTitle(title) }
    }
    private var rateObserver: NSKeyValueObservation?

    init() {
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let rate = change.newValue ?? 0
            Task { @MainActor [weak self] in
                withAnimation(Theme.transition) { self?.isPlaying = rate != 0 }
                self?.refreshNowPlaying()
            }
        }
    }

    deinit {
        rateObserver?.invalidate()
        itemObserver?.invalidate()
    }

    // MARK: – User intent

    func play(_ station: Station) {
        // Flip the selection OUTSIDE the animation so the station list's `/`→`>`
        // glyph and colour change instantly (no cross-dissolve). Only the track
        // change is animated, so the header growth — and the list sliding with it —
        // still runs on the shared curve, and the selected/previous rows glide in
        // step with the others instead of snapping.
        current = station
        // No cached seed here: latestMeta can be hours old after inactivity, and
        // a wrong artist that flips on play is worse than ~1s of blank. The
        // in-band ICY title fills this in as soon as audio is buffered.
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
        let item = AVPlayerItem(url: station.streamURL(for: transport))
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, transport == .hls, self.current?.id == station.id else { return }
                self.open(station, on: .mp3)
            }
        }
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
            // Resuming a live stream from a stale buffer usually drops out.
            // Re-open the URL to get a fresh connection.
            play(cur)
        } else if let first = Stations.all.first {
            play(first)
        }
    }

    func pause() {
        // Drop the displayed track: while inactive it would sit there looking
        // current when it's actually the last song heard (possibly hours old).
        // The brand name shows instead until the next play() streams fresh ICY.
        withAnimation(Theme.transition) { nowPlaying = nil }
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

    /// Apply an in-band ICY `StreamTitle` from the playing stream. It rides the same
    /// buffer as the audio, so the displayed track flips exactly when the listener
    /// hears the song change — no offset to tune.
    private func handleICYTitle(_ raw: String) {
        guard current != nil else { return }
        let track = TrackMeta(icyStreamTitle: raw)
        guard !track.isEmpty else { return }
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
