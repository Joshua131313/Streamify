package com.streamify.app.downloads

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.View
import android.view.HapticFeedbackConstants
import kotlin.math.min

/** A native seek control with a cumulative, fading seek acknowledgement. */
class SkipControl(context: Context, private val forward: Boolean, private val skip: (Int) -> Unit) : View(context) {
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    private var animator: ValueAnimator?=null
    private var feedback=0f
    private var accumulated=0
    init {
        contentDescription=if(forward) "Forward 10 seconds" else "Rewind 10 seconds"
        isClickable=true;isFocusable=true
        setOnClickListener {
            val delta=if(forward) 10 else -10
            accumulated=if(feedback>0f) accumulated+delta else delta
            skip(delta);performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            animator?.cancel()
            animator=ValueAnimator.ofFloat(1f,0f).apply {duration=850;addUpdateListener {feedback=it.animatedValue as Float;invalidate()};start()}
            announceForAccessibility("${if(accumulated>0) "+" else ""}$accumulated seconds")
        }
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val unit=min(width,height)/80f;val cx=width/2f;val cy=height/2f
        paint.style=Paint.Style.FILL;paint.color=Color.WHITE;paint.alpha=(feedback*28).toInt()
        canvas.drawCircle(cx,cy,unit*(33+8*(1-feedback)),paint)
        canvas.save();canvas.translate(cx,cy);if(!forward) canvas.scale(-1f,1f)
        canvas.rotate(feedback*22)
        paint.alpha=255;paint.style=Paint.Style.STROKE;paint.strokeWidth=unit*2;paint.strokeCap=Paint.Cap.ROUND;paint.strokeJoin=Paint.Join.ROUND
        canvas.drawArc(RectF(-23*unit,-23*unit,23*unit,23*unit),-55f,305f,false,paint)
        val arrow=Path().apply {moveTo(13.19f*unit,-27.84f*unit);lineTo(13.19f*unit,-18.84f*unit);lineTo(4.19f*unit,-18.84f*unit)}
        canvas.drawPath(arrow,paint);canvas.restore()
        paint.style=Paint.Style.FILL;paint.textAlign=Paint.Align.CENTER;paint.textSize=unit*18;paint.typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL)
        canvas.drawText(if(feedback>0f) "${if(accumulated>0) "+" else ""}$accumulated" else "10",cx,cy+6*unit,paint)
    }
    override fun onDetachedFromWindow() {animator?.cancel();super.onDetachedFromWindow()}
}
