package com.streamify.app.downloads

import android.os.Bundle
import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RemoteAction
import android.content.*
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.View
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.streamify.app.R

class OfflinePlayerActivity : ComponentActivity() {
    private lateinit var video: VideoView
    private val key get() = intent.getStringExtra("key").orEmpty()
    private val prefs by lazy { getSharedPreferences("offline-positions",MODE_PRIVATE) }
    private var resume = true
    private lateinit var toolbar: LinearLayout
    private lateinit var controls: MediaController
    private val handler=Handler(Looper.getMainLooper())
    private val hideControls=Runnable { if(::toolbar.isInitialized) toolbar.visibility=View.GONE }
    private var closing=false
    private val toggleAction="com.streamify.app.OFFLINE_TOGGLE"
    private val receiver=object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if(intent?.action==toggleAction && ::video.isInitialized) { if(video.isPlaying) video.pause() else video.start();resume=video.isPlaying;updatePip() }
        }
    }
    private val update=object : Runnable { override fun run() { updatePip();handler.postDelayed(this,750) } }
    private fun pipParams(): PictureInPictureParams {
        val playing=::video.isInitialized && video.isPlaying
        val toggle=PendingIntent.getBroadcast(this,401,Intent(toggleAction).setPackage(packageName),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val action=RemoteAction(Icon.createWithResource(this,if(playing) R.drawable.pip_pause else R.drawable.pip_play),if(playing) "Pause" else "Play","Play or pause offline video",toggle)
        return PictureInPictureParams.Builder().setAspectRatio(Rational(16,9)).setActions(listOf(action)).apply {
            if(Build.VERSION.SDK_INT>=31) setAutoEnterEnabled(playing && !closing).setSeamlessResizeEnabled(true)
        }.build()
    }
    private fun updatePip() { if(packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) runCatching { setPictureInPictureParams(pipParams()) } }
    private fun enterPip() {
        if(!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        runCatching { enterPictureInPictureMode(pipParams()) }
    }
    private fun showControls() {
        if(isInPictureInPictureMode) return
        toolbar.visibility=View.VISIBLE;handler.removeCallbacks(hideControls);handler.postDelayed(hideControls,4000)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.content.ContextCompat.registerReceiver(this,receiver,IntentFilter(toggleAction),androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window,false)
        WindowInsetsControllerCompat(window,window.decorView).apply { hide(WindowInsetsCompat.Type.systemBars());systemBarsBehavior=WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE }
        val file=DownloadStore.get(this).file(key)
        if(!file.isFile) { Toast.makeText(this,"Downloaded video is missing. Download it again.",Toast.LENGTH_LONG).show();finish();return }
        val root=FrameLayout(this).apply { setBackgroundColor(android.graphics.Color.BLACK) }
        video=VideoView(this)
        root.addView(video,FrameLayout.LayoutParams(-1,-1,Gravity.CENTER))
        controls=MediaController(this).apply { setAnchorView(root) }
        video.setMediaController(controls)
        video.setOnPreparedListener { video.seekTo(prefs.getInt(key,0));if(resume) video.start();updatePip() }
        video.setOnCompletionListener { prefs.edit().remove(key).apply();finish() }
        video.setOnErrorListener { _,_,_ -> Toast.makeText(this,"This downloaded file could not play.",Toast.LENGTH_LONG).show();finish();true }
        toolbar=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL;setPadding(20,8,20,8);setBackgroundColor(0x66000000) }
        val controlSize=(48*resources.displayMetrics.density).toInt()
        toolbar.addView(ImageButton(this).apply { setImageResource(android.R.drawable.ic_menu_close_clear_cancel);imageTintList=android.content.res.ColorStateList.valueOf(android.graphics.Color.WHITE);setBackgroundColor(android.graphics.Color.TRANSPARENT);contentDescription="Exit offline player";setOnClickListener { closing=true;updatePip();finish() } },LinearLayout.LayoutParams(controlSize,controlSize))
        toolbar.addView(TextView(this).apply { text=DownloadStore.get(this@OfflinePlayerActivity).get(key)?.title ?: "Offline video";setTextColor(android.graphics.Color.WHITE);textSize=16f;gravity=Gravity.CENTER_VERTICAL;setPadding(16,0,16,0);maxLines=1 },LinearLayout.LayoutParams(0,controlSize,1f))
        if(packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) toolbar.addView(Button(this).apply { text="PiP";contentDescription="Picture-in-picture";setOnClickListener { enterPip() } })
        root.addView(toolbar,FrameLayout.LayoutParams(-1,-2,Gravity.TOP))
        video.setOnTouchListener { _,event -> if(event.action==android.view.MotionEvent.ACTION_DOWN) showControls();false }
        setContentView(root)
        video.setVideoPath(file.absolutePath)
        showControls();handler.post(update)
    }
    override fun onUserLeaveHint() { super.onUserLeaveHint();if(::video.isInitialized && video.isPlaying && !closing) enterPip() }
    override fun onPictureInPictureModeChanged(inPip: Boolean, configuration: Configuration) {
        super.onPictureInPictureModeChanged(inPip,configuration)
        if(inPip) { toolbar.visibility=View.GONE;controls.hide() } else showControls()
    }
    override fun onPause() { if(::video.isInitialized) { resume=video.isPlaying;prefs.edit().putInt(key,video.currentPosition).apply() };super.onPause() }
    override fun onStop() { if(::video.isInitialized) video.pause();super.onStop() }
    override fun onResume() { super.onResume();if(::video.isInitialized && resume) video.start() }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);unregisterReceiver(receiver);if(::video.isInitialized) video.stopPlayback();super.onDestroy() }
}
