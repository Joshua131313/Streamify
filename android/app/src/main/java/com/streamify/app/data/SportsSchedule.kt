package com.streamify.app.data

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject
import java.io.IOException
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlin.coroutines.coroutineContext

// An all-leagues view otherwise launches fifteen requests simultaneously.
private val scheduleRequests = Semaphore(3)

internal suspend fun loadSportsSchedule(
    league: League,
    date: LocalDate,
    backend: String = "",
    retryDelayMillis: Long = 600,
    fetch: suspend (String) -> String = { request(it) }
): Schedule {
    suspend fun get(url: String): JSONObject {
        try {
            return scheduleRequests.withPermit { JSONObject(fetch(url)) }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            coroutineContext.ensureActive()
            // A single retry handles transient denials/network failures without a request loop.
            val transient = if (error is HttpStatusException) error.status == 403 || error.status in 500..599
                else error is IOException
            if (!transient) throw error
            delay(retryDelayMillis)
            return scheduleRequests.withPermit { JSONObject(fetch(url)) }
        }
    }
    val base = backend.trim().trimEnd('/')
    var backendGames: List<Game> = emptyList()
    if (base.isNotEmpty()) {
        require(httpsUrl(base)) { "The sports API address must use HTTPS. Update it in Settings." }
        try {
            val json = get("$base/api/schedule?league=${league.name.lowercase()}&start=$date&end=$date")
            val games = json.getJSONArray("games").objects().map { parseBackendGame(it, league) }
            backendGames = games.filter { it.localDate == date }
            if ((json.optJSONArray("failedDates")?.length() ?: 0) == 0) {
                return Schedule(games.filter { it.localDate == date }.distinctBy { it.key }.sortedBy { it.date }, false)
            }
        } catch (error: Exception) { if (error is CancellationException) throw error
            coroutineContext.ensureActive() }
        // The public schedule source needs no movie API key or backend credentials.
    }
    val results = coroutineScope {
        (-1L..1L).map { offset -> async {
            try {
                val day = date.plusDays(offset).format(DateTimeFormatter.BASIC_ISO_DATE)
                val json = get("https://site.api.espn.com/apis/site/v2/sports/${league.sport}/${league.name.lowercase()}/scoreboard?dates=$day&limit=100")
                Result.success(json.getJSONArray("events").objects().mapNotNull { parseESPN(it, league) })
            } catch (error: Exception) {
                if (error is CancellationException) throw error
            coroutineContext.ensureActive()
                Result.failure<List<Game>>(error)
            }
        } }.awaitAll()
    }
    if (results.all { it.isFailure } && backendGames.isEmpty()) {
        val throttled = results.any { (it.exceptionOrNull() as? HttpStatusException)?.status == 429 }
        throw IOException(if (throttled) "Scores are being requested too quickly. Wait a moment, then retry."
            else "The sports provider couldn’t load this date. Please try again shortly.")
    }
    return Schedule((results.flatMap { it.getOrDefault(emptyList()) } + backendGames).filter { it.localDate == date }
        .distinctBy { it.key }.sortedBy { it.date }, results.any { it.isFailure })
}
