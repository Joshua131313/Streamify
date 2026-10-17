package com.streamify.app.downloads

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Conflates scrub requests: at most one decode runs, and only the latest result is shown. */
class SeekPreview(context:Context, private val file:File): LinearLayout(context) {
    private val executor=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    private val pending=AtomicLong(-1)
    private val running=AtomicBoolean(false)
    private val closed=AtomicBoolean(false)
    private var latest=-1L
    private var retriever:MediaMetadataRetriever?=null
    private val cache=object:LruCache<Long,Bitmap>(12) {}
    private val image=ImageView(context).apply {scaleType=ImageView.ScaleType.FIT_CENTER}
    private val label=TextView(context).apply {setTextColor(-1);textSize=12f;gravity=Gravity.CENTER}
    init {
        orientation=VERTICAL;setBackgroundColor(0xE6222222.toInt());visibility=GONE
        val density=resources.displayMetrics.density
        addView(image,LayoutParams((160*density).toInt(),(90*density).toInt()))
        addView(label,LayoutParams(-1,(24*density).toInt()))
        contentDescription="Seek preview"
    }
    fun preview(ms:Long) {
        if(closed.get()) return
        visibility=VISIBLE
        val seconds=ms/1000
        label.text=if(seconds>=3600) "%d:%02d:%02d".format(seconds/3600,seconds/60%60,seconds%60) else "%d:%02d".format(seconds/60,seconds%60)
        latest=seconds;pending.set(seconds);drain()
    }
    @Synchronized private fun drain() {
        if(closed.get() || !running.compareAndSet(false,true)) return
        executor.execute {
            try {
                while(!closed.get()) {
                    val seconds=pending.getAndSet(-1)
                    if(seconds<0) break
                    val frame=runCatching {
                        cache.get(seconds) ?: run {
                            val reader=retriever ?: MediaMetadataRetriever().also {retriever=it;it.setDataSource(file.absolutePath)}
                            (if(android.os.Build.VERSION.SDK_INT>=27) reader.getScaledFrameAtTime(seconds*1000000,MediaMetadataRetriever.OPTION_CLOSEST_SYNC,320,180)
                            else reader.getFrameAtTime(seconds*1000000,MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { full ->
                                val scaled=Bitmap.createScaledBitmap(full,320,180,true);if(scaled!==full) full.recycle();scaled
                            })?.also {cache.put(seconds,it)}
                        }
                    }.getOrNull()
                    main.post {if(!closed.get() && latest==seconds && visibility==VISIBLE) image.setImageBitmap(frame)}
                }
            } finally {running.set(false);if(!closed.get() && pending.get()>=0) drain()}
        }
    }
    fun hidePreview() {visibility=GONE;latest=-1;pending.set(-1)}
    @Synchronized fun close() {
        if(!closed.compareAndSet(false,true)) return
        hidePreview();main.removeCallbacksAndMessages(null)
        executor.execute {runCatching {retriever?.release()};retriever=null;cache.evictAll()}
        executor.shutdown();image.setImageDrawable(null)
    }
}
