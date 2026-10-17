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
    private lateinit var transport: LinearLayout
    private lateinit var timeline: LinearLayout
    private lateinit var playButton: ImageButton
    private lateinit var seek: SeekBar
    private lateinit var time: TextView
    private var scrubbing=false
    private val handler=Handler(Looper.getMainLooper())
    private val hideControls=Runnable { if(::toolbar.isInitialized) toolbar.visibility=View.GONE; if(::transport.isInitialized) transport.visibility=View.GONE; if(::timeline.isInitialized) timeline.visibility=View.GONE }
    private var closing=false
    private val toggleAction="com.streamify.app.OFFLINE_TOGGLE"
    private val receiver=object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if(intent?.action==toggleAction && ::video.isInitialized) { if(video.isPlaying) video.pause() else video.start();resume=video.isPlaying;updatePip() }
        }
    }
    private val update=object : Runnable { override fun run() { updatePip();refreshControls();handler.postDelayed(this,750) } }
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
        toolbar.visibility=View.VISIBLE;transport.visibility=View.VISIBLE;timeline.visibility=View.VISIBLE;handler.removeCallbacks(hideControls);handler.postDelayed(hideControls,4000)
    }
    private fun dp(value:Int)=(value*resources.displayMetrics.density).toInt()
    private fun icon(resource:Int,label:String,action:()->Unit)=ImageButton(this).apply {
        setImageResource(resource);imageTintList=android.content.res.ColorStateList.valueOf(-1)
        background=null;setPadding(dp(12),dp(12),dp(12),dp(12));scaleType=ImageView.ScaleType.FIT_CENTER
        contentDescription=label;setOnClickListener { action() }
    }
    private fun refreshControls() {
        if(!::playButton.isInitialized || !::video.isInitialized) return
        playButton.setImageResource(if(video.isPlaying) R.drawable.pip_pause else R.drawable.pip_play)
        playButton.contentDescription=if(video.isPlaying) "Pause" else "Play"
        val duration=video.duration.coerceAtLeast(0);val position=video.currentPosition.coerceAtLeast(0)
        if(!scrubbing) seek.progress=if(duration>0) (position.toLong()*1000/duration).toInt() else 0
        fun stamp(ms:Int):String {val seconds=ms/1000;return if(seconds>=3600) "%d:%02d:%02d".format(seconds/3600,seconds/60%60,seconds%60) else "%d:%02d".format(seconds/60,seconds%60)}
        time.text="${stamp(position)}  /  ${stamp(duration)}"
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

        video.setOnPreparedListener { video.seekTo(prefs.getInt(key,0));if(resume) video.start();updatePip() }
        video.setOnCompletionListener { prefs.edit().remove(key).apply();finish() }
        video.setOnErrorListener { _,_,_ -> Toast.makeText(this,"This downloaded file could not play.",Toast.LENGTH_LONG).show();finish();true }
        toolbar=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL;setPadding(dp(16),dp(8),dp(16),dp(8));background=android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,intArrayOf(0xB3000000.toInt(),0x00000000)) }
        val controlSize=(48*resources.displayMetrics.density).toInt()
        toolbar.addView(icon(R.drawable.player_back,"Exit offline player") { closing=true;updatePip();finish() },LinearLayout.LayoutParams(controlSize,controlSize))
        toolbar.addView(TextView(this).apply { text=DownloadStore.get(this@OfflinePlayerActivity).get(key)?.title ?: "Offline video";setTextColor(android.graphics.Color.WHITE);textSize=16f;gravity=Gravity.CENTER_VERTICAL;setPadding(16,0,16,0);maxLines=1 },LinearLayout.LayoutParams(0,controlSize,1f))
        if(packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) toolbar.addView(icon(R.drawable.player_pip,"Picture-in-picture") { enterPip() },LinearLayout.LayoutParams(controlSize,controlSize))
        root.addView(toolbar,FrameLayout.LayoutParams(-1,-2,Gravity.TOP))
        transport=LinearLayout(this).apply { gravity=Gravity.CENTER;orientation=LinearLayout.HORIZONTAL }
        transport.addView(icon(R.drawable.player_rewind,"Rewind 10 seconds") { video.seekTo((video.currentPosition-10000).coerceAtLeast(0));showControls() },LinearLayout.LayoutParams(dp(64),dp(64)))
        playButton=icon(R.drawable.pip_pause,"Pause") { if(video.isPlaying) video.pause() else video.start();resume=video.isPlaying;refreshControls();showControls() }
        transport.addView(playButton,LinearLayout.LayoutParams(dp(80),dp(80)).apply {setMargins(dp(40),0,dp(40),0)})
        transport.addView(icon(R.drawable.player_forward,"Forward 10 seconds") { video.seekTo((video.currentPosition+10000).coerceAtMost(video.duration));showControls() },LinearLayout.LayoutParams(dp(64),dp(64)))
        root.addView(transport,FrameLayout.LayoutParams(-2,-2,Gravity.CENTER))
        timeline=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;setPadding(dp(24),dp(12),dp(24),dp(16));background=android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.BOTTOM_TOP,intArrayOf(0xB3000000.toInt(),0x00000000)) }
        time=TextView(this).apply {setTextColor(-1);textSize=12f;gravity=Gravity.END}
        seek=SeekBar(this).apply { progressTintList=android.content.res.ColorStateList.valueOf(0xFFE50914.toInt());thumbTintList=android.content.res.ColorStateList.valueOf(-1);progressBackgroundTintList=android.content.res.ColorStateList.valueOf(0x66FFFFFF);max=1000 }
        seek.setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(bar:SeekBar) {scrubbing=true;handler.removeCallbacks(hideControls)}
            override fun onStopTrackingTouch(bar:SeekBar) {video.seekTo((video.duration.toLong()*bar.progress/1000).toInt());scrubbing=false;showControls()}
            override fun onProgressChanged(bar:SeekBar,value:Int,fromUser:Boolean) { }
        })
        timeline.addView(seek,LinearLayout.LayoutParams(-1,dp(40)));timeline.addView(time)
        root.addView(timeline,FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM))
        video.setOnClickListener { if(toolbar.visibility==View.VISIBLE) hideControls.run() else showControls() }
        setContentView(root)
        video.setVideoPath(file.absolutePath)
        showControls();handler.post(update)
    }
    override fun onUserLeaveHint() { super.onUserLeaveHint();if(::video.isInitialized && video.isPlaying && !closing) enterPip() }
    override fun onPictureInPictureModeChanged(inPip: Boolean, configuration: Configuration) {
        super.onPictureInPictureModeChanged(inPip,configuration)
        if(inPip) { hideControls.run() } else showControls()
    }
    override fun onPause() { if(::video.isInitialized) { resume=video.isPlaying;prefs.edit().putInt(key,video.currentPosition).apply() };super.onPause() }
    override fun onStop() { if(::video.isInitialized) video.pause();super.onStop() }
    override fun onResume() { super.onResume();if(::video.isInitialized && resume) video.start() }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);unregisterReceiver(receiver);if(::video.isInitialized) video.stopPlayback();super.onDestroy() }
}
