package com.streamify.app.downloads

import android.app.Activity
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

/** No credit markers are supplied by our sources. This is an offer, never an early automatic skip. */
internal fun episodeEndOffer(position:Double,duration:Double):Boolean =
    position.isFinite() && duration.isFinite() && duration>=300 && position>=duration-(duration*.05).coerceIn(30.0,90.0)

class EpisodeEndOverlay(private val activity:Activity,private val play:()->Unit) {
    private val density=activity.resources.displayMetrics.density
    private fun dp(n:Int)=(n*density).toInt()
    private val host=activity.window.decorView as ViewGroup
    private var dismissed=false
    private var launched=false
    private var elapsed=0L
    private var previous=0L
    private var endedBefore=false
    private var fill=0f
    private var animator:android.animation.ValueAnimator?=null
    private var fillTarget=0f
    private val row=LinearLayout(activity).apply {gravity=Gravity.CENTER_VERTICAL;visibility=View.GONE}
    private val next=object:TextView(activity) {
        override fun onDraw(canvas:android.graphics.Canvas) {
            if(fill>0) {val paint=android.graphics.Paint().apply {color=Color.WHITE};canvas.drawRect(0f,0f,width*fill,height.toFloat(),paint)}
            super.onDraw(canvas)
        }
    }
    init {
        fun style(view:TextView,label:String,primary:Boolean) {
            view.text=label;view.textSize=16f;view.gravity=Gravity.CENTER;view.setTextColor(if(primary) Color.BLACK else Color.WHITE)
            view.setPadding(dp(18),0,dp(18),0)
            view.background=android.graphics.drawable.GradientDrawable().apply {setColor(if(primary) 0xFFDADADA.toInt() else 0xFF333333.toInt());cornerRadius=dp(5).toFloat()}
            view.clipToOutline=true
        }
        val credits=TextView(activity);style(credits,"Watch Credits",false)
        credits.setOnClickListener {dismissed=true;row.visibility=View.GONE}
        row.addView(credits,LinearLayout.LayoutParams(-2,dp(48)))
        style(next,"▶  Next Episode",true);next.contentDescription="Play next episode"
        next.setOnClickListener {launch()}
        row.addView(next,LinearLayout.LayoutParams(-2,dp(48)).apply {marginStart=dp(10)})
        host.addView(row,FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM or Gravity.END).apply {setMargins(dp(20),0,dp(28),dp(28))})
    }
    private fun launch() {if(!launched) {launched=true;row.visibility=View.GONE;play()}}
    fun update(position:Double,duration:Double,ended:Boolean,hidden:Boolean,controls:Boolean=false) {
        val now=android.os.SystemClock.elapsedRealtime()
        val delta=if(previous==0L) 0L else (now-previous).coerceAtMost(1500L)
        previous=now
        if(!ended && !episodeEndOffer(position,duration)) {dismissed=false;elapsed=0;endedBefore=false}
        val visible=!hidden && !dismissed && !launched && (ended || episodeEndOffer(position,duration))
        row.visibility=if(visible) View.VISIBLE else View.GONE
        (row.layoutParams as FrameLayout.LayoutParams).bottomMargin=dp(if(controls) 118 else 28)
        row.requestLayout();row.bringToFront()
        if(visible && ended && endedBefore && (activity as? LifecycleOwner)?.lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED)==true) elapsed+=delta
        endedBefore=ended
        next.contentDescription=if(ended && visible) "Next episode playing in ${((10000-elapsed).coerceAtLeast(0)+999)/1000} seconds" else "Play next episode"
        val target=(elapsed/10000f).coerceIn(0f,1f)
        if(target!=fillTarget) {
            fillTarget=target;animator?.cancel()
            animator=android.animation.ValueAnimator.ofFloat(fill,target).apply {this.duration=250L;addUpdateListener {fill=it.animatedValue as Float;next.invalidate()};start()}
        }
        if(visible && ended && elapsed>=10000) launch()
    }
    fun close() {animator?.cancel();host.removeView(row)}
}
