// A Watch action authorizes one start attempt for each visible sports video.
// Never click provider overlays, change the source, mute, or undo a later pause.
(() => {
  const attempted = new WeakSet();
  const watched = new WeakSet();
  function scan() {
    if (document.hidden) return;
    const videos = Array.from(document.querySelectorAll('video'));
    for (const video of videos) {
      if (!watched.has(video)) {
        watched.add(video);
        for (const event of ['loadedmetadata', 'canplay', 'resize']) video.addEventListener(event, scan);
        video.addEventListener('play', () => attempted.add(video));
        video.addEventListener('pause', () => { if (video.currentTime > 0) attempted.add(video); });
      }
      if (!video.paused) attempted.add(video);
    }
    const candidates = videos.filter(video => video.isConnected && video.readyState >= 2 && !video.ended)
      .map(video => ({video, area: video.getBoundingClientRect().width * video.getBoundingClientRect().height}))
      .filter(item => item.area > 3200).sort((a, b) => b.area - a.area);
    const video = candidates[0]?.video;
    if (!video || attempted.has(video)) return;
    attempted.add(video);
    try { const started = video.play(); if (started) started.catch(() => {}); } catch (_) { /* Provider may require a tap. */ }
  }
  new MutationObserver(scan).observe(document, {childList: true, subtree: true});
  document.addEventListener('DOMContentLoaded', scan);
  document.addEventListener('visibilitychange', scan);
  scan(); setInterval(scan, 1000);
})();
