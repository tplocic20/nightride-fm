import AppKit
import Foundation

/// Quick "I love this song" actions: jump to a search for the current track in
/// a streaming service, or copy "Artist — Title". These are SEARCH links only
/// (no auth / SDK / library-write) — they land the user on a results page in
/// the app or web, where they can save it themselves.
enum MusicService: String, CaseIterable, Identifiable {
    case spotify, appleMusic, youtube
    var id: String { rawValue }

    /// Short, lowercase label to match the mono/CRT chrome.
    var label: String {
        switch self {
        case .spotify:    return "spotify"
        case .appleMusic: return "apple"
        case .youtube:    return "youtube"
        }
    }

    func url(query: String) -> URL? {
        // Encode to alphanumerics only so spaces → %20 and any &, ?, / in a
        // title can't break the URL (works for both path- and query-style).
        let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        switch self {
        // https (not the spotify: scheme) so it behaves like the others: a
        // Universal Link opens the installed app on the search, and falls back
        // to web when the app isn't present.
        case .spotify:    return URL(string: "https://open.spotify.com/search/\(q)")
        // The /us/ locale avoids music.apple.com's no-locale → /us/ redirect,
        // which was rewriting our %20 spaces into literal "+" in the search box.
        case .appleMusic: return URL(string: "https://music.apple.com/us/search?term=\(q)")
        case .youtube:    return URL(string: "https://www.youtube.com/results?search_query=\(q)")
        }
    }
}

enum MusicSearch {
    /// "Artist Title" for searching, with parenthetical/bracketed noise such as
    /// "(Album Version)" or "[Remastered]" stripped — it rarely helps a match.
    static func query(for track: TrackMeta) -> String {
        let title = track.title.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        return [track.artist, title]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func open(_ service: MusicService, for track: TrackMeta) {
        guard let url = service.url(query: query(for: track)) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copies the human "Artist — Title" form (not the search-stripped query).
    static func copy(_ track: TrackMeta) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(track.display, forType: .string)
    }
}
