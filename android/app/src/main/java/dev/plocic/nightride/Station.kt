package dev.plocic.nightride

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

/** Brand string used wherever there's no live artist info yet. */
const val BRAND = "Nightride FM"

data class Station(
    val id: String,      // stream key, e.g. "nightride"
    val name: String,
    val accentHex: Int,  // per-station neon accent (RGB), mirrors ios/Stations.swift
) {
    /** All stations stream from the same host on both transports. */
    fun streamUrl(source: StreamSource): String = when (source) {
        StreamSource.HLS -> "https://stream.nightride.fm/hls/$id/$id.m3u8"
        StreamSource.MP3 -> "https://stream.nightride.fm/$id.mp3"
    }
}

/**
 * Playable Media3 item for a station — used both for direct playback from the
 * phone UI and as the browse-tree entry surfaced to Android Auto. The media id
 * is the stream key so we can always resolve a request back to its [Station];
 * the per-station cover rides along so the notification and Auto show art.
 */
// HLS is intentionally disabled at runtime for now (native/Apple HLS proved
// unstable on some clients/networks; the fixed-bitrate MP3 stream is solid,
// incl. in-car). MP3 is the only transport callers get, the picker UI is gone,
// and we ignore any StreamSource saved in SharedPreferences. The HLS code path
// (StreamSource.HLS, Station.streamUrl's HLS branch, the HLS→MP3 failover in
// PlaybackService) is kept intact but unreachable for an easy future re-enable.
fun Station.toMediaItem(
    context: Context,
    source: StreamSource = StreamSource.MP3,
): MediaItem =
    MediaItem.Builder()
        .setMediaId(id)
        .setUri(streamUrl(source))
        .setMediaMetadata(defaultMetadata(context))
        .build()

private fun Station.defaultMetadata(context: Context): MediaMetadata =
    MediaMetadata.Builder()
        .setTitle(name)
        .setArtist(BRAND)
        .setStation(name)
        .setArtworkUri(Artwork.uri(context, this))
        .setIsBrowsable(false)
        .setIsPlayable(true)
        .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
        .build()
