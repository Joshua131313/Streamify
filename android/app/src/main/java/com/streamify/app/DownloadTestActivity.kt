package com.streamify.app

import android.app.DownloadManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.*
import androidx.activity.ComponentActivity
import java.io.File

/** Isolated single-title download experiment; no catalogue or account integration. */
class DownloadTestActivity : ComponentActivity() {
    private val manager by lazy { getSystemService(DownloadManager::class.java) }
    private val prefs by lazy { getSharedPreferences("movie-download-test", MODE_PRIVATE) }
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var download: Button
    private lateinit var play: Button
    private lateinit var progress: ProgressBar
    private val poll = object : Runnable {
        override fun run() { refresh(); handler.postDelayed(this, 1000) }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 64, 32, 32)
            setBackgroundColor(android.graphics.Color.rgb(11, 13, 16))
        }
        fun label(value: String, size: Float) = TextView(this).apply {
            text = value; textSize = size; setTextColor(android.graphics.Color.WHITE)
            setPadding(0, 16, 0, 16); layout.addView(this)
        }
        Button(this).apply { text = "Back"; setOnClickListener { finish() }; layout.addView(this) }
        label("Download test · Titanic", 22f)
        label("One hardcoded movie · approximately 2.18 GB. The test link may expire. Android manages the transfer in the background. Once complete, turn off Wi-Fi/mobile data and tap Watch offline.", 16f)
        status = label("Ready", 16f)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100; layout.addView(this) }
        download = Button(this).apply {
            text = "Download test movie (2.18 GB)"
            setOnClickListener {
                try {
                    val file = File(getExternalFilesDir(null), "titanic-download-test.mp4")
                    // Remove only this experiment's previous failed transfer before retrying.
                    val previous = prefs.getLong("id", -1)
                    if (previous != -1L) manager.remove(previous)
                    if (file.exists()) file.delete()
                    val url = assets.open("download-test-url.txt").bufferedReader().use { it.readText().trim() }
                    val id = manager.enqueue(DownloadManager.Request(Uri.parse(url))
                        .setTitle("Streamify · Titanic download test")
                        .setMimeType("video/mp4")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationUri(Uri.fromFile(file)))
                    prefs.edit().putLong("id", id).apply()
                    refresh()
                } catch (e: Exception) { status.text = "Could not start: ${e.localizedMessage}" }
            }
            layout.addView(this)
        }
        play = Button(this).apply {
            text = "Watch offline"; visibility = View.GONE
            setOnClickListener {
                val uri = manager.getUriForDownloadedFile(prefs.getLong("id", -1))
                if (uri == null) { status.text = "Downloaded file is missing"; return@setOnClickListener }
                handler.removeCallbacks(poll)
                val video = VideoView(this@DownloadTestActivity)
                setContentView(video)
                video.setMediaController(MediaController(this@DownloadTestActivity).apply { setAnchorView(video) })
                video.setOnErrorListener { _, _, _ ->
                    Toast.makeText(this@DownloadTestActivity, "This file could not play. Press Back to exit.", Toast.LENGTH_LONG).show(); true
                }
                video.setVideoURI(uri); video.start()
            }
            layout.addView(this)
        }
        setContentView(layout)
        handler.post(poll)
    }
    private fun refresh() {
        val id = prefs.getLong("id", -1)
        if (id == -1L) return
        manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (!cursor.moveToFirst()) { status.text = "No saved download. Try again."; download.isEnabled = true; play.visibility = View.GONE; return }
            val state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            progress.progress = if (total > 0) (bytes * 100 / total).toInt() else 0
            status.text = when (state) {
                DownloadManager.STATUS_SUCCESSFUL -> "Ready to watch offline"
                DownloadManager.STATUS_FAILED -> "Download failed (code ${cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))}). You can retry; the test link may have expired."
                DownloadManager.STATUS_PAUSED -> "Waiting for network or Android download service"
                else -> "Downloading · ${bytes / 1_000_000} / ${if (total > 0) total / 1_000_000 else "?"} MB"
            }
            download.isEnabled = state == DownloadManager.STATUS_FAILED
            play.visibility = if (state == DownloadManager.STATUS_SUCCESSFUL) View.VISIBLE else View.GONE
        }
    }
    override fun onDestroy() { handler.removeCallbacks(poll); super.onDestroy() }
}
