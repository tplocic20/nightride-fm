package dev.plocic.nightride

/**
 * Splits the raw "Artist - Title" string from the /meta feed into the
 * (track, artist) pair shown on the notification, lock screen and Android Auto.
 * Mirrors PlayerStore.splitTitle in the Apple clients so every platform labels
 * Now Playing identically.
 */
object Titles {
    data class Split(val track: String, val artist: String)

    fun split(raw: String, station: Station): Split {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return Split(station.name, BRAND)

        val dash = trimmed.indexOf(" - ")
        if (dash >= 0) {
            val artist = trimmed.substring(0, dash).trim()
            val track = trimmed.substring(dash + 3).trim()
            return Split(track, "$artist — ${station.name}")
        }
        return Split(trimmed, station.name)
    }
}
