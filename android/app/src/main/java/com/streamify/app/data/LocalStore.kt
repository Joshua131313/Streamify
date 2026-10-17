package com.streamify.app.data

import android.content.Context
import com.streamify.app.BuildConfig
import org.json.JSONArray
import org.json.JSONObject

class LocalStore(private val context: Context, private val accountId: () -> String? = {
    com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.takeUnless { it.isAnonymous }?.uid
}) {
    private val prefs = context.getSharedPreferences("streamify", Context.MODE_PRIVATE)
    private val dataPrefs get() = accountId()?.let { context.getSharedPreferences("streamify-account-$it", Context.MODE_PRIVATE) } ?: prefs
    var theme: String
        get() = prefs.getString("theme", "Dark") ?: "Dark"
        set(value) { prefs.edit().putString("theme", value).apply() }
    var tmdbKey: String
        get() = prefs.getString("tmdbKey", BuildConfig.TMDB_API_KEY).orEmpty()
        set(value) { prefs.edit().putString("tmdbKey", value.trim()).apply() }
    var apiBase: String
        get() = prefs.getString("apiBase", BuildConfig.API_BASE_URL).orEmpty()
        set(value) { prefs.edit().putString("apiBase", value.trim().trimEnd('/')).apply() }
    var serverId: String
        get() = prefs.getString("server", "streamex").orEmpty()
        set(value) { prefs.edit().putString("server", value).apply() }
    var animeServerId: String
        get() = dataPrefs.getString("animeServer", "anime-nest-sub").orEmpty().takeIf { id -> animeServers.any { it.id == id } } ?: "anime-nest-sub"
        set(value) { if (animeServers.any { it.id == value }) dataPrefs.edit().putString("animeServer", value).apply() }
    var searches: List<String>
        get() = array("searches").let { items -> (0 until items.length()).map { items.optString(it) }.filter { it.isNotBlank() } }
        set(value) { dataPrefs.edit().putString("searches", JSONArray(value.take(12)).toString()).apply() }
    val collections: List<Collection> = context.assets.open("collections.json").bufferedReader().use {
        JSONArray(it.readText()).objects().map { item ->
            val genres = item.getJSONArray("genres")
            Collection(item.getInt("id"), item.getString("name"), item.getString("backdrop").substringAfterLast('/'),
                (0 until genres.length()).map { i -> genres.getInt(i) }, item.optBoolean("featured"))
        }
    }
    var favorites: Set<String>
        get() = dataPrefs.getStringSet("favorites", emptySet())?.toSet() ?: emptySet()
        set(value) { dataPrefs.edit().putStringSet("favorites", value).apply() }
    var saved: List<Media>
        get() = array("saved").objects().mapNotNull { Media.parse(it) }
        set(value) { dataPrefs.edit().putString("saved", JSONArray(value.map { it.json() }).toString()).apply() }
    var history: List<History>
        get() = array("history").objects().mapNotNull {
            val media = it.optJSONObject("media")?.let { item -> Media.parse(item) } ?: return@mapNotNull null
            History(media, it.optInt("season", 1), it.optInt("episode", 1), it.optLong("watchedAt"), it.optDouble("positionSeconds", 0.0), it.optDouble("durationSeconds", 0.0))
        }
        set(value) {
            dataPrefs.edit().putString("history", JSONArray(value.take(200).map {
                JSONObject().put("media", it.media.json()).put("season", it.season).put("episode", it.episode).put("watchedAt", it.watchedAt).put("positionSeconds", it.positionSeconds).put("durationSeconds", it.durationSeconds)
            }).toString()).apply()
        }
    val servers: List<MediaServer> = context.assets.open("media-servers.json").bufferedReader().use {
        JSONArray(it.readText()).objects().map { server ->
            MediaServer(server.getString("id"), server.getString("label"), server.getString("movie"), server.getString("tv"))
        }
    }
    private fun array(key: String) = runCatching { JSONArray(dataPrefs.getString(key, "[]")) }.getOrElse { JSONArray() }
}
