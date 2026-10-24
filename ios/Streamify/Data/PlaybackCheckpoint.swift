import Foundation

struct PlaybackIdentity: Equatable {
    let mediaKey: String
    let season: Int
    let episode: Int

    init(mediaKey: String, season: Int, episode: Int) {
        self.mediaKey = mediaKey; self.season = max(1, season); self.episode = max(1, episode)
    }

    func resumeSeconds(from entry: WatchEntry?) -> Double {
        guard let entry, entry.media.key == mediaKey, entry.season == season, entry.episode == episode,
              let sample = PlaybackSample(position: entry.positionSeconds, duration: entry.durationSeconds),
              sample.position >= 5, sample.position < sample.duration * 0.95 else { return 0 }
        return sample.position
    }
}

struct PlaybackSample: Equatable {
    let position: Double
    let duration: Double

    init?(position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, (60...43_200).contains(duration),
              position >= 0, position <= duration + 5 else { return nil }
        self.position = min(position, duration); self.duration = duration
    }
}

/// Local writes are bounded even when a provider repeatedly sends forced samples.
struct PlaybackCheckpoint {
    private var latest: PlaybackSample?
    private var saved: PlaybackSample?
    private var savedAt: TimeInterval?

    mutating func sample(position: Double, duration: Double, now: TimeInterval, force: Bool = false) -> PlaybackSample? {
        guard let sample = PlaybackSample(position: position, duration: duration),
              sample.position >= 5 || latest != nil else { return nil }
        latest = sample
        return flush(now: now, force: force)
    }

    mutating func flush(now: TimeInterval, force: Bool = true) -> PlaybackSample? {
        guard let latest, now.isFinite else { return nil }
        if let saved, let savedAt {
            guard abs(latest.position - saved.position) >= 1 || abs(latest.duration - saved.duration) >= 1,
                  now - savedAt >= (force ? 1 : 5) else { return nil }
        }
        saved = latest; savedAt = now
        return latest
    }
}

enum PlaybackProgressScript {
    static func document(token: String, resumeSeconds: Double) -> String {
        let resume = resumeSeconds.isFinite && resumeSeconds >= 5 ? resumeSeconds : 0
        let encodedToken = (try? JSONEncoder().encode(token)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function(){
          if(location.protocol!=='https:')return;
          var token=\(encodedToken),resume=\(resume),bound=new WeakSet(),restored=new WeakSet(),last=0;
          function valid(v){
            var r=v.getBoundingClientRect();
            return Number.isFinite(v.duration)&&v.duration>=60&&v.duration<=43200&&r.width>=100&&r.height>=50&&
              !v.closest('.ad-container,[data-ad],.vast-ad,.video-ads,.ad-showing,[class*="vpaid"]')&&
              !/(?:\\/|[?&])(?:ads?|vast|vpaid)(?:[/?=._-]|$)/i.test(location.pathname+location.search);
          }
          function restore(v){
            if(!valid(v)||restored.has(v))return;
            if(resume>=5&&resume<v.duration*.95){
              try{v.currentTime=Math.min(resume,v.duration-1);if(Math.abs(v.currentTime-resume)>2)return;}catch(e){return;}
            }
            restored.add(v);
          }
          function emit(v,force){
            if(!valid(v)||!restored.has(v)||(!force&&Date.now()-last<1000))return;
            var p=v.ended?v.duration:v.currentTime;if(!Number.isFinite(p))return;last=Date.now();
            try{window.webkit.messageHandlers.streamifyProgress.postMessage({token:token,position:p,duration:v.duration,force:!!force});}catch(e){}
          }
          function bind(){document.querySelectorAll('video').forEach(function(v){
            if(bound.has(v))return;bound.add(v);
            ['loadedmetadata','canplay'].forEach(function(e){v.addEventListener(e,function(){restore(v);});});
            v.addEventListener('timeupdate',function(){restore(v);if(!v.paused)emit(v,false);});
            ['pause','ended','seeked'].forEach(function(e){v.addEventListener(e,function(){emit(v,e!=='seeked');});});
            restore(v);
          });}
          window.__streamifyFlushProgress=function(){document.querySelectorAll('video').forEach(function(v){emit(v,true);});};
          new MutationObserver(bind).observe(document,{childList:true,subtree:true});
          document.addEventListener('DOMContentLoaded',bind);bind();
          window.addEventListener('pagehide',window.__streamifyFlushProgress);
          document.addEventListener('visibilitychange',function(){if(document.hidden)window.__streamifyFlushProgress();});
        })();
        """
    }
}
