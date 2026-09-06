import AVFoundation
import Foundation

/// One station's currently-playing track, as reported by the /meta feed.
struct TrackMeta: Equatable {
    let artist: String
    let title: String

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
    /// Parse the in-band ICY `StreamTitle` ("Artist - Title") into a TrackMeta,
    /// splitting on the first " - ".
    init(icyStreamTitle raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sep = trimmed.range(of: " - ") {
            self.init(
                artist: String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces),
                title: String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            )
        } else {
            self.init(artist: "", title: trimmed)
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

