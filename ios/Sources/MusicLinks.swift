import Foundation
import UIKit

/// Quick "I love this song" actions: jump to a search for the current track in
/// a streaming service, or copy "Artist — Title". These are SEARCH links only
/// (no auth / SDK / library-write) — they land the user on a results page in
/// the app or web, where they can save it themselves.
enum MusicService: String, CaseIterable, Identifiable {
    case spotify, appleMusic, youtube
    var id: String { rawValue }

    var label: String {
        switch self {
        case .spotify:    return "spotify"
        case .appleMusic: return "apple"
        case .youtube:    return "youtube"
        }
    }

    func url(query: String) -> URL? {
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
        switch service {
        case .appleMusic:
            // The Music *app* ignores a `…/search?term=` universal link — it just
            // opens to Browse (only the website runs the search). So resolve the
            // track to a real catalog URL via the public iTunes Search API and
            // open THAT, which lands on the exact song. Fall back to the web
            // search link only when nothing matches.
            openAppleMusic(query: query(for: track))
        case .spotify, .youtube:
            guard let url = service.url(query: query(for: track)) else { return }
            UIApplication.shared.open(url)
        }
    }

    /// Copies the human "Artist — Title" form (not the search-stripped query).
    static func copy(_ track: TrackMeta) {
        UIPasteboard.general.string = track.display
    }

    // MARK: – Apple Music catalog resolution

    private static func openAppleMusic(query: String) {
        Task {
            let target = await appleMusicURL(for: query)
                ?? MusicService.appleMusic.url(query: query)
            guard let url = target else { return }
            await MainActor.run { UIApplication.shared.open(url) }
        }
    }

    /// Best-matching song's Apple Music deep link (`trackViewUrl`, e.g.
    /// `https://music.apple.com/us/album/…?i=…`) — which, unlike the search URL,
    /// DOES open the song in the Music app. `nil` on no match or any
    /// network/decoding error, so the caller can fall back.
    private static func appleMusicURL(for query: String) async -> URL? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")
        comps?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps?.url else { return nil }

        struct Response: Decodable {
            let results: [Item]
            struct Item: Decodable { let trackViewUrl: String? }
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            let link = try JSONDecoder().decode(Response.self, from: data).results.first?.trackViewUrl
            return link.flatMap { URL(string: $0) }
        } catch {
            return nil
        }
    }
}
