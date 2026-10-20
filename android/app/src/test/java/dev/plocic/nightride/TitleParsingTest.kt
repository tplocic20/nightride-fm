package dev.plocic.nightride

import org.junit.Assert.assertEquals
import org.junit.Test

class TitleParsingTest {
    private val st = Station("nightride", "Nightride FM", 0xCC55FF)

    // raw, expected track, expected artist line, expected search query
    private data class Case(val raw: String, val track: String, val artist: String, val query: String)

    private val cases = listOf(
        Case("Artist - Title", "Title", "Artist — Nightride FM", "Artist Title"),
        Case("Just A Title", "Just A Title", "Nightride FM", "Just A Title"),
        Case("A - B - C", "B - C", "A — Nightride FM", "A B - C"),
        Case("", "Nightride FM", BRAND, ""),
        Case("   ", "Nightride FM", BRAND, ""),
        Case("Jean-Michel - Song", "Song", "Jean-Michel — Nightride FM", "Jean-Michel Song"),
        Case(
            "Artist - Song (Remastered) [Album Version]",
            "Song (Remastered) [Album Version]", "Artist — Nightride FM", "Artist Song",
        ),
    )

    @Test
    fun splitAndQuery() {
        for (c in cases) {
            assertEquals("split track: '${c.raw}'", c.track, Titles.split(c.raw, st).track)
            assertEquals("split artist: '${c.raw}'", c.artist, Titles.split(c.raw, st).artist)
            assertEquals("query: '${c.raw}'", c.query, MusicSearch.query(c.raw))
        }
    }
}
