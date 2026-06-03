package dev.plocic.nightride

object Stations {
    // Order mirrors nightride.fm's main player (Nightride → Chillsynth →
    // Datawave → Spacesynth → Darksynth → Horrorsynth → EBSM). Rekt and
    // Rektory live under Rekt.Network rather than the main picker on the
    // site, but their streams still work — we keep them at the bottom as
    // extras. Kept in lockstep with macos/ and ios/ Stations.swift, including
    // the per-station accent colours.
    val all: List<Station> = listOf(
        Station("nightride", "Nightride FM", 0xCC55FF),
        Station("chillsynth", "Chillsynth", 0xFFCBA6),
        Station("datawave", "Datawave", 0xFFE696),
        Station("spacesynth", "Spacesynth", 0x3DD6A8),
        Station("darksynth", "Darksynth", 0xFD3D9D),
        Station("horrorsynth", "Horrorsynth", 0x5BFF6A),
        Station("ebsm", "EBSM", 0xE6E6E6),
        Station("rekt", "Rekt", 0xFF4D4D),
        Station("rektory", "Rektory", 0xC9A86A),
    )

    fun byId(id: String?): Station? = id?.let { key -> all.firstOrNull { it.id == key } }
}
