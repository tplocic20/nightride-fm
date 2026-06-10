package dev.plocic.nightride

import android.content.Context

/**
 * Which of nightride.fm's two transports to pull audio over. HLS (adaptive
 * AAC, ~96–320k variants) rides quality drops gracefully and is the default;
 * the fixed-bitrate MP3 stream stays as the fallback for networks that block
 * HLS's non-standard port (8443) — MP3 is on plain 443.
 *
 * Persisted in SharedPreferences so the choice survives restarts and is
 * readable from both the UI process and [PlaybackService] (same process),
 * including when Android Auto starts playback with no phone UI around.
 */
enum class StreamSource(val label: String) {
    HLS("hls"),
    MP3("mp3");

    companion object {
        private const val PREFS = "settings"
        private const val KEY = "streamSource"

        fun load(context: Context): StreamSource =
            when (prefs(context).getString(KEY, null)) {
                MP3.label -> MP3
                else -> HLS
            }

        fun save(context: Context, source: StreamSource) {
            prefs(context).edit().putString(KEY, source.label).apply()
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }
}
