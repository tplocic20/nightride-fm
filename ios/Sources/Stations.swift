import SwiftUI

struct Station: Identifiable, Hashable {
    let id: String         // stream key, e.g. "nightride"
    let name: String
    let streamURL: URL
    let accentHex: UInt32  // per-station accent (mirrors /assets generator)

    /// Contrast-checked neon accent, derived from nightride.fm's own per-station
    /// gradient colours. Used to tint the UI just enough to tell stations apart.
    var accent: Color { Color(hex: accentHex) }
}

extension Station {
    fileprivate static func nightride(_ id: String, _ name: String, _ accent: UInt32) -> Station {
        Station(
            id: id,
            name: name,
            streamURL: URL(string: "https://stream.nightride.fm/\(id).mp3")!,
            accentHex: accent
        )
    }
}

enum Stations {
    // Order mirrors nightride.fm's main player (Nightride → Chillsynth →
    // Datawave → Spacesynth → Darksynth → Horrorsynth → EBSM). Rekt and
    // Rektory live under Rekt.Network rather than the main picker on the
    // site, but their streams still work — we keep them at the bottom as
    // extras. Accents mirror assets/generate.mjs (keep both in sync).
    static let all: [Station] = [
        .nightride("nightride",   "Nightride FM", 0xCC55FF),
        .nightride("chillsynth",  "Chillsynth",   0xFFCBA6),
        .nightride("datawave",    "Datawave",     0xFFE696),
        .nightride("spacesynth",  "Spacesynth",   0x3DD6A8),
        .nightride("darksynth",   "Darksynth",    0xFD3D9D),
        .nightride("horrorsynth", "Horrorsynth",  0x5BFF6A),
        .nightride("ebsm",        "EBSM",         0xE6E6E6),
        .nightride("rekt",        "Rekt",         0xFF4D4D),
        .nightride("rektory",     "Rektory",      0xC9A86A),
    ]
}
