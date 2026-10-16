package com.streamify.app.data

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.Locale

enum class MediaType(val path: String, val label: String) { MOVIE("movie", "Movie"), TV("tv", "Series") }

data class Media(
    val id: Int, val type: MediaType, val title: String, val overview: String = "",
    val poster: String = "", val backdrop: String = "", val rating: Double = 0.0, val date: String = "", val genreIds: List<Int> = emptyList()
) {
    val key get() = "${type.path}:$id"
    val year get() = date.take(4)
    fun image(wide: Boolean = false) = (if (wide) backdrop.ifBlank { poster } else poster)
        .takeIf { it.startsWith("/") }?.let { "https://image.tmdb.org/t/p/${if (wide) "w780" else "w342"}$it" }
    fun json() = JSONObject().put("id", id).put("media_type", type.path).put("title", title)
        .put("overview", overview).put("poster_path", poster).put("backdrop_path", backdrop)
        .put("vote_average", rating).put("release_date", date).put("genre_ids", JSONArray(genreIds))

    companion object {
        fun parse(json: JSONObject, type: MediaType? = null): Media? {
            val kind = type ?: when (json.text("media_type")) {
                "movie" -> MediaType.MOVIE
                "tv" -> MediaType.TV
                else -> return null
            }
            if (json.optInt("id") <= 0) return null
            return Media(json.optInt("id"), kind, json.text("title").ifBlank { json.text("name") },
                json.text("overview"), json.text("poster_path"), json.text("backdrop_path"),
                json.optDouble("vote_average", 0.0), json.text("release_date").ifBlank { json.text("first_air_date") },
                json.optJSONArray("genre_ids")?.let { a -> (0 until a.length()).map { a.optInt(it) }.filter { it > 0 } }
                    ?: json.optJSONArray("genres").objects().map { it.optInt("id") }.filter { it > 0 })
        }
    }
}

data class MediaPage(val items: List<Media>, val page: Int, val pages: Int)
data class Season(val number: Int, val name: String, val count: Int)
data class Episode(val number: Int, val title: String, val overview: String, val still: String, val date: String, val runtime: Int = 0)
data class Credit(val name: String, val character: String, val image: String, val id: Int = 0)
data class Genre(val id: Int, val name: String)
data class Collection(val id: Int, val name: String, val backdrop: String, val genres: List<Int>, val featured: Boolean)
data class CollectionDetails(val overview: String, val movies: List<Media>)
data class Person(val name: String, val image: String, val biography: String, val birthday: String, val birthplace: String, val credits: List<Media>)
data class Provider(val id: Int, val name: String)
val catalogProviders = listOf(Provider(8, "Netflix"), Provider(9, "Prime"), Provider(15, "Hulu"), Provider(337, "Disney+"), Provider(350, "Apple TV"), Provider(531, "Paramount+"))
data class Details(val media: Media, val genres: String, val runtime: String, val seasons: List<Season>,
                   val cast: List<Credit>, val related: List<Media>, val trailer: String?)
data class History(val media: Media, val season: Int = 1, val episode: Int = 1, val watchedAt: Long = System.currentTimeMillis(), val positionSeconds: Double = 0.0, val durationSeconds: Double = 0.0) {
    val progress get() = if (durationSeconds > 0) (positionSeconds / durationSeconds).coerceIn(0.0, 1.0).toFloat() else 0f
    val completed get() = durationSeconds > 0 && progress >= .95f
    val resumable get() = positionSeconds >= 5 && durationSeconds > 0 && !completed
}

enum class League(val sport: String, val category: String) {
    NFL("football", "american-football"), NBA("basketball", "basketball"),
    WNBA("basketball", "basketball"), NHL("hockey", "hockey"), MLB("baseball", "baseball")
}
data class Team(val id: String, val name: String, val abbreviation: String, val logo: String, val score: String, val record: String, val nickname: String = "") : java.io.Serializable
data class Game(val id: String, val league: League, val date: String, val state: String, val status: String,
                val home: Team, val away: Team, val venue: String, val broadcasts: String, val link: String, val baseball: BaseballLive? = null) : java.io.Serializable {
    val key get() = "${league.name}:$id"
    val live get() = state == "in"
    fun canWatch(now: java.time.Instant = java.time.Instant.now()): Boolean {
        if (live) return true
        val start = parseTimestamp(date) ?: return false
        return state == "pre" && !start.isBefore(now) && !start.isAfter(now.plusSeconds(3600))
    }
    val localDate: LocalDate? get() = parseTimestamp(date)?.atZone(ZoneId.systemDefault())?.toLocalDate()
}
data class Schedule(val games: List<Game>, val partial: Boolean = false)
data class Stream(val label: String, val url: String)
data class StreamSource(val source: String, val id: String)
data class StreamMatch(val title: String, val category: String, val date: Long,
                       val home: String, val away: String, val sources: List<StreamSource>)

fun normalizeTeam(value: String): String = value.lowercase(Locale.ROOT)
    .replace(Regex("\\bst\\.? louis\\b"), "saint louis")
    .replace(Regex("\\bla\\b"), "los angeles").replace(Regex("[^a-z0-9]"), "")

fun findMatch(matches: List<StreamMatch>, game: Game, now: Long = System.currentTimeMillis()): StreamMatch? {
    val home = normalizeTeam(game.home.name)
    val away = normalizeTeam(game.away.name)
    if (home.isBlank() || away.isBlank()) return null
    return matches.filter {
        it.category == game.league.category && it.sources.isNotEmpty() &&
            (it.date == 1L || kotlin.math.abs(it.date - now) <= 18 * 60 * 60 * 1000L) &&
            ((listOf(normalizeTeam(it.home), normalizeTeam(it.away)).containsAll(listOf(home, away))) ||
                (normalizeTeam(it.title).contains(home) && normalizeTeam(it.title).contains(away)))
    }.minByOrNull { kotlin.math.abs(it.date - now) }
}

data class MediaServer(val id: String, val label: String, val movie: String, val tv: String) {
    fun url(media: Media, season: Int = 1, episode: Int = 1): String =
        (if (media.type == MediaType.MOVIE) movie else tv).replace("{id}", media.id.toString())
            .replace("{season}", season.coerceAtLeast(1).toString()).replace("{episode}", episode.coerceAtLeast(1).toString())
}

fun httpsUrl(value: String): Boolean = runCatching {
    val uri = URI(value)
    uri.scheme.equals("https", true) && !uri.host.isNullOrBlank() && uri.userInfo == null
}.getOrDefault(false)
// ESPN frequently omits seconds (23:30Z); ISO_INSTANT parsing alone rejects that form.
fun parseTimestamp(value: String): Instant? = runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
fun JSONObject.text(key: String): String = if (isNull(key)) "" else optString(key, "")
fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

data class BaseballLive(val first: Boolean?, val second: Boolean?, val third: Boolean?, val balls: Int?, val strikes: Int?, val outs: Int?,
    val batter: String, val headshot: String, val summary: String, val pitcher: String = "", val pitcherHeadshot: String = "", val pitcherSummary: String = "") : java.io.Serializable
internal fun parseBaseball(json: JSONObject?, espn: Boolean = false): BaseballLive? {
    if (json == null) return null
    val bases = if (espn) json else json.optJSONObject("bases")
    fun base(name: String): Boolean? = bases?.let { val key = if (espn) "on" + name.replaceFirstChar(Char::uppercaseChar) else name; if (it.has(key) && !it.isNull(key)) it.optBoolean(key) else null }
    fun count(key: String): Int? = if (json.has(key) && !json.isNull(key)) json.optInt(key) else null
    val batter = json.optJSONObject("batter")
    val athlete = batter?.optJSONObject("athlete") ?: batter
    val pitcher = json.optJSONObject("pitcher")
    val pitcherAthlete = pitcher?.optJSONObject("athlete") ?: pitcher
    return BaseballLive(base("first"), base("second"), base("third"), count("balls"), count("strikes"), count("outs"),
        athlete?.text(if (espn) "displayName" else "name").orEmpty().ifBlank { athlete?.text("shortName").orEmpty() },
        athlete?.optJSONObject("headshot")?.text("href") ?: athlete?.text("headshot").orEmpty(), batter?.text("summary").orEmpty(),
        pitcherAthlete?.text(if (espn) "displayName" else "name").orEmpty().ifBlank { pitcherAthlete?.text("shortName").orEmpty() },
        pitcherAthlete?.optJSONObject("headshot")?.text("href") ?: pitcherAthlete?.text("headshot").orEmpty(), pitcher?.text("summary").orEmpty())
}

fun Team.cardName(): String = nickname.ifBlank {
    val parts = name.split(" ")
    if (parts.takeLast(2).joinToString(" ") in setOf("Trail Blazers", "Blue Jays", "Red Sox", "White Sox", "Golden Knights", "Maple Leafs", "Red Wings")) parts.takeLast(2).joinToString(" ") else parts.lastOrNull().orEmpty()
}.ifBlank { abbreviation }
