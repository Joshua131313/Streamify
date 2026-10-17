package com.streamify.app

import android.media.MediaMetadataRetriever
import android.net.ConnectivityManager
import android.net.Uri
import android.widget.VideoView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Test APK only. No download UI, background service, or release-app behavior changes. */
internal class ResumableDownloadProbe(private val source: String, private val file: File) {
    private val metadata = File(file.path + ".json")
    private val state = if (metadata.exists()) JSONObject(metadata.readText()) else JSONObject()
    val total get() = state.optLong("total", -1)

    fun transfer(untilBytes: Long = Long.MAX_VALUE): Int {
        require(URL(source).protocol == "https") { "Only HTTPS download sources are accepted" }
        val offset = file.takeIf { it.exists() }?.length() ?: 0L
        check(offset == 0L || state.optString("source") == source) { "Partial file belongs to another source" }
        val connection = URL(source).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000; connection.readTimeout = 20_000
        connection.setRequestProperty("Accept-Encoding", "identity")
        if (offset > 0) {
            connection.setRequestProperty("Range", "bytes=$offset-")
            state.optString("validator").takeIf { it.isNotBlank() }?.let { connection.setRequestProperty("If-Range", it) }
        }
        try {
            val status = connection.responseCode
            check(connection.url.protocol == "https") { "Insecure download redirect rejected" }
            val contentType = connection.contentType.orEmpty().substringBefore(';')
            check(contentType.startsWith("video/") || contentType == "application/octet-stream") {
                "Source returned HTTP $status, content type $contentType; not a video download"
            }
            if (offset > 0) validateResume(status, connection.getHeaderField("Content-Range"), offset, total)
            else check(status == 200) { "Initial request failed: HTTP $status" }
            val bytes = if (offset == 0L) connection.contentLengthLong else total
            check(bytes in 1..1_600_000_000L) { "Unknown size or exceeds 1.6 GB prototype limit" }
            val validator = connection.getHeaderField("ETag")?.takeUnless { it.startsWith("W/") }
                ?: connection.getHeaderField("Last-Modified").orEmpty()
            if (offset > 0 && state.optString("validator").isNotBlank() && validator.isNotBlank()) {
                check(validator == state.getString("validator")) { "Remote file changed; partial download cannot be resumed" }
            }
            state.put("source", source).put("total", bytes).put("validator", validator)
            metadata.writeText(state.toString())
            connection.inputStream.use { input -> RandomAccessFile(file, "rw").use { output ->
                output.seek(offset)
                val buffer = ByteArray(64 * 1024)
                val deadline = System.currentTimeMillis() + 600_000
                while (output.length() < minOf(untilBytes, bytes)) {
                    check(System.currentTimeMillis() < deadline) { "Prototype transfer time limit reached" }
                    val count = input.read(buffer, 0, minOf(buffer.size.toLong(), minOf(untilBytes, bytes) - output.length()).toInt())
                    check(count > 0) { "Download ended before the declared file size" }
                    output.write(buffer, 0, count)
                }
                output.fd.sync()
            } }
            return status
        } finally { connection.disconnect() }
    }

    companion object {
        fun validateResume(status: Int, range: String?, offset: Long, expectedTotal: Long) {
            check(status == 206) { "Server did not honor resume request (HTTP $status); nothing appended" }
            val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(range.orEmpty())
                ?: error("Missing or invalid Content-Range; nothing appended")
            check(match.groupValues[1].toLong() == offset && match.groupValues[2].toLong() >= offset && match.groupValues[3].toLong() == expectedTotal) {
                "Resume range or remote size changed; nothing appended"
            }
        }
    }
}

@RunWith(AndroidJUnit4::class)
class DownloadPrototypeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val directory get() = File(context.getExternalFilesDir(null), "download-prototype").apply { mkdirs() }
    private val device get() = UiDevice.getInstance(instrumentation)

    @Test fun refusesUnsafeResumeResponses() {
        ResumableDownloadProbe.validateResume(206, "bytes 100-999/1000", 100, 1000)
        listOf(200 to "bytes 100-999/1000", 206 to "bytes 0-999/1000", 206 to "bytes 100-1999/2000", 206 to "").forEach { (status, range) ->
            assertTrue(runCatching { ResumableDownloadProbe.validateResume(status, range, 100, 1000) }.isFailure)
        }
    }

    @Test fun localControlVideoPlaysWithNetworkDisabled() {
        val video = File(directory, "control.mp4")
        assumeTrue("Upload the app-owned control recording first", video.isFile)
        val result = JSONObject().put("kind", "local control only; not Screenscape")
        try { playOffline(video, result) }
        finally { File(directory, "control-result.json").writeText(result.toString(2)) }
    }

    @Test fun screenscapeDownloadPauseResumeAndOfflinePlayback() {
        val config = File(directory, "source.json")
        val report = JSONObject().put("download", "not tested").put("pauseResume", "not tested").put("offlinePlayback", "not tested")
        val reportFile = File(directory, "screenscape-result.json")
        if (!config.exists()) {
            report.put("blocked", "A verified Screenscape direct video URL is required; download landing pages are not files")
            reportFile.writeText(report.toString(2))
            assumeTrue("No verified direct download URL available", false)
        }
        val source = JSONObject(config.readText()).getString("url")
        val video = File(directory, "screenscape.mp4")
        // Preserve interrupted test artifacts; each live run needs a fresh output path.
        check(!video.exists()) { "Previous prototype file exists; inspect or move it before a fresh run" }
        try {
            var downloader = ResumableDownloadProbe(source, video)
            report.put("initialHttpStatus", downloader.transfer(1_048_576))
            report.put("download", "partial received").put("totalBytes", downloader.total)
            val pausedAt = video.length()
            val firstHash = prefixHash(video, pausedAt)
            Thread.sleep(1500)
            check(video.length() == pausedAt) { "File grew while paused" }
            report.put("pausedAtBytes", pausedAt)
            // Reconstruct the downloader to prove resume survives object recreation.
            downloader = ResumableDownloadProbe(source, video)
            report.put("resumeHttpStatus", downloader.transfer())
            check(video.length() == downloader.total)
            check(prefixHash(video, pausedAt) == firstHash) { "Resume corrupted the existing prefix" }
            report.put("download", "complete").put("pauseResume", "passed")
            playOffline(video, report)
        } catch (e: Exception) { report.put("failure", e.message); throw e }
        finally { reportFile.writeText(report.toString(2)) }
    }

    private fun prefixHash(file: File, bytes: Long): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536); var left = bytes
            while (left > 0) { val n = input.read(buffer, 0, minOf(left, buffer.size.toLong()).toInt()); check(n > 0); digest.update(buffer, 0, n); left -= n }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun playOffline(file: File, report: JSONObject) {
        val wifi = device.executeShellCommand("settings get global wifi_on").trim() != "0"
        val data = device.executeShellCommand("settings get global mobile_data").trim() == "1"
        try {
            device.executeShellCommand("svc wifi disable"); device.executeShellCommand("svc data disable")
            val connectivity = context.getSystemService(ConnectivityManager::class.java)
            repeat(20) { if (connectivity.activeNetwork != null) Thread.sleep(250) }
            check(connectivity.activeNetwork == null) { "Network is still connected; cannot claim offline playback" }
            MediaMetadataRetriever().use { retriever ->
                retriever.setDataSource(file.absolutePath)
                report.put("durationMs", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION))
                val frame = retriever.getFrameAtTime(1_000_000) ?: error("Local video frame could not be decoded")
                report.put("frameWidth", frame.width).put("frameHeight", frame.height); frame.recycle()
            }
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val ready = CountDownLatch(1); val error = AtomicReference<String?>(null)
                lateinit var view: VideoView
                scenario.onActivity { activity ->
                    view = VideoView(activity)
                    activity.setContentView(view)
                    view.setOnPreparedListener { view.start(); ready.countDown() }
                    view.setOnErrorListener { _, what, extra -> error.set("Playback error $what/$extra"); ready.countDown(); true }
                    view.setVideoURI(Uri.fromFile(file))
                }
                check(ready.await(15, TimeUnit.SECONDS)) { "Local playback preparation timed out" }
                check(error.get() == null) { error.get().orEmpty() }
                Thread.sleep(1500)
                scenario.onActivity { check(view.currentPosition > 500) { "Local playback clock did not advance" }; report.put("positionMs", view.currentPosition) }
                device.takeScreenshot(File(directory, "offline-playback.png"))
            }
            report.put("offlinePlayback", "passed with no active network")
        } finally {
            if (wifi) device.executeShellCommand("svc wifi enable")
            if (data) device.executeShellCommand("svc data enable")
        }
    }
}
