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
    static let all: [Station] = [
        .nightride("nightride",   "Nightride FM"),
        .nightride("darksynth",   "Darksynth"),
        .nightride("chillsynth",  "Chillsynth"),
        .nightride("datawave",    "Datawave"),
        .nightride("ebsm",        "EBSM"),
        .nightride("horrorsynth", "Horrorsynth"),
        .nightride("spacesynth",  "Spacesynth"),
        .nightride("rekt",        "Rekt"),
        .nightride("rektory",     "Rektory"),
    ]
}
