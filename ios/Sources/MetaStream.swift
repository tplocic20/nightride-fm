import AVFoundation
import Foundation

/// One station's currently-playing track, as reported by the /meta feed.
struct TrackMeta: Equatable {
    let artist: String
    let title: String
    let album: String

    /// "Artist — Title", degrading gracefully if either half is missing.
    var display: String {
        switch (artist.isEmpty, title.isEmpty) {
        case (false, false): return "\(artist) — \(title)"
        case (true, false): return title
        case (false, true): return artist
        case (true, true): return ""
        }
    }

    var isEmpty: Bool { artist.isEmpty && title.isEmpty }
}

extension TrackMeta {
    /// Parse an Icecast/SHOUTcast in-band `StreamTitle` ("Artist - Title") into a
    /// TrackMeta. The MP3 stream carries this inline, synced to the buffered audio,
    /// so it drives the live station's now-playing line in place of the (live-edge)
    /// `/meta` feed. Splits on the first " - "; album is unknown in-band. Declared
    /// in an extension so the memberwise initializer stays synthesized.
    init(icyStreamTitle raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sep = trimmed.range(of: " - ") {
            self.init(
                artist: String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces),
                title: String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces),
                album: ""
            )
        } else {
            self.init(artist: "", title: trimmed, album: "")
        }
    }
}

/// Forwards AVPlayer's ICY timed metadata (the in-band `StreamTitle`) off the
/// player to a handler. AVPlayer parses Icecast metadata automatically; we just
/// pull the `StreamTitle` items out of each group as they're rendered, so they
/// arrive in step with the audio the listener actually hears.
final class ICYMetadataReader: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let onTitle: (String) -> Void

    init(_ onTitle: @escaping (String) -> Void) { self.onTitle = onTitle }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let titles = groups.flatMap(\.items).filter { $0.identifier == .icyMetadataStreamTitle }
        for item in titles {
            // Pushed items are already loaded, so this resolves immediately.
            Task {
                if let title = try? await item.load(.stringValue), !title.isEmpty {
                    onTitle(title)
                }
            }
        }
    }
}

/// Consumes Nightride FM's Server-Sent-Events feed at
/// `https://nightride.fm/meta` and reports `[stationID: TrackMeta]` whenever
/// the metadata changes. The feed pushes a snapshot of every station on
/// connect, then incremental updates as tracks change.
final class MetaStream {
    typealias Handler = ([String: TrackMeta]) -> Void

    private let handler: Handler
    private var task: Task<Void, Never>?

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        task?.cancel()
        task = Task.detached(priority: .utility) { [weak self] in
            await self?.loop()
        }
    }

    func stop() { task?.cancel() }

    private func loop() async {
        var backoff: UInt64 = 1_000_000_000  // 1 s
        while !Task.isCancelled {
            do {
                var req = URLRequest(url: URL(string: "https://nightride.fm/meta")!)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.setValue("no-cache",          forHTTPHeaderField: "Cache-Control")
                req.timeoutInterval = TimeInterval.infinity

                let (bytes, _) = try await URLSession.shared.bytes(for: req)
                backoff = 1_000_000_000

                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst("data: ".count))
                    if payload.isEmpty || payload == "keepalive" { continue }
                    parse(payload)
                }
            } catch is CancellationError {
                return
            } catch {
                try? await Task.sleep(nanoseconds: backoff)
                backoff = min(backoff * 2, 30_000_000_000)
            }
        }
    }

    private func parse(_ payload: String) {
        struct Entry: Decodable {
            let station: String
            let title: String
            let artist: String
            let album: String?
        }
        guard let data = payload.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }

        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

        var updates: [String: TrackMeta] = [:]
        for e in entries {
            updates[e.station] = TrackMeta(
                artist: clean(e.artist),
                title: clean(e.title),
                album: clean(e.album ?? "")
            )
        }
        if !updates.isEmpty {
            handler(updates)
        }
    }
}
