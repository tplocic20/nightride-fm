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
    /** All stations stream MP3 from the same host. */
    val streamUrl: String get() = "https://stream.nightride.fm/$id.mp3"
}

/**
 * Playable Media3 item for a station — used both for direct playback from the
 * phone UI and as the browse-tree entry surfaced to Android Auto. The media id
 * is the stream key so we can always resolve a request back to its [Station];
 * the per-station cover rides along so the notification and Auto show art.
 */
fun Station.toMediaItem(context: Context): MediaItem =
    MediaItem.Builder()
        .setMediaId(id)
        .setUri(streamUrl)
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
