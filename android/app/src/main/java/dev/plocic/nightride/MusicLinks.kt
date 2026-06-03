package dev.plocic.nightride

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Quick "I love this song" actions, mirroring ios/MusicLinks.swift: jump to the
 * current track in a streaming service, or copy "Artist — Title". Search /
 * catalog-lookup links only — no auth, SDK, or library writes.
 */
enum class MusicService(val label: String) {
    SPOTIFY("spotify"),
    APPLE("apple"),
    YOUTUBE("youtube");

    fun searchUrl(query: String): String {
        val q = Uri.encode(query)
        return when (this) {
            SPOTIFY -> "https://open.spotify.com/search/$q"
            APPLE -> "https://music.apple.com/us/search?term=$q"
            YOUTUBE -> "https://www.youtube.com/results?search_query=$q"
        }
    }
}

object MusicSearch {

    /**
     * "Artist Title" for searching, with parenthetical/bracketed noise such as
     * "(Album Version)" or "[Remastered]" stripped. [raw] is the feed's
     * "Artist - Title".
     */
    fun query(raw: String): String {
        val (artist, title) = splitRaw(raw)
        val cleanTitle = title.replace(Regex("""\s*[(\[][^)\]]*[)\]]"""), "")
        return listOf(artist, cleanTitle)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
    }

    fun open(context: Context, scope: CoroutineScope, service: MusicService, raw: String) {
        val q = query(raw)
        if (q.isEmpty()) return
        when (service) {
            MusicService.APPLE -> scope.launch {
                // The Music app ignores a `…/search?term=` link (lands on Browse),
                // so resolve the track to a real catalog URL via the iTunes Search
                // API and open THAT; fall back to the web search on no match.
                val url = appleMusicUrl(q) ?: service.searchUrl(q)
                withContext(Dispatchers.Main) { openUrl(context, url) }
            }
            else -> openUrl(context, service.searchUrl(q))
        }
    }

    /** Copies the human "Artist — Title" form (not the search-stripped query). */
    fun copy(context: Context, raw: String) {
        val (artist, title) = splitRaw(raw)
        val display = if (artist.isNotEmpty() && title.isNotEmpty()) "$artist — $title" else raw.trim()
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("track", display))
    }

    // ── internals ───────────────────────────────────────────────────────────

    private fun splitRaw(raw: String): Pair<String, String> {
        val trimmed = raw.trim()
        val dash = trimmed.indexOf(" - ")
        return if (dash >= 0) {
            trimmed.substring(0, dash).trim() to trimmed.substring(dash + 3).trim()
        } else {
            "" to trimmed
        }
    }

    private fun openUrl(context: Context, url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    @Serializable
    private data class SearchResponse(val results: List<Item> = emptyList()) {
        @Serializable
        data class Item(val trackViewUrl: String? = null)
    }

    private val client by lazy {
        OkHttpClient.Builder().callTimeout(8, TimeUnit.SECONDS).build()
    }
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Best-matching song's Apple Music deep link from the public iTunes Search
     * API, or null on no match / any network or decode error.
     */
    private suspend fun appleMusicUrl(query: String): String? = withContext(Dispatchers.IO) {
        try {
            val url = "https://itunes.apple.com/search?term=${Uri.encode(query)}&entity=song&limit=1"
            client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                val body = response.body?.string() ?: return@withContext null
                json.decodeFromString<SearchResponse>(body).results.firstOrNull()?.trackViewUrl
            }
        } catch (e: Exception) {
            null
        }
    }
}
