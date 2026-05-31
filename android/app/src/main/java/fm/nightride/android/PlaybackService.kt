package fm.nightride.android

import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.LibraryResult
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
            override fun onMediaItemTransition(item: MediaItem?, reason: Int) = applyMeta()
        })

        session = MediaLibrarySession.Builder(this, player, LibrarySessionCallback()).build()

        // SSE: the connection stays open between events, so disable the read
        // timeout for this client.
        val client = OkHttpClient.Builder()
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()
        meta = MetaStream(client, scope) { updates ->
            main.post {
                latestMeta = latestMeta + updates
                applyMeta()
            }
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
     * Re-stamp the currently playing item with the freshest "Artist - Title"
     * for its station. [Player.replaceMediaItem] with the same URI updates the
     * metadata in place without restarting the stream.
     */
    private fun applyMeta() {
        val item = player.currentMediaItem ?: return
        val station = Stations.byId(item.mediaId) ?: return
        val raw = latestMeta[station.id].orEmpty()
        val split = Titles.split(raw, station)

        val metadata = MediaMetadata.Builder()
            .setTitle(split.track)
            .setArtist(split.artist)
            .setStation(station.name)
            .setSubtitle(raw)  // raw "Artist - Title" for the phone UI to display
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
            val children = ImmutableList.copyOf(Stations.all.map { it.toMediaItem() })
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
                Stations.byId(request.mediaId)?.toMediaItem() ?: request
            }.toMutableList()
            return Futures.immediateFuture(resolved)
        }
    }

    private companion object {
        const val ROOT_ID = "root"
    }
}
