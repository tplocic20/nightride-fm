import XCTest
@testable import Nightride

final class TrackMetaTests: XCTestCase {
    func testIcyStreamTitleSplit() {
        // raw, expected artist, expected title
        let cases: [(String, String, String)] = [
            ("Artist - Title", "Artist", "Title"),
            ("Just A Title", "", "Just A Title"),
            ("A - B - C", "A", "B - C"),
            ("", "", ""),
            ("   ", "", ""),
            ("Jean-Michel - Song", "Jean-Michel", "Song"),
            ("Artist - Song (Remastered) [Album Version]", "Artist", "Song (Remastered) [Album Version]"),
        ]
        for (raw, artist, title) in cases {
            let m = TrackMeta(icyStreamTitle: raw)
            XCTAssertEqual(m.artist, artist, "artist for '\(raw)'")
            XCTAssertEqual(m.title, title, "title for '\(raw)'")
        }
    }
}
