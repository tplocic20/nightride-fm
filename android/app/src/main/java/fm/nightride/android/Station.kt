package fm.nightride.android

import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

/** Brand string used wherever there's no live artist info yet. */
const val BRAND = "Nightride FM"

data class Station(
    val id: String,    // stream key, e.g. "nightride"
    val name: String,
) {
    /** All stations stream MP3 from the same host. */
    val streamUrl: String get() = "https://stream.nightride.fm/$id.mp3"
}

/**
 * Playable Media3 item for a station — used both for direct playback from the
 * phone UI and as the browse-tree entry surfaced to Android Auto. The media id
 * is the stream key so we can always resolve a request back to its [Station].
 */
fun Station.toMediaItem(metadata: MediaMetadata = defaultMetadata()): MediaItem =
    MediaItem.Builder()
        .setMediaId(id)
        .setUri(streamUrl)
        .setMediaMetadata(metadata)
        .build()

private fun Station.defaultMetadata(): MediaMetadata =
    MediaMetadata.Builder()
        .setTitle(name)
        .setArtist(BRAND)
        .setStation(name)
        .setIsBrowsable(false)
        .setIsPlayable(true)
        .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
        .build()
