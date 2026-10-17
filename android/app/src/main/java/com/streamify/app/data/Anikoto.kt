package com.streamify.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.jsoup.Jsoup
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

data class AnimeIdentity(val malId: Int, val names: List<String>)
data class AnimeSource(val url: String, val referer: String)
internal data class AnikotoEpisode(val number: Int, val malId: Int, val servers: String)

/** Uses the same public episode/server responses as Anikoto's watch page. */
object Anikoto {
    private const val base = "https://anikoto.cz"
    private data class Match(val url: String, val id: String, val malId: Int)
    private val matches = ConcurrentHashMap<Int, Match>()

    private suspend fun get(path: String): String = withContext(Dispatchers.IO) {
        require(path.startsWith("/") && !path.startsWith("//"))
        val connection = URL(base + path).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 8000; connection.readTimeout = 10000
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android) Streamify/1.0")
            connection.setRequestProperty("Referer", "$base/")
            connection.setRequestProperty("X-Requested-With", "XMLHttpRequest")
            check(connection.responseCode in 200..299) { "Anikoto could not respond (${connection.responseCode}). Please retry." }
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally { connection.disconnect() }
    }
    private suspend fun response(path: String): JSONObject = JSONObject(get(path)).also {
        check(it.optInt("status") == 200) { "Anikoto could not find this episode or source." }
    }
    internal fun searchLinks(html: String): List<String> = Jsoup.parse(html, base).select("a.item[href]")
        .map { it.absUrl("href") }.filter(::watchUrl).distinct().take(6)
    internal fun watchUrl(url: String): Boolean = runCatching {
        val uri = URI(url)
        uri.scheme == "https" && uri.host == "anikoto.cz" && uri.userInfo == null && uri.port == -1 &&
            Regex("/watch/[a-zA-Z0-9-]+").matches(uri.path)
    }.getOrDefault(false)
    internal fun episodes(html: String): List<AnikotoEpisode> = Jsoup.parse(html).select("a[data-num][data-ids]").mapNotNull {
        val number = it.attr("data-num").toIntOrNull() ?: return@mapNotNull null
        AnikotoEpisode(number, it.attr("data-mal").toIntOrNull() ?: 0, it.attr("data-ids"))
    }
    internal fun sourceToken(html: String, language: String, server: String): String? {
        require(language in listOf("sub", "dub"))
        return Jsoup.parse(html).select(".type[data-type=$language] li[data-link-id]")
            .firstOrNull { it.attr("data-sv-id") == server }?.attr("data-link-id")?.takeIf { it.isNotBlank() }
    }
    private suspend fun episodeList(id: String) = episodes(response("/ajax/episode/list/${encode(id)}").text("result"))
    private suspend fun match(media: Media): Match {
        matches[media.id]?.let { return it }
        val identity = AnimeCatalog.identity(media.id)
        check(identity.malId > 0) { "This anime has no verified Anikoto title mapping yet." }
        val visited = mutableSetOf<String>()
        for (name in (listOf(media.title) + identity.names).filter { it.isNotBlank() }.distinct().take(2)) {
            val html = response("/ajax/anime/search?keyword=${encode(name)}").getJSONObject("result").text("html")
            for (url in searchLinks(html).filter { visited.add(it) }) {
                val page = Jsoup.parse(get(URI(url).rawPath))
                val id = page.selectFirst(".watch-wrap[data-id]")?.attr("data-id") ?: continue
                if (!id.all(Char::isDigit) || id.isBlank()) continue
                // The catalog's MAL ID must match the site's episode metadata. No fuzzy title fallback.
                if (episodeList(id).any { it.malId == identity.malId }) {
                    return Match(url, id, identity.malId).also { matches[media.id] = it }
                }
            }
        }
        error("No matching Anikoto release was found for this title. Try another anime.")
    }
    suspend fun resolve(media: Media, number: Int, providerId: String): AnimeSource {
        require(media.type == MediaType.ANIME && number > 0)
        val provider = Regex("anime-anikoto-([a-zA-Z0-9]+)-(sub|dub)").matchEntire(providerId)
            ?: error("Choose an Anikoto source.")
        val (server, language) = provider.destructured
        val title = match(media)
        val episode = episodeList(title.id).firstOrNull { it.number == number && it.malId == title.malId }
            ?: error("Episode $number is not available on Anikoto yet.")
        val sources = response("/ajax/server/list?servers=${encode(episode.servers)}").text("result")
        val token = sourceToken(sources, language, server)
            ?: error("This ${language.uppercase()} source is unavailable for episode $number. Choose another source.")
        val url = response("/ajax/server?get=${encode(token)}").getJSONObject("result").text("url")
        check(httpsUrl(url)) { "Anikoto returned an unsupported player address." }
        return AnimeSource(url + (if (url.contains("?")) "&" else "?") + "autostart=true", "${title.url}/ep-$number")
    }
}
