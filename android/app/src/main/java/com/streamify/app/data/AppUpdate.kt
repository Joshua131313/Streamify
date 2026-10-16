package com.streamify.app.data

import org.json.JSONObject

data class AppUpdate(val versionCode: Long, val versionName: String, val url: String, val sha256: String, val size: Long, val notes: String) {
    companion object {
        const val REPO = "Joshua131313/streamify"
        fun trustedAsset(url: String): Boolean = runCatching {
            val uri = java.net.URI(url)
            uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null && uri.port == -1 &&
                uri.path.startsWith("/$REPO/releases/download/android-v", ignoreCase = true) && !uri.path.contains("..")
        }.getOrDefault(false)
        fun parse(raw: String): AppUpdate {
            val json = JSONObject(raw)
            return AppUpdate(json.getLong("versionCode"), json.getString("versionName"), json.getString("url"), json.getString("sha256").lowercase(), json.getLong("size"), json.optString("notes")).also {
                require(it.versionCode in 1..2100000000 && it.versionName.length in 1..80 && trustedAsset(it.url)) { "Invalid update information." }
                require(it.sha256.matches(Regex("[a-f0-9]{64}")) && it.size in 1..262144000) { "Invalid update file information." }
            }
        }
    }
}
