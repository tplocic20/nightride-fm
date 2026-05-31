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
