package com.streamify.app.data

fun playerDocument(url: String): String {
    require(httpsUrl(url))
    val escaped = url.replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;").replace(">", "&gt;")
    return """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100vw;height:100vh;background:#000;overflow:hidden}iframe{position:fixed;inset:0;display:block;width:100vw;height:100vh;border:0}</style></head><body><iframe src="$escaped" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>"""
}

// WebView does not implement ScreenOrientation.lock on all Android versions.
// Some embed players abort initialization on the rejected promise. Retain real
// locks when supported and degrade to the current orientation only when unsupported.
const val orientationCompatibilityScript = """(() => {
  const orientation = screen.orientation;
  if (!orientation || typeof orientation.lock !== 'function') return;
  const original = orientation.lock.bind(orientation);
  orientation.lock = async (...args) => {
    try { return await original(...args); }
    catch (error) { if (error.name !== 'NotSupportedError') throw error; }
  };
})();"""

// This provider treats failure of an invalid PDF object as evidence of iframe sandboxing.
// WebView has no PDF plugin: ignore only this exact probe on a top-level provider page.
const val sportsPdfCompatibilityScript = """(() => {
  if (self !== top || location.hostname !== 'embed.st') return;
  window.addEventListener('error', event => {
    const object = event.target;
    if (object instanceof HTMLObjectElement && object.id === 'sandDetect' &&
        object.getAttribute('data') === 'data:application/pdf;base64,aG1t') {
      event.stopImmediatePropagation();
      event.preventDefault();
    }
  }, true);
})();"""
