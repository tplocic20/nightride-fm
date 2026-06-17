package dev.plocic.nightride

import android.content.Context

/**
 * Which of nightride.fm's two transports to pull audio over. HLS (adaptive
 * AAC, ~96–320k variants) rides quality drops gracefully; the fixed-bitrate
 * MP3 stream is the failover target when an HLS stream fails to load (see
 * PlaybackService.recoverFromHlsFailure). Both ride plain 443.
 *
 * NOTE: HLS is intentionally disabled at runtime for now — native/Apple HLS
 * proved unstable on some clients/networks while the plain MP3 stream is solid
 * (incl. in-car). The picker UI is removed and MP3 is the only transport
 * callers actually get (see Station.toMediaItem, which pins MP3). This enum,
 * Station.streamUrl's HLS branch, and the HLS→MP3 failover are kept intact but
 * unreachable so HLS can be re-enabled later without a rebuild of this logic.
 *
 * The persistence helpers below are likewise dormant: callers no longer read or
 * write the saved choice, so any StreamSource left in SharedPreferences from an
 * older build is ignored.
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
