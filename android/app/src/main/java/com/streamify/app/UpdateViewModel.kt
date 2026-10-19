package com.streamify.app

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.compose.runtime.*
import com.streamify.app.data.AppUpdate
import kotlinx.coroutines.*
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class UpdateViewModel(app: Application) : AndroidViewModel(app) {
    var busy by mutableStateOf(false); private set
    var message by mutableStateOf("Check for the latest Android release."); private set
    var available by mutableStateOf<AppUpdate?>(null); private set
    var progress by mutableFloatStateOf(0f); private set
    var ready by mutableStateOf<File?>(null); private set
    private fun connection(url: String): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15000; readTimeout = 30000
            setRequestProperty("User-Agent", "Streamify-Android/${BuildConfig.VERSION_NAME}")
            setRequestProperty("Accept", "application/vnd.github+json")
        }
    }
    private fun text(url: String): String {
        val c = connection(url)
        try {
            require(c.responseCode == 200) { if (c.responseCode == 403 || c.responseCode == 429) "Update checks are temporarily limited. Try later." else "Cannot check updates (HTTP ${c.responseCode})." }
            val bytes = c.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() <= 1048576) {
                    val count = input.read(buffer); if (count < 0) break
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            require(bytes.size <= 1048576) { "Update information is too large." }
            return bytes.toString(Charsets.UTF_8)
        } finally { c.disconnect() }
    }
    private var lastAutomaticCheck=0L
    fun checkAutomatically() {
        val now=android.os.SystemClock.elapsedRealtime()
        if(busy || ready!=null || (lastAutomaticCheck!=0L && now-lastAutomaticCheck<6*60*60*1000)) return
        lastAutomaticCheck=now
        check()
    }
    fun check() {
        if (busy) return
        busy = true; message = "Checking GitHub releases…"; available = null; ready = null
        viewModelScope.launch {
            try {
                val update = withContext(Dispatchers.IO) {
                    val releases = JSONArray(text("https://api.github.com/repos/${AppUpdate.REPO}/releases?per_page=30"))
                    val ordered=(0 until releases.length()).map {releases.getJSONObject(it)}
                        .filterNot {it.optBoolean("draft") || it.optBoolean("prerelease")}
                        .mapNotNull {release -> release.optString("tag_name").removePrefix("android-v").toLongOrNull()?.takeIf {release.optString("tag_name").startsWith("android-v")}?.let {it to release}}
                        .sortedByDescending {it.first}
                    var newest:AppUpdate?=null
                    for((code,release) in ordered) {
                        val assets=release.getJSONArray("assets")
                        val asset=(0 until assets.length()).map {assets.getJSONObject(it)}.firstOrNull {it.optString("name")=="update.json"} ?: continue
                        val url=asset.getString("browser_download_url")
                        require(AppUpdate.trustedAsset(url)) {"Untrusted release address."}
                        newest=AppUpdate.parse(text(url))
                        require(newest.versionCode==code) {"Release version does not match its update information."}
                        break
                    }
                    newest
                }
                available = update?.takeIf { it.versionCode > BuildConfig.VERSION_CODE }
                message = when { update == null -> "No Android updates have been published yet."; available == null -> "You’re up to date."; else -> "Version ${update.versionName} is available." }
            } catch (e: Exception) { if (e is CancellationException) throw e; message = e.message ?: "Update check failed. Try again." }
            finally { busy = false }
        }
    }
    fun download() {
        val update = available ?: return
        if (busy) return
        busy = true; progress = 0f; message = "Downloading update…"
        viewModelScope.launch {
            try {
                val file = withContext(Dispatchers.IO) {
                    val directory = File(getApplication<Application>().cacheDir, "updates").apply { mkdirs() }
                    val partial = File(directory, "update.part")
                    val destination = File(directory, "streamify.apk")
                    val c = connection(update.url)
                    try {
                        require(c.responseCode == 200 && c.url.protocol == "https") { "Download failed. Try again." }
                        val digest = MessageDigest.getInstance("SHA-256")
                        var total = 0L
                        c.inputStream.use { input -> partial.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            while (true) {
                                ensureActive()
                                val count = input.read(buffer); if (count < 0) break
                                total += count; require(total <= update.size) { "Unexpected download size." }
                                output.write(buffer, 0, count); digest.update(buffer, 0, count)
                                withContext(Dispatchers.Main) { progress = total.toFloat() / update.size }
                            }
                        } }
                        require(total == update.size && digest.digest().joinToString("") { "%02x".format(it) } == update.sha256) { "Download verification failed. Please retry." }
                        verify(partial, update.versionCode)
                        require(partial.renameTo(destination)) { "Could not save update." }
                        destination
                    } finally { c.disconnect(); partial.delete() }
                }
                ready = file; message = "Update verified. Ready to install."
            } catch (e: Exception) { if (e is CancellationException) throw e; message = e.message ?: "Download failed. Try again." }
            finally { busy = false }
        }
    }
    @Suppress("DEPRECATION")
    private fun verify(file: File, expectedCode: Long) {
        val app = getApplication<Application>(); val pm = app.packageManager
        val candidate = pm.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNATURES) ?: error("Invalid APK.")
        val installed = pm.getPackageInfo(app.packageName, PackageManager.GET_SIGNATURES)
        val code = if (android.os.Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        require(candidate.packageName == app.packageName && code == expectedCode && code > BuildConfig.VERSION_CODE) { "This APK is not a newer Streamify update." }
        require(!candidate.signatures.isNullOrEmpty() && candidate.signatures!!.toSet() == installed.signatures?.toSet()) { "This update has a different signing key and cannot replace your app." }
    }
    fun install(context: android.content.Context) {
        val file = ready ?: return
        try {
            if (!context.packageManager.canRequestPackageInstalls()) {
                message = "Allow updates from Streamify, then return here and tap Install update."
                context.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
                return
            }
            verify(file, available!!.versionCode)
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
            context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            message = "Confirm the update in Android’s installer. If cancelled, tap Install update to retry."
        } catch (e: Exception) { message = e.message ?: "Could not open the installer." }
    }
}
