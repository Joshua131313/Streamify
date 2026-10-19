package com.streamify.app.downloads

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.view.Gravity
import android.widget.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Countdown runs only while the player is visible; movies always require a tap. */
fun Activity.playbackEnding(title:String,episode:Boolean,play:(()->Unit)?,replay:()->Unit):Dialog {
    val dialog=Dialog(this)
    val density=resources.displayMetrics.density
    fun dp(n:Int)=(n*density).toInt()
    val body=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(32),dp(24),dp(32),dp(24));setBackgroundColor(0xFF181818.toInt())}
    body.addView(TextView(this).apply {text=if(play==null) "You've finished watching" else if(episode) "Up next" else "Recommended next";textSize=22f;setTextColor(Color.WHITE)})
    body.addView(TextView(this).apply {text=title;textSize=17f;setTextColor(Color.WHITE);setPadding(0,dp(16),0,dp(16))})
    var countdown=episode && play!=null
    var seconds=10
    fun start() {countdown=false;dialog.dismiss();play?.invoke()}
    val watch=Button(this).apply {text=if(episode) "Next episode · 10s" else "Watch movie";setOnClickListener {start()}}
    if(play!=null) body.addView(watch)
    if(countdown) body.addView(Button(this).apply {text="Cancel autoplay";setOnClickListener {countdown=false;watch.text="Play next episode";visibility=android.view.View.GONE}})
    body.addView(Button(this).apply {text="Watch again";setOnClickListener {dialog.dismiss();replay()}})
    body.addView(Button(this).apply {text="Back";setOnClickListener {dialog.dismiss();finish()}})
    for(index in 0 until body.childCount) {
        (body.getChildAt(index) as? Button)?.apply {
            isAllCaps=false;textSize=16f;setTextColor(if(this===watch) Color.BLACK else Color.WHITE)
            val buttonColor=if(this===watch) Color.WHITE else 0xFF333333.toInt()
            background=android.graphics.drawable.GradientDrawable().apply {setColor(buttonColor);cornerRadius=dp(28).toFloat()}
            layoutParams=LinearLayout.LayoutParams(-1,dp(52)).apply {topMargin=dp(10)}
        }
    }
    dialog.setContentView(body);dialog.setOnCancelListener {finish()};dialog.show()
    dialog.window?.apply {setBackgroundDrawableResource(android.R.color.transparent);setLayout(minOf(resources.displayMetrics.widthPixels-dp(48),dp(480)),-2);setGravity(Gravity.CENTER)}
    val owner=this as? LifecycleOwner
    owner?.lifecycleScope?.launch {
        while(dialog.isShowing && countdown && seconds>0) {
            delay(1000)
            if(countdown && owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) && !isInPictureInPictureMode) {
                seconds--;watch.text="Next episode · ${seconds}s"
                if(seconds==0 && countdown && dialog.isShowing) start()
            }
        }
    }
    return dialog
}
