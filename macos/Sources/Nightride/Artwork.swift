import AppKit

/// Loads the shared per-station cover art (generated in /assets, copied into
/// the .app's Resources by build.sh). Cached after first load. Used for the
/// popover thumbnail and the Now Playing artwork.
enum Artwork {
    private static var cache: [String: NSImage] = [:]

    static func image(for station: Station) -> NSImage? {
        if let cached = cache[station.id] { return cached }
        guard let url = Bundle.main.url(forResource: station.id, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[station.id] = image
        return image
    }
}
