package fm.nightride.android

import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors

/**
 * UI-side handle on playback. The real player lives in [PlaybackService]; this
 * connects to it through a Media3 [MediaController] and mirrors the relevant
 * state into Compose. The intent surface (play / togglePlayPause / next / prev)
 * matches PlayerStore in the macOS and iOS clients.
 */
class PlayerController(private val context: Context) {

    var current by mutableStateOf<Station?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var nowPlaying by mutableStateOf("")  // raw "Artist - Title", may be empty
        private set

    private var controller: MediaController? = null

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) = sync(player)
    }

    /** Bind to the playback service; call from Activity.onStart. */
    fun connect() {
        if (controller != null) return
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            controller = future.get().also {
                it.addListener(listener)
                sync(it)
            }
        }, MoreExecutors.directExecutor())
    }

    /** Release the controller; call from Activity.onStop. Playback continues. */
    fun release() {
        controller?.removeListener(listener)
        controller?.release()
        controller = null
    }

    private fun sync(player: Player) {
        isPlaying = player.isPlaying
        current = Stations.byId(player.currentMediaItem?.mediaId)
        nowPlaying = player.mediaMetadata.subtitle?.toString().orEmpty()
    }

    fun play(station: Station) {
        val c = controller ?: return
        c.setMediaItem(station.toMediaItem())
        c.prepare()
        c.play()
    }

    fun togglePlayPause() {
        val c = controller ?: return
        if (c.isPlaying) {
            c.pause()
        } else {
            // Live streams resume poorly from a stale buffer — re-open instead.
            (current ?: Stations.all.firstOrNull())?.let { play(it) }
        }
    }

    fun next() = step(+1)
    fun prev() = step(-1)

    private fun step(delta: Int) {
        val list = Stations.all
        if (list.isEmpty()) return
        val base = current?.let { cur -> list.indexOfFirst { it.id == cur.id } } ?: -1
        val index = ((base + delta) % list.size + list.size) % list.size
        play(list[index])
    }
}
