package dev.plocic.nightride

import android.content.Context
import android.net.Uri

/**
 * Maps a station to its bundled cover (res/drawable-nodpi/<id>.png). Drives the
 * in-app cover (Compose) and the notification / Android Auto artwork — the
 * latter via an `android.resource://` URI that Media3's bitmap loader resolves.
 */
object Artwork {
    private val drawables: Map<String, Int> = mapOf(
        "nightride" to R.drawable.nightride,
        "chillsynth" to R.drawable.chillsynth,
        "datawave" to R.drawable.datawave,
        "spacesynth" to R.drawable.spacesynth,
        "darksynth" to R.drawable.darksynth,
        "horrorsynth" to R.drawable.horrorsynth,
        "ebsm" to R.drawable.ebsm,
        "rekt" to R.drawable.rekt,
        "rektory" to R.drawable.rektory,
    )

    /** Drawable resource id for a station's cover, or null if missing. */
    fun resId(station: Station): Int? = drawables[station.id]

    /** android.resource:// URI for Media3 (notification + Android Auto load it). */
    fun uri(context: Context, station: Station): Uri? =
        resId(station)?.let { id -> Uri.parse("android.resource://${context.packageName}/$id") }
}
