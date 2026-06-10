import SwiftUI

/// Which of nightride.fm's two transports to pull audio over. HLS (adaptive
/// AAC, ~96–320k variants) rides quality drops gracefully and is the default;
/// the fixed-bitrate MP3 stream stays as the fallback for networks that block
/// HLS's non-standard port (8443) — MP3 is on plain 443.
enum StreamSource: String, CaseIterable, Identifiable {
    case hls, mp3

    var id: String { rawValue }
    var label: String { rawValue }

    private static let storageKey = "streamSource"

    static var saved: StreamSource {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(StreamSource.init(rawValue:)) ?? .hls
    }

    func save() { UserDefaults.standard.set(rawValue, forKey: Self.storageKey) }
}

struct Station: Identifiable, Hashable {
    let id: String         // stream key, e.g. "nightride"
    let name: String
    let accentHex: UInt32  // per-station accent (mirrors /assets generator)

    /// Contrast-checked neon accent, derived from nightride.fm's own per-station
    /// gradient colours. Used to tint the UI just enough to tell stations apart.
    var accent: Color { Color(hex: accentHex) }

    /// All stations stream from the same host on both transports.
    func streamURL(for source: StreamSource) -> URL {
        switch source {
        case .hls: URL(string: "https://stream.nightride.fm:8443/\(id)/\(id).m3u8")!
        case .mp3: URL(string: "https://stream.nightride.fm/\(id).mp3")!
        }
    }
}

extension Station {
    fileprivate static func nightride(_ id: String, _ name: String, _ accent: UInt32) -> Station {
        Station(id: id, name: name, accentHex: accent)
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

extension Stations {
    /// Rekt.Network streams live outside nightride.fm's main picker.
    private static let rektIDs: Set<String> = ["rekt", "rektory"]

    /// Header-titled groups for sectioned list UIs (e.g. CarPlay), mirroring the
    /// site's split between the main stations and the Rekt.Network extras.
    static let grouped: [(title: String, stations: [Station])] = [
        ("Stations",     all.filter { !rektIDs.contains($0.id) }),
        ("Rekt.Network", all.filter {  rektIDs.contains($0.id) }),
    ]
}
