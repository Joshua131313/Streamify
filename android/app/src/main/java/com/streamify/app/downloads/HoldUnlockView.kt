package com.streamify.app.downloads

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View
import android.view.HapticFeedbackConstants

/** A cancellable one-second hold followed by the shackle opening. */
class HoldUnlockView(context:Context,private val onHold:()->Unit,private val onCancel:()->Unit,private val onUnlock:()->Unit):View(context) {
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    private var animator:ValueAnimator?=null
    private var progress=0f
    private var opening=0f
    private var completing=false
    init {contentDescription="Hold to unlock screen";isClickable=true;isFocusable=true;setOnClickListener {startHold()}}
    private fun startHold() {
        if(completing || animator?.isRunning==true) return
        onHold();progress=0f;opening=0f
        animator=ValueAnimator.ofFloat(0f,1f).apply {
            duration=1000;interpolator=android.view.animation.LinearInterpolator()
            addUpdateListener {
                progress=it.animatedValue as Float;invalidate()
                if(progress>=1f && !completing) {
                    completing=true;performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    post {if(visibility==VISIBLE && isShown) openLock() else cancelHold()}
                }
            };start()
        }
    }
    private fun openLock() {
        animator=ValueAnimator.ofFloat(0f,1f).apply {
            duration=280
            addUpdateListener {opening=it.animatedValue as Float;invalidate();if(opening>=1f) {completing=false;onUnlock()}}
            start()
        }
    }
    private fun cancelHold() {animator?.cancel();animator=null;progress=0f;opening=0f;completing=false;invalidate();onCancel()}
    override fun onTouchEvent(e:MotionEvent):Boolean {
        when(e.actionMasked) {
            MotionEvent.ACTION_DOWN->startHold()
            MotionEvent.ACTION_MOVE->if(!completing && (e.x<0 || e.x>width || e.y<0 || e.y>height)) cancelHold()
            MotionEvent.ACTION_UP,MotionEvent.ACTION_CANCEL->if(!completing) cancelHold()
        };return true
    }
    override fun onDraw(canvas:Canvas) {
        val d=resources.displayMetrics.density;val x=width/2f;val y=34*d
        paint.style=Paint.Style.STROKE;paint.strokeWidth=2*d;paint.strokeCap=Paint.Cap.ROUND;paint.color=Color.WHITE
        paint.alpha=55;canvas.drawCircle(x,y,29*d,paint);paint.alpha=255
        canvas.drawArc(RectF(x-29*d,y-29*d,x+29*d,y+29*d),-90f,progress*360,false,paint)
        canvas.drawRoundRect(RectF(x-10*d,y-1*d,x+10*d,y+15*d),2*d,2*d,paint)
        canvas.save();canvas.rotate(-32*opening,x+7*d,y-1*d)
        val shackle=Path().apply {moveTo(x-7*d,y-1*d);lineTo(x-7*d,y-9*d);cubicTo(x-7*d,y-20*d,x+7*d,y-20*d,x+7*d,y-9*d);lineTo(x+7*d,y-1*d)}
        canvas.drawPath(shackle,paint);canvas.restore()
        canvas.drawLine(x,y+5*d,x,y+9*d,paint)
        paint.style=Paint.Style.FILL;paint.textSize=13*d;paint.textAlign=Paint.Align.CENTER
        canvas.drawText(if(completing) "Unlocking" else "Hold to unlock",x,83*d,paint)
    }
    override fun onVisibilityChanged(changedView:View,visibility:Int) {super.onVisibilityChanged(changedView,visibility);if(visibility!=VISIBLE) {animator?.cancel();animator=null;progress=0f;opening=0f;completing=false}}
    override fun onDetachedFromWindow() {animator?.cancel();super.onDetachedFromWindow()}
}
