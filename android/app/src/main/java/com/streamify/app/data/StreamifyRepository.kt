package com.streamify.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlin.coroutines.coroutineContext

class StreamifyRepository(private val store: LocalStore) {
    suspend fun media(id: Int, type: MediaType): Media = if (type == MediaType.ANIME) AnimeCatalog.details(id).media else Media.parse(tmdb("${type.path}/$id"), type)
        ?: error("Title details unavailable.")
    suspend fun catalog(path: String, type: MediaType? = null, page: Int = 1, query: String = "", params: Map<String, String> = emptyMap()): MediaPage {
        val json = tmdb(path, params + mapOf("page" to page.toString(), "query" to query))
        return MediaPage(json.optJSONArray("results").objects().mapNotNull { Media.parse(it, type) },
            json.optInt("page", 1), json.optInt("total_pages", 1).coerceAtMost(500))
    }

    suspend fun details(media: Media): Details {
        if (media.type == MediaType.ANIME) return AnimeCatalog.details(media.id)
        val json = tmdb("${media.type.path}/${media.id}", mapOf("append_to_response" to "credits,recommendations,videos"))
        val runtime = json.optInt("runtime").takeIf { it > 0 }?.let { "$it min" } ?: ""
        return Details(Media.parse(json, media.type) ?: media,
            json.optJSONArray("genres").objects().joinToString(" · ") { it.text("name") }, runtime,
            json.optJSONArray("seasons").objects().filter { it.optInt("season_number") > 0 }.map {
                Season(it.optInt("season_number"), it.text("name"), it.optInt("episode_count"))
            }, json.optJSONObject("credits")?.optJSONArray("cast").objects().take(15).map {
                Credit(it.text("name"), it.text("character"), it.text("profile_path"), it.optInt("id"))
            }, json.optJSONObject("recommendations")?.optJSONArray("results").objects().mapNotNull { Media.parse(it, media.type) },
            json.optJSONObject("videos")?.optJSONArray("results").objects()
                .firstOrNull { it.text("site") == "YouTube" && it.text("type") == "Trailer" }
                ?.text("key")?.takeIf { Regex("[A-Za-z0-9_-]+").matches(it) }?.let { "https://www.youtube.com/watch?v=$it" })
    }

    suspend fun episodes(id: Int, season: Int, type: MediaType = MediaType.TV): List<Episode> = if (type == MediaType.ANIME) AnimeCatalog.episodes(id) else tmdb("tv/$id/season/$season")
        .optJSONArray("episodes").objects().map {
            Episode(it.optInt("episode_number"), it.text("name"), it.text("overview"), it.text("still_path"), it.text("air_date"), it.optInt("runtime", 0))
        }

    suspend fun genres(type: MediaType): List<Genre> = if (type == MediaType.ANIME) emptyList() else tmdb("genre/${type.path}/list").optJSONArray("genres").objects().map { Genre(it.optInt("id"), it.text("name")) }

    suspend fun collection(id: Int): CollectionDetails {
        val json = tmdb("collection/$id")
        return CollectionDetails(json.text("overview"), json.optJSONArray("parts").objects().mapNotNull { Media.parse(it, MediaType.MOVIE) }
            .sortedBy { it.date.ifBlank { "9999" } })
    }

    suspend fun person(id: Int): Person {
        val json = tmdb("person/$id", mapOf("append_to_response" to "combined_credits"))
        return Person(json.text("name"), json.text("profile_path"), json.text("biography"), json.text("birthday"), json.text("place_of_birth"),
            json.optJSONObject("combined_credits")?.optJSONArray("cast").objects().mapNotNull { Media.parse(it) }.distinctBy { it.key }.sortedByDescending { it.rating })
    }

    private suspend fun tmdb(path: String, params: Map<String, String> = emptyMap()): JSONObject {
        val key = store.tmdbKey.trim()
        check(key.isNotBlank()) { "Add your TMDB API key in Settings to browse movies and series." }
        val query = (params.filterValues { it.isNotBlank() } + mapOf("language" to "en-US", "include_adult" to "false") +
            if (key.startsWith("eyJ")) emptyMap() else mapOf("api_key" to key))
            .entries.joinToString("&") { "${encode(it.key)}=${encode(it.value)}" }
        return JSONObject(request("https://api.themoviedb.org/3/$path?$query", if (key.startsWith("eyJ")) key else null))
    }

    suspend fun schedule(league: League, date: LocalDate): Schedule =
        loadSportsSchedule(league, date, store.apiBase)

    suspend fun streams(game: Game): List<Stream> {
        val matches = JSONArray(request("https://streamed.pk/api/matches/all")).objects().map {
            val teams = it.optJSONObject("teams")
            StreamMatch(it.text("title"), it.text("category"), it.optLong("date"),
                teams?.optJSONObject("home")?.text("name").orEmpty(), teams?.optJSONObject("away")?.text("name").orEmpty(),
                it.optJSONArray("sources").objects().map { source -> StreamSource(source.text("source"), source.text("id")) })
        }
        val match = findMatch(matches, game) ?: return emptyList()
        val results = coroutineScope {
            match.sources.take(8).map { source -> async {
                try {
                    Result.success(JSONArray(request("https://streamed.pk/api/stream/${encode(source.source)}/${encode(source.id)}"))
                        .objects().mapNotNull {
                            val url = it.text("embedUrl")
                            if (!httpsUrl(url)) null else Stream("${source.source} ${it.optInt("streamNo")} · ${it.text("language")}${if (it.optBoolean("hd")) " · HD" else ""}", url)
                        })
                } catch (error: Exception) { coroutineContext.ensureActive(); Result.failure<List<Stream>>(error) }
            } }.awaitAll()
        }
        if (results.isNotEmpty() && results.all { it.isFailure }) error("Stream sources are unavailable. Try again shortly.")
        return results.flatMap { it.getOrDefault(emptyList()) }.distinctBy { it.url }
    }
}

internal suspend fun request(url: String, bearer: String? = null): String = withContext(Dispatchers.IO) {
    require(httpsUrl(url)) { "Only HTTPS connections are supported." }
    val connection = URL(url).openConnection() as HttpURLConnection
    try {
        connection.connectTimeout = 12_000
        connection.readTimeout = 15_000
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", "Streamify-Android/1.0")
        bearer?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
        val status = connection.responseCode
        if (status !in 200..299) throw HttpStatusException(status,
            when (status) { 401, 403 -> "Access was denied. Check your API key or try another source."
                429 -> "Too many requests. Please wait a moment and retry."
                else -> "The service is unavailable (HTTP $status). Please retry." })
        connection.inputStream.bufferedReader().use { it.readText() }.also { coroutineContext.ensureActive() }
    } finally { connection.disconnect() }
}

internal fun parseBackendGame(json: JSONObject, league: League): Game {
    fun team(key: String): Team {
        val t = json.getJSONObject(key)
        return Team(t.text("id"), t.text("name"), t.text("abbreviation"), t.text("logo"), t.text("score"), t.text("record"), t.text("nickname"))
    }
    val broadcasts = json.optJSONArray("broadcasts")
    return Game(json.text("id"), league, json.text("date"), json.text("state"), json.text("status"),
        team("homeTeam"), team("awayTeam"), json.optJSONObject("venue")?.text("name").orEmpty(),
        broadcasts?.let { (0 until it.length()).joinToString(" · ") { i -> it.optString(i) } }.orEmpty(), json.text("gameLink"), if (league == League.MLB) parseBaseball(json.optJSONObject("live")) else null)
}

internal fun parseESPN(json: JSONObject, league: League): Game? {
    val comp = json.optJSONArray("competitions")?.optJSONObject(0) ?: return null
    val competitors = comp.optJSONArray("competitors").objects()
    fun team(side: String): Team? {
        val entry = competitors.firstOrNull { it.text("homeAway") == side } ?: return null
        val t = entry.optJSONObject("team") ?: return null
        return Team(t.text("id"), t.text("displayName"), t.text("abbreviation"), t.text("logo").ifBlank { t.optJSONArray("logos")?.optJSONObject(0)?.text("href").orEmpty() }, entry.optJSONObject("score")?.text("displayValue") ?: entry.text("score"),
            entry.optJSONArray("records")?.optJSONObject(0)?.text("summary").orEmpty(), t.text("name"))
    }
    val status = comp.optJSONObject("status") ?: json.optJSONObject("status")
    val type = status?.optJSONObject("type")
    return Game(json.text("id"), league, json.text("date").ifBlank { comp.text("date") }, type?.text("state") ?: "pre",
        type?.text("shortDetail").orEmpty().ifBlank { type?.text("description").orEmpty() }, team("home") ?: return null,
        team("away") ?: return null, comp.optJSONObject("venue")?.text("fullName").orEmpty(),
        comp.optJSONArray("broadcasts").objects().mapNotNull { it.optJSONArray("names")?.optString(0) }.joinToString(" · "),
        json.optJSONArray("links")?.optJSONObject(0)?.text("href").orEmpty(), if (league == League.MLB) parseBaseball(comp.optJSONObject("situation"), espn = true) else null)
}

internal class HttpStatusException(val status: Int, message: String) : java.io.IOException(message)
