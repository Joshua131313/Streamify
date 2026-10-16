package com.streamify.app.data

/** Uniform crop-to-fill: keep aspect ratio and center the visible video rectangle. */
data class VideoFill(val scale: Float, val offsetX: Float, val offsetY: Float)
fun videoFill(viewWidth: Float, viewHeight: Float, left: Float, top: Float, width: Float, height: Float): VideoFill? {
    if (listOf(viewWidth, viewHeight, left, top, width, height).any { !it.isFinite() } ||
        viewWidth <= 0 || viewHeight <= 0 || width <= 0 || height <= 0) return null
    val scale = maxOf(viewWidth / width, viewHeight / height).coerceAtLeast(1f)
    // Refuse tiny thumbnails or nonsensical provider geometry.
    if (scale > 4f) return null
    return VideoFill(scale, (viewWidth / 2 - left - width / 2) * scale, (viewHeight / 2 - top - height / 2) * scale)
}

// Cross-origin frames are deliberately left alone; no provider security settings are changed.
val videoGeometryScript = """
(() => {
  const candidates = [];
  function scan(win, x, y) {
    try {
      win.document.querySelectorAll('video').forEach(v => {
        const r = v.getBoundingClientRect();
        if (v.videoWidth > 0 && v.videoHeight > 0 && r.width > 0 && r.height > 0) {
          let w = r.width, h = r.height;
          const fit = win.getComputedStyle(v).objectFit;
          if (fit !== 'cover' && fit !== 'fill') {
            const factor = Math.min(w / v.videoWidth, h / v.videoHeight);
            w = v.videoWidth * factor; h = v.videoHeight * factor;
          }
          candidates.push({left:x+r.left+(r.width-w)/2, top:y+r.top+(r.height-h)/2,
            width:w, height:h, aspect:v.videoWidth/v.videoHeight});
        }
      });
      win.document.querySelectorAll('iframe').forEach(f => {
        const r = f.getBoundingClientRect(); scan(f.contentWindow, x+r.left, y+r.top);
      });
    } catch (_) {}
  }
  scan(window, 0, 0);
  candidates.sort((a,b) => b.width*b.height-a.width*a.height);
  return candidates.length ? {...candidates[0], viewportWidth:innerWidth, viewportHeight:innerHeight} : null;
})();
""".trimIndent()
