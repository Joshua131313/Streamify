package com.streamify.app.data

fun multiWatchAudioUpdate(audible: Boolean) = "window.postMessage({streamifyAudio: true, audible: $audible}, '*');"
fun multiWatchAudioScript(audible: Boolean) = """
(() => {
  if (window.__streamifyAudioInstalled) return;
  window.__streamifyAudioInstalled = true;
  let audible = $audible;
  const proto = HTMLMediaElement.prototype;
  const muted = Object.getOwnPropertyDescriptor(proto, 'muted');
  Object.defineProperty(proto, 'muted', {configurable:true, get: muted.get,
    set(value) { muted.set.call(this, audible ? value : true); }});
  const apply = () => document.querySelectorAll('video,audio').forEach(v => {
    muted.set.call(v, !audible);
  });
  window.addEventListener('message', e => {
    if (e.source !== window && e.source !== parent) return;
    if (e.data?.streamifyAudio !== true || typeof e.data.audible !== 'boolean') return;
    audible = e.data.audible; apply();
    for (let i=0; i<frames.length; i++) frames[i].postMessage(e.data, '*');
  });
  document.addEventListener('play', apply, true);
  document.addEventListener('volumechange', () => { if (!audible) apply(); }, true);
  new MutationObserver(apply).observe(document, {childList:true, subtree:true});
  apply();
})();
""".trimIndent()
