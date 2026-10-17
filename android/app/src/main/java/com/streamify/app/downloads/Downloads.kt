package com.streamify.app.downloads

import android.content.Context
import android.content.Intent
import com.streamify.app.data.Media
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

data class DownloadItem(val key: String, val id: Int, val title: String, val poster: String = "", val season: Int = 0, val episode: Int = 0,
    val state: String = "queued", val bytes: Long = 0, val total: Long = 0, val url: String = "", val validator: String = "", val error: String = "", val episodeTitle: String = "", val landscape: String = "") {
    val subtitle get() = if (season > 0) "Season $season · Episode $episode" else "Movie"
    fun json() = JSONObject().put("key",key).put("id",id).put("title",title).put("poster",poster).put("season",season).put("episode",episode)
        .put("state",state).put("bytes",bytes).put("total",total).put("url",url).put("validator",validator).put("error",error).put("episodeTitle",episodeTitle).put("landscape",landscape)
    companion object {
        fun parse(j: JSONObject) = DownloadItem(j.getString("key"),j.getInt("id"),j.getString("title"),j.optString("poster"),j.optInt("season"),j.optInt("episode"),j.optString("state"),j.optLong("bytes"),j.optLong("total"),j.optString("url"),j.optString("validator"),j.optString("error"),j.optString("episodeTitle"),j.optString("landscape"))
    }
}

class DownloadStore private constructor(private val context: Context) {
    private val prefs = context.getSharedPreferences("downloads-v1", Context.MODE_PRIVATE)
    private val mutable = MutableStateFlow(runCatching {
        val array = JSONArray(prefs.getString("items","[]"))
        List(array.length()) { DownloadItem.parse(array.getJSONObject(it)) }.map {
            if (it.state in listOf("queued","downloading","resolving")) it.copy(state="paused") else it
        }
    }.getOrDefault(emptyList()))
    val items = mutable.asStateFlow()
    val directory = File(context.filesDir,"downloads").apply { mkdirs() }
    fun file(key: String) = File(directory, "${key.replace(Regex("[^a-zA-Z0-9_-]"),"_")}.mp4")
    fun subtitleFile(key:String)=File(directory,file(key).nameWithoutExtension+".vtt")
    @Synchronized fun get(key: String) = mutable.value.firstOrNull { it.key == key }
    @Synchronized fun update(item: DownloadItem) {
        mutable.value = mutable.value.filterNot { it.key == item.key } + item
        prefs.edit().putString("items",JSONArray(mutable.value.map { it.json() }).toString()).apply()
    }
    @Synchronized fun change(key: String, action: (DownloadItem) -> DownloadItem) { get(key)?.let { update(action(it)) } }
    @Synchronized fun remove(key: String) {
        mutable.value = mutable.value.filterNot { it.key == key }
        prefs.edit().putString("items",JSONArray(mutable.value.map { it.json() }).toString()).apply()
        file(key).delete();subtitleFile(key).delete()
    }
    fun enqueue(media: Media, season: Int = 0, episode: Int = 0, episodeTitle: String = "", thumbnail: String? = null): String {
        val key = "${media.type.path}_${media.id}_${season}_$episode"
        val old = get(key)
        if (old == null) update(DownloadItem(key,media.id,media.title,thumbnail ?: media.image(true).orEmpty(),season,episode,episodeTitle=episodeTitle,landscape=media.backdrop.takeIf {it.isNotBlank()}?.let {media.image(true)}.orEmpty()))
        else if (old.state !in listOf("complete","resolving","downloading")) update(old.copy(state="queued",error=""))
        command(context,"start",key)
        return key
    }
    companion object {
        @Volatile private var instance: DownloadStore? = null
        fun get(context: Context): DownloadStore = instance ?: synchronized(this) { instance ?: DownloadStore(context.applicationContext).also { instance=it } }
        fun command(context: Context, action: String, key: String) {
            val store = get(context)
            try { context.startForegroundService(Intent(context, DownloadService::class.java).setAction(action).putExtra("key",key)) }
            catch (e: Exception) { store.change(key) { it.copy(state="paused",error="Open Downloads to resume: ${e.localizedMessage}") } }
        }
    }
}

/** Enforce exact byte identity before appending, never append a full HTTP 200 response. */
object DownloadRange {
    fun valid(status: Int, range: String?, offset: Long, total: Long): Boolean {
        val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(range.orEmpty()) ?: return false
        return status == 206 && match.groupValues[1].toLong() == offset && match.groupValues[2].toLong() >= offset && match.groupValues[3].toLong() == total
    }
}

/** Native adapter for the MP4 source verified by the Amayembed experiment. */
object DownloadResolver {
    private fun json(url: String, provider: Boolean = false): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout=10000; connection.readTimeout=15000
        if (provider) { connection.setRequestProperty("Origin","https://vidlink.pro");connection.setRequestProperty("Referer","https://vidlink.pro/");connection.setRequestProperty("User-Agent","Mozilla/5.0") }
        try {
            check(connection.responseCode == 200) { "Download source is unavailable. Try again later." }
            return connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
        } finally { connection.disconnect() }
    }
    internal fun preferredQualityUrl(qualities: JSONObject):String =
        listOf("1080","720","480","360").firstNotNullOfOrNull { qualities.optJSONObject(it)?.optString("url")?.takeIf(String::isNotBlank) }
            ?: error("No downloadable video found.")
    private fun stream(item: DownloadItem): JSONObject {
        val token = json("https://enc-dec.app/api/enc-vidlink?text=${item.id}").optString("result")
        check(token.isNotBlank()) { "Could not find a download for this title." }
        val path = if(item.season > 0) "tv/$token/${item.season}/${item.episode}" else "movie/$token"
        return json("https://vidlink.pro/api/b/$path",true).optJSONObject("stream") ?: error("No stream available.")
    }
    internal fun englishCaption(captions:JSONArray?):String? {
        if(captions==null) return null
        return (0 until captions.length()).mapNotNull {captions.optJSONObject(it)}.firstOrNull {
            val language=it.optString("language").lowercase(java.util.Locale.ROOT)
            (language=="en" || language=="eng" || language.startsWith("english")) && it.optString("type").lowercase() in listOf("srt","vtt") && it.optString("url").startsWith("https://")
        }?.optString("url")
    }
    fun subtitle(item:DownloadItem):String? = englishCaption(stream(item).optJSONArray("captions"))
    fun resolve(item: DownloadItem, captions:(String?)->Unit = {}): String {
        val stream=stream(item)
        check(stream?.optString("type") == "file") { "This title is available for streaming only; no MP4 download is available." }
        val qualities = stream!!.optJSONObject("qualities") ?: error("No downloadable video found.")
        val link = preferredQualityUrl(qualities)
        check(URL(link).protocol == "https") { "Unsupported download source." }
        captions(englishCaption(stream.optJSONArray("captions")))
        return link
    }
}
