package dev.plocic.nightride

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import kotlin.coroutines.coroutineContext

/**
 * Consumes Nightride FM's Server-Sent-Events feed at
 * `https://nightride.fm/meta` and reports `{ stationID -> "Artist - Title" }`
 * maps whenever the metadata changes. Reconnects with exponential backoff,
 * mirroring MetaStream.swift in the Apple clients.
 *
 * The [client] should be built with no read timeout — SSE connections stay
 * open indefinitely between events.
 */
class MetaStream(
    private val client: OkHttpClient,
    private val scope: CoroutineScope,
    private val onUpdate: (Map<String, String>) -> Unit,
) {
    private var job: Job? = null

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch(Dispatchers.IO) { loop() }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private suspend fun loop() {
        var backoffMs = 1_000L
        while (coroutineContext.isActive) {
            try {
                val request = Request.Builder()
                    .url("https://nightride.fm/meta")
                    .header("Accept", "text/event-stream")
                    .header("Cache-Control", "no-cache")
                    .build()

                client.newCall(request).execute().use { response ->
                    val source = response.body?.source() ?: return@use
                    backoffMs = 1_000L  // connected — reset backoff

                    while (coroutineContext.isActive) {
                        val line = source.readUtf8Line() ?: break  // server closed
                        if (!line.startsWith("data:")) continue
                        val payload = line.removePrefix("data:").trim()
                        if (payload.isEmpty() || payload == "keepalive") continue
                        parse(payload)
                    }
                }
            } catch (e: Exception) {
                if (!coroutineContext.isActive) return  // cancellation
                // fall through to backoff + retry
            }

            delay(backoffMs)
            backoffMs = (backoffMs * 2).coerceAtMost(30_000L)
        }
    }

    @Serializable
    private data class Entry(val station: String, val title: String, val artist: String)

    private fun parse(payload: String) {
        val entries = try {
            json.decodeFromString<List<Entry>>(payload)
        } catch (e: Exception) {
            return
        }
        val updates = entries.associate { it.station to "${it.artist} - ${it.title}" }
        if (updates.isNotEmpty()) onUpdate(updates)
    }

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
