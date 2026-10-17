package com.streamify.app.downloads

import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class OfflinePlayerActivity : ComponentActivity() {
    private lateinit var video: VideoView
    private val key get() = intent.getStringExtra("key").orEmpty()
    private val prefs by lazy { getSharedPreferences("offline-positions",MODE_PRIVATE) }
    private var resume = true
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window,false)
        WindowInsetsControllerCompat(window,window.decorView).apply { hide(WindowInsetsCompat.Type.systemBars());systemBarsBehavior=WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE }
        val file=DownloadStore.get(this).file(key)
        if(!file.isFile) { Toast.makeText(this,"Downloaded video is missing. Download it again.",Toast.LENGTH_LONG).show();finish();return }
        val root=FrameLayout(this).apply { setBackgroundColor(android.graphics.Color.BLACK) }
        video=VideoView(this)
        root.addView(video,FrameLayout.LayoutParams(-1,-1,Gravity.CENTER))
        val controls=MediaController(this).apply { setAnchorView(root) }
        video.setMediaController(controls)
        video.setOnPreparedListener { video.seekTo(prefs.getInt(key,0));if(resume) video.start() }
        video.setOnCompletionListener { prefs.edit().remove(key).apply();finish() }
        video.setOnErrorListener { _,_,_ -> Toast.makeText(this,"This downloaded file could not play.",Toast.LENGTH_LONG).show();finish();true }
        setContentView(root)
        video.setVideoPath(file.absolutePath)
    }
    override fun onPause() { if(::video.isInitialized) { resume=video.isPlaying;prefs.edit().putInt(key,video.currentPosition).apply();video.pause() };super.onPause() }
    override fun onResume() { super.onResume();if(::video.isInitialized && resume) video.start() }
    override fun onDestroy() { if(::video.isInitialized) video.stopPlayback();super.onDestroy() }
}
