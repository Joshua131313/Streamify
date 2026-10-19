package com.streamify.app.data

/** No writes on timeupdate ticks: local checkpoints every 5s, cloud every 60s plus changed lifecycle checkpoints. */
class PlaybackCheckpoint(private val initial: History, private val save: (History, Boolean) -> Unit,
                         private val clock: () -> Long = System::currentTimeMillis) {
    private var latest: History? = null
    private var localAt = 0L
    private var cloudAt = 0L
    private var cloudPosition = -1.0
    private var localPosition = -1.0
    fun sample(position: Double, duration: Double, force: Boolean = false) {
        if (!position.isFinite() || !duration.isFinite() || duration !in 60.0..43200.0 || position < 0 || position > duration + 5) return
        if (position < 5 && latest == null) return // Loading at zero must not erase an existing resume point.
        latest = initial.copy(positionSeconds = position.coerceAtMost(duration), durationSeconds = duration, watchedAt = clock())
        checkpoint(force)
    }
    fun flush() = checkpoint(true)
    private fun checkpoint(force: Boolean) {
        val entry = latest ?: return
        val now = clock()
        val cloud = kotlin.math.abs(entry.positionSeconds - cloudPosition) >= 2 &&
            (cloudAt == 0L || now - cloudAt >= 60_000 || force)
        val local = kotlin.math.abs(entry.positionSeconds - localPosition) >= 1 && (force || now - localAt >= 5_000)
        if (!cloud && !local) return
        save(entry, cloud)
        localAt = now; localPosition = entry.positionSeconds
        if (cloud) { cloudAt = now; cloudPosition = entry.positionSeconds }
    }
}

/** Installed only in this provider's exact HTTPS origin, never an unrestricted native bridge. */
fun playbackProgressScript(resumeSeconds: Double): String = """
(function(){
  if(window.__streamifyProgress) return;
  window.__streamifyProgress=true;
  var resume=${resumeSeconds.takeIf { it.isFinite() && it >= 0 } ?: 0.0};
  var bound=new WeakSet(), restored=new WeakSet(), last=0;
  function valid(v){return Number.isFinite(v.duration)&&v.duration>=60&&v.duration<=43200&&!v.closest('.ad-container,[data-ad],.vast-ad');}
  function restore(v){
    if(!valid(v)||restored.has(v))return;
    if(resume>=5 && resume<v.duration*.95){
      try {v.currentTime=Math.min(resume,v.duration-1); if(Math.abs(v.currentTime-resume)>2)return;}catch(e){return;}
    }
    restored.add(v);
  }
  function emit(v,force){
    if(!valid(v)||!restored.has(v)||(!force&&Date.now()-last<1000))return;
    if(v.getBoundingClientRect().width<100)return;
    last=Date.now();
    try{StreamifyProgress.postMessage(JSON.stringify({position:v.ended?v.duration:v.currentTime,duration:v.duration,force:!!force,ended:!!v.ended}));}catch(e){}
  }
  function bind(){document.querySelectorAll('video').forEach(function(v){
    if(bound.has(v))return;bound.add(v);
    ['loadedmetadata','canplay'].forEach(function(e){v.addEventListener(e,function(){restore(v);});});
    v.addEventListener('timeupdate',function(){restore(v);if(!v.paused)emit(v,false);});
    ['pause','ended','seeked'].forEach(function(e){v.addEventListener(e,function(){emit(v,e!=='seeked');});});
    restore(v);
  });}
  new MutationObserver(bind).observe(document,{childList:true,subtree:true});
  document.addEventListener('DOMContentLoaded',bind);bind();
  window.addEventListener('pagehide',function(){document.querySelectorAll('video').forEach(function(v){emit(v,true);});});
})();
""".trimIndent()
