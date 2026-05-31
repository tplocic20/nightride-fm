package fm.nightride.android

object Stations {
    // Order mirrors nightride.fm's main player (Nightride → Chillsynth →
    // Datawave → Spacesynth → Darksynth → Horrorsynth → EBSM). Rekt and
    // Rektory live under Rekt.Network rather than the main picker on the
    // site, but their streams still work — we keep them at the bottom as
    // extras. Kept in lockstep with macos/ and ios/ Stations.swift.
    val all: List<Station> = listOf(
        Station("nightride", "Nightride FM"),
        Station("chillsynth", "Chillsynth"),
        Station("datawave", "Datawave"),
        Station("spacesynth", "Spacesynth"),
        Station("darksynth", "Darksynth"),
        Station("horrorsynth", "Horrorsynth"),
        Station("ebsm", "EBSM"),
        Station("rekt", "Rekt"),
        Station("rektory", "Rektory"),
    )

    fun byId(id: String?): Station? = id?.let { key -> all.firstOrNull { it.id == key } }
}
