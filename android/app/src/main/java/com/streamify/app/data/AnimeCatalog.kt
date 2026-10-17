package com.streamify.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** AniList IDs occupy their own namespace; never pass these to TMDB providers. */
val animeServers = listOf("sub", "dub").flatMap { language ->
    listOf("323" to "HD-1", "e54" to "Vidstream-2", "1a7" to "Vidstream-1").map { (id, name) ->
        MediaServer("anime-anikoto-$id-$language", "$name · ${language.uppercase()}", "", "")
    }
}

object AnimeCatalog {
    private const val fields = "id idMal title { english romaji } description(asHtml: false) coverImage { large } bannerImage averageScore startDate { year month day } episodes status nextAiringEpisode { episode } duration genres trailer { id site }"
    private suspend fun query(query: String, variables: JSONObject): JSONObject = withContext(Dispatchers.IO) {
        val connection = URL("https://graphql.anilist.co").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 12000; connection.readTimeout = 20000
            connection.setRequestProperty("Content-Type", "application/json")
            connection.doOutput = true
            connection.outputStream.use { it.write(JSONObject().put("query", query).put("variables", variables).toString().toByteArray(Charsets.UTF_8)) }
            check(connection.responseCode in 200..299) { "Anime catalog unavailable (${connection.responseCode}). Please try again shortly." }
            val result = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            check(!result.has("errors")) { "Anime catalog could not complete this request." }
            result.getJSONObject("data")
        } finally { connection.disconnect() }
    }
    internal fun media(json: JSONObject): Media = Media(json.getInt("id"), MediaType.ANIME,
        json.optJSONObject("title")?.text("english").orEmpty().ifBlank { json.optJSONObject("title")?.text("romaji").orEmpty() },
        json.text("description").replace(Regex("<[^>]+>"), ""), json.optJSONObject("coverImage")?.text("large").orEmpty(),
        json.text("bannerImage"), json.optDouble("averageScore", 0.0) / 10,
        json.optJSONObject("startDate")?.optInt("year")?.takeIf { it > 0 }?.toString().orEmpty())
    internal fun episodeCount(json: JSONObject): Int {
        if (json.text("status") == "NOT_YET_RELEASED") return 0
        val next = json.optJSONObject("nextAiringEpisode")?.optInt("episode") ?: 0
        return (if (next > 0) next - 1 else json.optInt("episodes")).coerceIn(0, 3000)
    }
    suspend fun catalog(page: Int, search: String, topRated: Boolean, genre: String? = null): MediaPage {
        val sort = if (topRated) "SCORE_DESC" else "POPULARITY_DESC"
        val data = query("query(\$page:Int,\$search:String,\$genre:String){Page(page:\$page,perPage:24){pageInfo{hasNextPage} media(type:ANIME,isAdult:false,search:\$search,genre:\$genre,sort:$sort){$fields}}}",
            JSONObject().put("genre", genre ?: JSONObject.NULL).put("page", page).put("search", search.takeIf { it.isNotBlank() } ?: JSONObject.NULL)).getJSONObject("Page")
        return MediaPage(data.optJSONArray("media").objects().map(::media), page, if (data.getJSONObject("pageInfo").optBoolean("hasNextPage")) page + 1 else page)
    }
    private suspend fun title(id: Int) = query("query(\$id:Int){Media(id:\$id,type:ANIME,isAdult:false){$fields}}", JSONObject().put("id", id)).getJSONObject("Media")
    suspend fun identity(id: Int): AnimeIdentity {
        val json = title(id)
        val names = json.getJSONObject("title")
        return AnimeIdentity(json.optInt("idMal"), listOf(names.text("english"), names.text("romaji")))
    }
    suspend fun details(id: Int): Details {
        val json = title(id)
        val genres = json.optJSONArray("genres")
        val trailer = json.optJSONObject("trailer")
        return Details(media(json), (0 until (genres?.length() ?: 0)).joinToString(" · ") { genres!!.getString(it) },
            json.optInt("duration").takeIf { it > 0 }?.let { "$it min" }.orEmpty(),
            listOf(Season(1, "Episodes", episodeCount(json))), emptyList(), emptyList(),
            trailer?.takeIf { it.text("site") == "youtube" }?.text("id")?.takeIf { Regex("[A-Za-z0-9_-]+").matches(it) }?.let { "https://www.youtube.com/watch?v=$it" })
    }
    suspend fun episodes(id: Int): List<Episode> {
        val json = title(id)
        return (1..episodeCount(json)).map { Episode(it, "Episode $it", "", "", "", json.optInt("duration")) }
    }
}
