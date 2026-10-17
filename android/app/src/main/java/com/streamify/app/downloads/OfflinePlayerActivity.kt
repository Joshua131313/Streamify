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
    private var player: android.media.MediaPlayer?=null
    private var speed=1f
    private var lastSeekAt=0L
    private var seekTarget=0L
    private var settingsOpen=false
    private var brightnessControl: View?=null
    private var volumeControl: View?=null
    private var seekPreview: SeekPreview?=null
    private lateinit var speedButton: TextView
    private var settingsDialog: android.app.Dialog?=null
    private val handler=Handler(Looper.getMainLooper())
    private val hideControls=Runnable { if(::toolbar.isInitialized) toolbar.visibility=View.GONE; if(::transport.isInitialized) transport.visibility=View.GONE; if(::timeline.isInitialized) timeline.visibility=View.GONE;brightnessControl?.visibility=View.GONE;volumeControl?.visibility=View.GONE;seekPreview?.hidePreview() }
    private var fillScreen=false
    private var sourceWidth=0
    private var sourceHeight=0
    private lateinit var scaleDetector:android.view.ScaleGestureDetector
    private var pinchActive=false
    private var pinchScale=1f
    private var pinchChanged=false
    private fun setVideoFill(fill:Boolean) {
        if(fillScreen==fill) return
        fillScreen=fill;video.requestLayout()
        gestureFeedback.animate().cancel();gestureFeedback.translationX=0f
        gestureFeedback.text=if(fill) "Fill screen" else "Fit screen"
        gestureFeedback.visibility=View.VISIBLE;gestureFeedback.alpha=1f
        gestureFeedback.scaleX=1f;gestureFeedback.scaleY=1f
        gestureFeedback.animate().alpha(0f).setStartDelay(650).setDuration(250).withEndAction {gestureFeedback.visibility=View.GONE}.start()
        video.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
    }
    private var locked=false
    private lateinit var unlockOverlay:FrameLayout
    private val hideUnlock=Runnable {if(::unlockOverlay.isInitialized) unlockOverlay.visibility=View.GONE}
    private lateinit var gestureDetector:android.view.GestureDetector
    private lateinit var gestureFeedback:TextView
    private var gestureBrightness=.5f
    private var gestureVolume=0
    private var gestureTotal=0
    private var gestureLast=0L
    private var suppressControls=false
    private fun askUnlock() {
        unlockOverlay.visibility=View.VISIBLE;unlockOverlay.alpha=0f
        unlockOverlay.animate().alpha(1f).setDuration(160).start()
        handler.removeCallbacks(hideUnlock);handler.postDelayed(hideUnlock,3000)
    }
    override fun dispatchTouchEvent(event:android.view.MotionEvent):Boolean {
        if(locked && !isInPictureInPictureMode) {
            if(::unlockOverlay.isInitialized && unlockOverlay.visibility==View.VISIBLE) return super.dispatchTouchEvent(event)
            if(event.actionMasked==android.view.MotionEvent.ACTION_UP) askUnlock()
            return true
        }
        if(::scaleDetector.isInitialized && !isInPictureInPictureMode) {
            if(event.pointerCount>1 || pinchActive) {
                if(!pinchActive) {
                    pinchActive=true
                    val cancel=android.view.MotionEvent.obtain(event);cancel.action=android.view.MotionEvent.ACTION_CANCEL
                    super.dispatchTouchEvent(cancel);gestureDetector.onTouchEvent(cancel);cancel.recycle()
                }
                scaleDetector.onTouchEvent(event)
                if(event.actionMasked==android.view.MotionEvent.ACTION_UP || event.actionMasked==android.view.MotionEvent.ACTION_CANCEL) pinchActive=false
                return true
            }
            scaleDetector.onTouchEvent(event)
        }
        return super.dispatchTouchEvent(event)
    }
    private fun styleSideSlider(slider:SeekBar) {
        fun track(color:Int)=android.graphics.drawable.GradientDrawable().apply {setColor(color);cornerRadius=dp(3).toFloat();setSize(dp(150),dp(5))}
        slider.thumb=null;slider.background=null;slider.splitTrack=false
        slider.progressDrawable=android.graphics.drawable.LayerDrawable(arrayOf(track(0x55FFFFFF),android.graphics.drawable.ClipDrawable(track(-1),Gravity.LEFT,android.graphics.drawable.ClipDrawable.HORIZONTAL))).apply {
            setId(0,android.R.id.background);setId(1,android.R.id.progress)
            setLayerHeight(0,dp(5));setLayerHeight(1,dp(5));setLayerGravity(0,Gravity.CENTER_VERTICAL);setLayerGravity(1,Gravity.CENTER_VERTICAL)
        }
    }
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
        if(isInPictureInPictureMode || locked || suppressControls) return
        toolbar.visibility=View.VISIBLE;transport.visibility=View.VISIBLE;timeline.visibility=View.VISIBLE;brightnessControl?.visibility=View.VISIBLE;volumeControl?.visibility=View.VISIBLE;handler.removeCallbacks(hideControls);if(!settingsOpen && video.isPlaying) handler.postDelayed(hideControls,4000)
    }
    private fun dp(value:Int)=(value*resources.displayMetrics.density).toInt()
    private fun icon(resource:Int,label:String,action:()->Unit)=ImageButton(this).apply {
        setImageResource(resource);imageTintList=android.content.res.ColorStateList.valueOf(-1)
        background=null;setPadding(dp(12),dp(12),dp(12),dp(12));scaleType=ImageView.ScaleType.FIT_CENTER
        contentDescription=label;setOnClickListener { performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK);animate().scaleX(.88f).scaleY(.88f).setDuration(80).withEndAction {animate().scaleX(1f).scaleY(1f).setDuration(120).start()}.start();action() }
    }
    private fun refreshControls() {
        if(!::playButton.isInitialized || !::video.isInitialized) return
        ((volumeControl as? android.view.ViewGroup)?.getChildAt(1) as? SeekBar)?.let { slider ->
            if(!slider.isPressed) slider.progress=getSystemService(android.media.AudioManager::class.java).getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
        }
        playButton.setImageResource(if(video.isPlaying) R.drawable.pip_pause else R.drawable.pip_play)
        playButton.contentDescription=if(video.isPlaying) "Pause" else "Play"
        val duration=video.duration.coerceAtLeast(0);val position=video.currentPosition.coerceAtLeast(0)
        if(!scrubbing) seek.progress=if(duration>0) (position.toLong()*1000/duration).toInt() else 0
        fun stamp(ms:Int):String {val seconds=ms/1000;return if(seconds>=3600) "%d:%02d:%02d".format(seconds/3600,seconds/60%60,seconds%60) else "%d:%02d".format(seconds/60,seconds%60)}
        time.text=stamp((duration-position).coerceAtLeast(0))
    }
    private fun skipBy(seconds:Int) {
        val now=android.os.SystemClock.elapsedRealtime()
        val origin=if(now-lastSeekAt<850) seekTarget else video.currentPosition.toLong()
        seekTarget=(origin+seconds*1000L).coerceIn(0L,video.duration.coerceAtLeast(0).toLong());lastSeekAt=now
        player?.seekTo(seekTarget,android.media.MediaPlayer.SEEK_CLOSEST)
        refreshControls();showControls()
    }
    private fun actionLabel(label:String, action:()->Unit)=TextView(this).apply {
        text=label;setTextColor(-1);textSize=14f;gravity=Gravity.CENTER;setPadding(dp(20),dp(10),dp(20),dp(10))
        minHeight=dp(48);isFocusable=true;setOnClickListener {performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK);action()}
    }
    private fun panel(bottom:Boolean, content:(LinearLayout,android.app.Dialog)->Unit) {
        settingsOpen=true;handler.removeCallbacks(hideControls)
        val dialog=android.app.Dialog(this);settingsDialog=dialog
        val body=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(28),dp(12),dp(28),dp(20));setBackgroundColor(0xFF1C1C1C.toInt())}
        body.addView(icon(R.drawable.player_close,"Close playback settings") {dialog.dismiss()},LinearLayout.LayoutParams(dp(48),dp(48)).apply {gravity=Gravity.END})
        content(body,dialog);dialog.setContentView(body)
        dialog.setOnDismissListener {settingsOpen=false;settingsDialog=null;if(!isFinishing && !isDestroyed) showControls()}
        dialog.show();dialog.window?.apply {setBackgroundDrawableResource(android.R.color.transparent);setLayout(-1,if(bottom) -2 else -1);setGravity(if(bottom) Gravity.BOTTOM else Gravity.CENTER)
            WindowCompat.setDecorFitsSystemWindows(this,false)
            WindowInsetsControllerCompat(this,decorView).apply {hide(WindowInsetsCompat.Type.systemBars());systemBarsBehavior=WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE}
        }
    }
    private fun showSpeed()=panel(true) {body,dialog ->
        body.addView(actionLabel("Playback speed") {})
        val row=LinearLayout(this)
        val slider=SeekBar(this).apply {
            contentDescription="Playback speed";max=4;progress=listOf(.5f,.75f,1f,1.25f,1.5f).indexOf(speed).coerceAtLeast(0)
            progressTintList=android.content.res.ColorStateList.valueOf(-1);thumbTintList=android.content.res.ColorStateList.valueOf(-1)
            setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar:SeekBar) { }
                override fun onProgressChanged(bar:SeekBar,value:Int,fromUser:Boolean) {}
                override fun onStopTrackingTouch(bar:SeekBar) {row.getChildAt(bar.progress).performClick()}
            })
        };body.addView(slider,LinearLayout.LayoutParams(-1,dp(40)))
        listOf(.5f,.75f,1f,1.25f,1.5f).forEach { rate ->
            row.addView(actionLabel(if(rate==speed) "✓ ${rate}×" else "${rate}×") {
                val active=video.isPlaying
                runCatching {player?.let {it.playbackParams=it.playbackParams.setSpeed(rate);if(!active) it.pause();speed=rate;speedButton.text="Speed (${rate}×)"}}
                    .onFailure {Toast.makeText(this,"This file does not support changing speed.",Toast.LENGTH_SHORT).show()}
                dialog.dismiss()
            },LinearLayout.LayoutParams(0,dp(56),1f))
        };body.addView(row)
    }
    private fun showTracks()=panel(false) {body,dialog ->
        val mediaPlayer=player
        val tracks=runCatching {mediaPlayer?.trackInfo?.toList().orEmpty()}.getOrDefault(emptyList())
        val columns=LinearLayout(this)
        fun column(title:String,types:Set<Int>) {
            val list=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
            list.addView(actionLabel(title) {}.apply {textSize=20f;setTypeface(typeface,android.graphics.Typeface.BOLD);gravity=Gravity.START})
            val matches=tracks.withIndex().filter {it.value.trackType in types}
            if(title=="Subtitles") list.addView(actionLabel("Off") {
                types.forEach {type -> runCatching {mediaPlayer?.getSelectedTrack(type)?.takeIf {it>=0}?.let {mediaPlayer.deselectTrack(it)}}};dialog.dismiss()
            })
            matches.forEach { (index,track) ->
                val language=track.language.takeUnless {it.isNullOrBlank() || it=="und"}?.let {java.util.Locale.forLanguageTag(it).displayLanguage} ?: "Track ${index+1}"
                val selected=runCatching {mediaPlayer?.getSelectedTrack(track.trackType)==index}.getOrDefault(false)
                list.addView(actionLabel("${if(selected) "✓  " else ""}$language") {
                    runCatching {mediaPlayer?.selectTrack(index)}.onFailure {Toast.makeText(this,"This track could not be selected.",Toast.LENGTH_SHORT).show()};dialog.dismiss()
                })
            }
            if(matches.isEmpty()) list.addView(actionLabel(if(title=="Audio") "No alternate audio tracks" else "No embedded subtitles") {})
            columns.addView(ScrollView(this).apply {addView(list)},LinearLayout.LayoutParams(0,-1,1f))
        }
        column("Audio",setOf(android.media.MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_AUDIO))
        column("Subtitles",setOf(android.media.MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_SUBTITLE,android.media.MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_TIMEDTEXT))
        body.addView(columns,LinearLayout.LayoutParams(-1,0,1f))
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.content.ContextCompat.registerReceiver(this,receiver,IntentFilter(toggleAction),androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window,false)
        WindowInsetsControllerCompat(window,window.decorView).apply { hide(WindowInsetsCompat.Type.systemBars());systemBarsBehavior=WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE }
        val file=DownloadStore.get(this).file(key)
        if(!file.isFile) { Toast.makeText(this,"Downloaded video is missing. Download it again.",Toast.LENGTH_LONG).show();finish();return }
        val root=FrameLayout(this).apply { contentDescription="Offline player canvas";setBackgroundColor(android.graphics.Color.BLACK) }
        video=object:VideoView(this) {
            override fun onMeasure(widthMeasureSpec:Int,heightMeasureSpec:Int) {
                if(fillScreen && !isInPictureInPictureMode && sourceWidth>0 && sourceHeight>0) {
                    val w=View.MeasureSpec.getSize(widthMeasureSpec);val h=View.MeasureSpec.getSize(heightMeasureSpec)
                    val scale=maxOf(w.toFloat()/sourceWidth,h.toFloat()/sourceHeight)
                    setMeasuredDimension(kotlin.math.ceil(sourceWidth*scale).toInt(),kotlin.math.ceil(sourceHeight*scale).toInt())
                } else super.onMeasure(widthMeasureSpec,heightMeasureSpec)
            }
        }
        video.contentDescription="Offline video surface"
        root.addView(video,FrameLayout.LayoutParams(-1,-1,Gravity.CENTER))

        video.setOnPreparedListener { prepared -> player=prepared;sourceWidth=prepared.videoWidth;sourceHeight=prepared.videoHeight;prepared.setOnVideoSizeChangedListener {_,w,h->sourceWidth=w;sourceHeight=h;video.requestLayout()};video.requestLayout();video.seekTo(prefs.getInt(key,0));if(resume) video.start();updatePip() }
        video.setOnCompletionListener { prefs.edit().remove(key).apply();finish() }
        video.setOnErrorListener { _,_,_ -> Toast.makeText(this,"This downloaded file could not play.",Toast.LENGTH_LONG).show();finish();true }
        toolbar=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL;setPadding(dp(16),dp(8),dp(16),dp(8));background=android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,intArrayOf(0xB3000000.toInt(),0x00000000)) }
        val controlSize=(48*resources.displayMetrics.density).toInt()
        toolbar.addView(icon(R.drawable.player_close,"Exit offline player") { closing=true;updatePip();finish() },LinearLayout.LayoutParams(controlSize,controlSize))
        toolbar.addView(ImageView(this).apply {setImageResource(R.drawable.streamify_logo);scaleType=ImageView.ScaleType.FIT_CENTER;contentDescription="Streamify"},LinearLayout.LayoutParams(dp(34),dp(34)).apply {setMargins(dp(8),0,dp(8),0)})
        toolbar.addView(TextView(this).apply { text=DownloadStore.get(this@OfflinePlayerActivity).get(key)?.title ?: "Offline video";setTextColor(android.graphics.Color.WHITE);textSize=16f;gravity=Gravity.CENTER_VERTICAL;setPadding(16,0,16,0);maxLines=1 },LinearLayout.LayoutParams(0,controlSize,1f))
        toolbar.addView(icon(R.drawable.player_cast,"Cast to TV") {com.streamify.app.ui.openCastToTv(this)},LinearLayout.LayoutParams(controlSize,controlSize))
        toolbar.addView(icon(R.drawable.player_lock,"Lock screen") {locked=true;handler.removeCallbacks(hideControls);hideControls.run()},LinearLayout.LayoutParams(controlSize,controlSize))
        if(packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) toolbar.addView(icon(R.drawable.player_pip,"Picture-in-picture") { enterPip() },LinearLayout.LayoutParams(controlSize,controlSize))
        root.addView(toolbar,FrameLayout.LayoutParams(-1,-2,Gravity.TOP))
        transport=LinearLayout(this).apply { gravity=Gravity.CENTER;orientation=LinearLayout.HORIZONTAL }
        transport.addView(SkipControl(this,false,::skipBy),LinearLayout.LayoutParams(0,dp(64),1f))
        playButton=icon(R.drawable.pip_pause,"Pause") { if(video.isPlaying) video.pause() else video.start();resume=video.isPlaying;refreshControls();showControls() }
        transport.addView(playButton,LinearLayout.LayoutParams(0,dp(64),1f))
        transport.addView(SkipControl(this,true,::skipBy),LinearLayout.LayoutParams(0,dp(64),1f))
        root.addView(transport,FrameLayout.LayoutParams(dp(360),-2,Gravity.CENTER))
        timeline=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;setPadding(dp(24),dp(12),dp(24),dp(16));background=android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.BOTTOM_TOP,intArrayOf(0xB3000000.toInt(),0x00000000)) }
        time=TextView(this).apply {setTextColor(-1);textSize=12f;gravity=Gravity.END}
        seek=SeekBar(this).apply { progressTintList=android.content.res.ColorStateList.valueOf(0xFFE50914.toInt());thumbTintList=android.content.res.ColorStateList.valueOf(0xFFE50914.toInt());progressBackgroundTintList=android.content.res.ColorStateList.valueOf(0x66FFFFFF);max=1000 }
        seek.setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(bar:SeekBar) {scrubbing=true;handler.removeCallbacks(hideControls);seekPreview?.preview(video.duration.coerceAtLeast(0).toLong()*bar.progress/1000);seekPreview?.follow(bar,bar.progress/1000f)}
            override fun onStopTrackingTouch(bar:SeekBar) {video.seekTo((video.duration.toLong()*bar.progress/1000).toInt());scrubbing=false;seekPreview?.hidePreview();showControls()}
            override fun onProgressChanged(bar:SeekBar,value:Int,fromUser:Boolean) {if(fromUser && scrubbing) {seekPreview?.preview(video.duration.coerceAtLeast(0).toLong()*value/1000);seekPreview?.follow(bar,value/1000f)}}
        })
        val progressRow=LinearLayout(this).apply {gravity=Gravity.CENTER_VERTICAL}
        progressRow.addView(seek,LinearLayout.LayoutParams(0,dp(40),1f));progressRow.addView(time,LinearLayout.LayoutParams(dp(85),dp(40)))
        timeline.addView(progressRow)
        val actions=LinearLayout(this).apply {gravity=Gravity.CENTER}
        speedButton=actionLabel("Speed (1×)") { showSpeed() }
        actions.addView(speedButton);actions.addView(actionLabel("Audio & Subtitles") { showTracks() })
        timeline.addView(actions)
        root.addView(timeline,FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM))
        val brightnessBox=FrameLayout(this)
        brightnessBox.addView(TextView(this).apply {text="☼";setTextColor(-1);textSize=22f;gravity=Gravity.CENTER},FrameLayout.LayoutParams(dp(48),dp(40),Gravity.TOP))
        brightnessBox.addView(SeekBar(this).apply {
            contentDescription="Player brightness";max=100;progress=50;rotation=-90f;styleSideSlider(this)
            progressTintList=android.content.res.ColorStateList.valueOf(-1);thumbTintList=android.content.res.ColorStateList.valueOf(-1)
            setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar:SeekBar) {handler.removeCallbacks(hideControls)}
                override fun onStopTrackingTouch(bar:SeekBar) {showControls()}
                override fun onProgressChanged(bar:SeekBar,value:Int,fromUser:Boolean) {if(fromUser) window.attributes=window.attributes.apply {screenBrightness=(value/100f).coerceAtLeast(.02f)}}
            })
        },FrameLayout.LayoutParams(dp(150),dp(40),Gravity.CENTER).apply {topMargin=dp(8)})
        brightnessControl=brightnessBox
        root.addView(brightnessBox,FrameLayout.LayoutParams(dp(48),dp(180),Gravity.CENTER_VERTICAL or Gravity.START).apply {leftMargin=dp(16)})
        val audio=getSystemService(android.media.AudioManager::class.java)
        val volumeBox=FrameLayout(this)
        volumeBox.addView(ImageView(this).apply {setImageResource(android.R.drawable.ic_lock_silent_mode_off);imageTintList=android.content.res.ColorStateList.valueOf(-1);setPadding(dp(12),dp(8),dp(12),dp(8))},FrameLayout.LayoutParams(dp(48),dp(40),Gravity.TOP))
        volumeBox.addView(SeekBar(this).apply {
            contentDescription="Player volume";max=audio.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC);progress=audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC);rotation=-90f;styleSideSlider(this)
            progressTintList=android.content.res.ColorStateList.valueOf(-1);thumbTintList=android.content.res.ColorStateList.valueOf(-1)
            setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar:SeekBar) {handler.removeCallbacks(hideControls)}
                override fun onStopTrackingTouch(bar:SeekBar) {showControls()}
                override fun onProgressChanged(bar:SeekBar,value:Int,fromUser:Boolean) {if(fromUser) audio.setStreamVolume(android.media.AudioManager.STREAM_MUSIC,value,0)}
            })
        },FrameLayout.LayoutParams(dp(150),dp(40),Gravity.CENTER).apply {topMargin=dp(8)})
        volumeControl=volumeBox
        root.addView(volumeBox,FrameLayout.LayoutParams(dp(48),dp(180),Gravity.CENTER_VERTICAL or Gravity.END).apply {rightMargin=dp(16)})
        seekPreview=SeekPreview(this,file).also {root.addView(it,FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {bottomMargin=dp(100)})}
        volumeControlStream=android.media.AudioManager.STREAM_MUSIC
        gestureFeedback=TextView(this).apply {setTextColor(-1);textSize=26f;gravity=Gravity.CENTER;visibility=View.GONE;setShadowLayer(4f,0f,0f,android.graphics.Color.BLACK)}
        root.addView(gestureFeedback,FrameLayout.LayoutParams(dp(120),dp(80),Gravity.CENTER))
        unlockOverlay=FrameLayout(this).apply {
            setBackgroundColor(0x55000000);visibility=View.GONE;isClickable=true
            setOnClickListener {handler.removeCallbacks(hideUnlock);visibility=View.GONE}
        }
        val unlockButton=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(16),dp(8),dp(16),dp(8))
            contentDescription="Unlock screen";isClickable=true;isFocusable=true
            addView(ImageView(this@OfflinePlayerActivity).apply {setImageResource(R.drawable.player_lock)},LinearLayout.LayoutParams(dp(28),dp(28)))
            addView(TextView(this@OfflinePlayerActivity).apply {text="Tap to unlock";setTextColor(-1);textSize=13f;gravity=Gravity.CENTER;setPadding(0,dp(6),0,0)})
            setOnClickListener {locked=false;handler.removeCallbacks(hideUnlock);unlockOverlay.visibility=View.GONE;performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK);showControls()}
        }
        unlockOverlay.addView(unlockButton,FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {bottomMargin=dp(24)})
        root.addView(unlockOverlay,FrameLayout.LayoutParams(-1,-1))
        gestureDetector=android.view.GestureDetector(this,object:android.view.GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e:android.view.MotionEvent):Boolean {
                gestureBrightness=window.attributes.screenBrightness.takeIf {it>=0} ?: .5f
                gestureVolume=audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC);return true
            }
            override fun onSingleTapConfirmed(e:android.view.MotionEvent):Boolean {if(toolbar.visibility==View.VISIBLE) hideControls.run() else showControls();return true}
            override fun onDoubleTap(e:android.view.MotionEvent):Boolean {
                val delta=if(e.rawX<root.width/2f) -10 else 10
                suppressControls=true;skipBy(delta);suppressControls=false
                val now=android.os.SystemClock.elapsedRealtime()
                gestureTotal=if(now-gestureLast<900 && (gestureTotal>0)==(delta>0)) gestureTotal+delta else delta;gestureLast=now
                gestureFeedback.animate().cancel();gestureFeedback.text="${if(gestureTotal>0) "+" else ""}$gestureTotal"
                gestureFeedback.translationX=if(delta<0) -root.width*.22f else root.width*.22f
                gestureFeedback.visibility=View.VISIBLE;gestureFeedback.alpha=1f;gestureFeedback.scaleX=.85f;gestureFeedback.scaleY=.85f
                gestureFeedback.animate().scaleX(1f).scaleY(1f).alpha(0f).setStartDelay(0).setDuration(800).withEndAction {gestureFeedback.visibility=View.GONE}.start();return true
            }
            override fun onScroll(start:android.view.MotionEvent?,current:android.view.MotionEvent,dx:Float,dy:Float):Boolean {
                if(start==null || kotlin.math.abs(current.rawY-start.rawY)<kotlin.math.abs(current.rawX-start.rawX)) return false
                val change=(start.rawY-current.rawY)/root.height
                if(start.rawX<root.width*.18f) {
                    val value=(gestureBrightness+change*1.5f).coerceIn(.02f,1f)
                    window.attributes=window.attributes.apply {screenBrightness=value}
                    (brightnessBox.getChildAt(1) as SeekBar).progress=(value*100).toInt();return true
                }
                if(start.rawX>root.width*.82f) {
                    val maximum=audio.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                    audio.setStreamVolume(android.media.AudioManager.STREAM_MUSIC,(gestureVolume+change*maximum*1.5f).toInt().coerceIn(0,maximum),0);return true
                }
                return false
            }
        })
        scaleDetector=android.view.ScaleGestureDetector(this,object:android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector:android.view.ScaleGestureDetector):Boolean {pinchScale=1f;pinchChanged=false;return true}
            override fun onScale(detector:android.view.ScaleGestureDetector):Boolean {
                pinchScale*=detector.scaleFactor
                if(!pinchChanged && (pinchScale>1.12f || pinchScale<.88f)) {setVideoFill(pinchScale>1f);pinchChanged=true}
                return true
            }
        }).apply {isQuickScaleEnabled=false}
        val touch=View.OnTouchListener {_,event->gestureDetector.onTouchEvent(event);true}
        video.setOnTouchListener(touch);root.setOnTouchListener(touch)
        setContentView(root)
        video.setVideoPath(file.absolutePath)
        showControls();handler.post(update)
    }
    override fun onUserLeaveHint() { super.onUserLeaveHint();if(::video.isInitialized && video.isPlaying && !closing) enterPip() }
    override fun onPictureInPictureModeChanged(inPip: Boolean, configuration: Configuration) {
        super.onPictureInPictureModeChanged(inPip,configuration)
        video.requestLayout()
        if(inPip) {unlockOverlay.visibility=View.GONE;handler.removeCallbacks(hideUnlock); settingsDialog?.dismiss();hideControls.run() } else showControls()
    }
    override fun onPause() { if(::video.isInitialized) { resume=video.isPlaying;prefs.edit().putInt(key,video.currentPosition).apply() };super.onPause() }
    override fun onStop() { if(::video.isInitialized) video.pause();super.onStop() }
    override fun onResume() { super.onResume();if(::video.isInitialized && resume) video.start() }
    override fun onDestroy() { seekPreview?.close();settingsDialog?.dismiss();player=null;handler.removeCallbacksAndMessages(null);unregisterReceiver(receiver);if(::video.isInitialized) video.stopPlayback();super.onDestroy() }
}
