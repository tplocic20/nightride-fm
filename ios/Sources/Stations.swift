import Foundation

struct Station: Identifiable, Hashable {
    let id: String         // stream key, e.g. "nightride"
    let name: String
    let streamURL: URL
}

extension Station {
    fileprivate static func nightride(_ id: String, _ name: String) -> Station {
        Station(
            id: id,
            name: name,
            streamURL: URL(string: "https://stream.nightride.fm/\(id).mp3")!
        )
    }
}

enum Stations {
    // Order mirrors nightride.fm's main player (Nightride → Chillsynth →
    // Datawave → Spacesynth → Darksynth → Horrorsynth → EBSM). Rekt and
    // Rektory live under Rekt.Network rather than the main picker on the
    // site, but their streams still work — we keep them at the bottom as
    // extras.
    static let all: [Station] = [
        .nightride("nightride",   "Nightride FM"),
        .nightride("chillsynth",  "Chillsynth"),
        .nightride("datawave",    "Datawave"),
        .nightride("spacesynth",  "Spacesynth"),
        .nightride("darksynth",   "Darksynth"),
        .nightride("horrorsynth", "Horrorsynth"),
        .nightride("ebsm",        "EBSM"),
        .nightride("rekt",        "Rekt"),
        .nightride("rektory",     "Rektory"),
    ]
}
