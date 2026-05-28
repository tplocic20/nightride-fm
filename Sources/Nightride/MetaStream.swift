import Foundation

/// Consumes the Nightride FM Server-Sent-Events feed at
/// `https://nightride.fm/meta` and reports `[stationID: "Artist - Title"]`
/// dictionaries whenever the metadata changes.
final class MetaStream {
    typealias Handler = ([String: String]) -> Void

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
        }
        guard let data = payload.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }

        var updates: [String: String] = [:]
        for e in entries {
            updates[e.station] = "\(e.artist) - \(e.title)"
        }
        if !updates.isEmpty {
            handler(updates)
        }
    }
}
