import UIKit

/// Loads the shared per-station cover art (generated in /assets, bundled via
/// project.yml). Cached after first load. Used both for the in-app cover and
/// the Now Playing artwork.
enum Artwork {
    private static var cache: [String: UIImage] = [:]

    static func image(for station: Station) -> UIImage? {
        if let cached = cache[station.id] { return cached }
        guard let url = Bundle.main.url(forResource: station.id, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[station.id] = image
        return image
    }
}
