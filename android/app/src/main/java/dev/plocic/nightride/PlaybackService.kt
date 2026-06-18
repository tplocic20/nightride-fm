package dev.plocic.nightride

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.extractor.metadata.icy.IcyInfo
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaConstants
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * The single home for playback. A Media3 [MediaLibraryService] gives us, from
 * one place: background audio, the media-style notification, lock-screen /
 * Bluetooth / headset transport controls, and the browsable library that
 * Android Auto projects. There is no Auto-specific UI code — Auto is just
 * another controller browsing [Stations] and asking us to play one, the same
 * way CarPlay reuses the iOS Now Playing center.
 *
 * The /meta SSE feed runs here too; when the current station's track changes
 * we re-stamp the playing item's metadata via [Player.replaceMediaItem], which
 * refreshes the notification and Auto without interrupting the live stream.
 */
class PlaybackService : MediaLibraryService() {

    private lateinit var player: ExoPlayer
    private var session: MediaLibrarySession? = null
    private lateinit var meta: MetaStream

    private val scope = CoroutineScope(SupervisorJob())
    private val main = Handler(Looper.getMainLooper())
    private var latestMeta: Map<String, String> = emptyMap()

    override fun onCreate() {
        super.onCreate()

        player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                /* handleAudioFocus = */ true,
            )
            .setHandleAudioBecomingNoisy(true)  // pause when headphones unplug
            .setWakeMode(C.WAKE_MODE_NETWORK)    // keep streaming with screen off
            .build()

        player.addListener(object : Player.Listener {
            override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
                // A station switch shows its cached (live-edge) track immediately;
                // the in-band ICY title then corrects it to the buffered audio.
                applyMeta()
            }
            override fun onMetadata(metadata: Metadata) = applyIcyMetadata(metadata)
            override fun onPlayerError(error: PlaybackException) = recoverFromHlsFailure()
        })

        session = MediaLibrarySession.Builder(this, player, LibrarySessionCallback()).build()

        // SSE: the connection stays open between events, so disable the read
        // timeout for this client.
        val client = OkHttpClient.Builder()
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()
        // The /meta feed is the live edge (instant), so it only warms the cache
        // that feeds the Android Auto browse tree and the instant track shown on a
        // station switch. The playing station's live line comes from the audio's
        // in-band ICY metadata (see onMetadata / applyIcyMetadata), not from here.
        meta = MetaStream(client, scope) { updates ->
            main.post { latestMeta = latestMeta + updates }
        }
        meta.start()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo) = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app away while paused (or with nothing queued) should
        // tear the service down rather than leave a dead notification.
        if (!player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        meta.stop()
        scope.cancel()
        session?.run {
            player.release()
            release()
        }
        session = null
        super.onDestroy()
    }

    /**
     * Auto-fall back HLS→MP3 when a stream fails to load. nightride.fm has moved
     * the HLS path before; the fixed-bitrate MP3 endpoint is the stable safety
     * net. Fires once per stream — if the live item is already MP3 the error
     * surfaces normally (no retry loop), and recovery clears ExoPlayer's error
     * state via prepare().
     */
    private fun recoverFromHlsFailure() {
        val item = player.currentMediaItem ?: return
        val onHls = item.localConfiguration?.uri?.toString()?.contains("/hls/") == true
        if (!onHls) return
        val station = Stations.byId(item.mediaId) ?: return
        player.setMediaItem(station.toMediaItem(this, StreamSource.MP3))
        player.prepare()
        player.play()
    }

    /**
     * Drive the playing station's live line from the MP3 stream's in-band ICY
     * `StreamTitle`. ExoPlayer emits it through [Player.Listener.onMetadata] as it
     * renders the stream, so it lands in step with the buffered audio the listener
     * actually hears — no fixed offset to guess at. Icecast re-sends the same title
     * roughly every metadata interval; [applyMeta]'s equality guard absorbs the
     * repeats.
     */
    private fun applyIcyMetadata(metadata: Metadata) {
        for (i in 0 until metadata.length()) {
            val entry = metadata.get(i)
            if (entry is IcyInfo) {
                entry.title?.takeIf { it.isNotBlank() }?.let { applyMeta(it) }
            }
        }
    }

    /**
     * Re-stamp the currently playing item with the freshest "Artist - Title" for
     * its station. [rawOverride] carries the audio-synced ICY title; without it we
     * fall back to the cached `/meta` value (used on a station switch).
     * [Player.replaceMediaItem] with the same URI updates the metadata in place
     * without restarting the stream.
     */
    private fun applyMeta(rawOverride: String? = null) {
        val item = player.currentMediaItem ?: return
        val station = Stations.byId(item.mediaId) ?: return
        val raw = rawOverride ?: latestMeta[station.id].orEmpty()
        val split = Titles.split(raw, station)

        val metadata = MediaMetadata.Builder()
            .setTitle(split.track)
            .setArtist(split.artist)
            .setStation(station.name)
            .setSubtitle(raw)  // raw "Artist - Title" for the phone UI to display
            .setArtworkUri(Artwork.uri(this, station))
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
            .build()

        if (item.mediaMetadata == metadata) return  // unchanged — avoid churn
        player.replaceMediaItem(
            player.currentMediaItemIndex,
            item.buildUpon().setMediaMetadata(metadata).build(),
        )
    }

    /**
     * A browse-tree entry for Android Auto: the station's cover art, its current
     * live track as the subtitle, and a group-title hint so Auto sections the
     * grid into "Stations" / "Rekt.Network".
     */
    private fun browseItem(station: Station): MediaItem {
        val base = station.toMediaItem(this)
        val raw = latestMeta[station.id].orEmpty()
        val meta = base.mediaMetadata.buildUpon()
            .apply { if (raw.isNotEmpty()) setSubtitle(raw) }
            .setExtras(Bundle().apply {
                putString(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_GROUP_TITLE, groupTitle(station))
            })
            .build()
        return base.buildUpon().setMediaMetadata(meta).build()
    }

    private fun groupTitle(station: Station): String =
        if (station.id in REKT_IDS) "Rekt.Network" else "Stations"

    /** Station name / id substring match for Auto voice search. */
    private fun searchMatches(query: String): List<Station> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return Stations.all
        return Stations.all.filter { it.name.lowercase().contains(q) || it.id.contains(q) }
    }

    private inner class LibrarySessionCallback : MediaLibrarySession.Callback {

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val root = MediaItem.Builder()
                .setMediaId(ROOT_ID)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(BRAND)
                        .setIsBrowsable(true)
                        .setIsPlayable(false)
                        .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_RADIO_STATIONS)
                        // Render the station list as a grid of covers in Auto.
                        .setExtras(Bundle().apply {
                            putInt(
                                MediaConstants.EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                                MediaConstants.EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM,
                            )
                            putInt(
                                MediaConstants.EXTRAS_KEY_CONTENT_STYLE_PLAYABLE,
                                MediaConstants.EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM,
                            )
                        })
                        .build()
                )
                .build()
            return Futures.immediateFuture(LibraryResult.ofItem(root, params))
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val children = ImmutableList.copyOf(Stations.all.map { browseItem(it) })
            return Futures.immediateFuture(LibraryResult.ofItemList(children, params))
        }

        /**
         * Controllers (Android Auto, restored sessions) hand us items by media
         * id only — re-attach the stream URI before they reach the player.
         */
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> {
            val resolved = mediaItems.map { request ->
                Stations.byId(request.mediaId)?.toMediaItem(this@PlaybackService) ?: request
            }.toMutableList()
            return Futures.immediateFuture(resolved)
        }

        // Voice search ("play Datawave on Nightride"): report the match count,
        // then serve the matching stations.
        override fun onSearch(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<Void>> {
            session.notifySearchResultChanged(browser, query, searchMatches(query).size, params)
            return Futures.immediateFuture(LibraryResult.ofVoid(params))
        }

        override fun onGetSearchResult(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val results = ImmutableList.copyOf(searchMatches(query).map { browseItem(it) })
            return Futures.immediateFuture(LibraryResult.ofItemList(results, params))
        }
    }

    private companion object {
        const val ROOT_ID = "root"
        val REKT_IDS = setOf("rekt", "rektory")
    }
}
