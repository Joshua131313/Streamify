import Foundation
import WebKit
import UIKit

/// Uses Apple's HTMLVideoElement presentation-mode API in the actual frame
/// containing the video, including cross-origin provider iframes.
@MainActor
final class SportsWebPiPBridge: NSObject, WKScriptMessageHandler {
    private static let name = "streamifySportsPiP"
    private static let world = WKContentWorld.world(name: "StreamifySportsPiP")
    private weak var webView: WKWebView?
    private weak var pictureInPicture: SportsSystemPiP?
    private var owner = UUID()
    private var frames: [String: VideoFrame] = [:]
    private var activeVideoID: String?
    private var fullscreenVideoIDs = Set<String>()
    private var refreshingFrames = Set<String>()
    private var elementFullscreen = false
    private var fullscreenObservation: NSKeyValueObservation?
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private struct VideoFrame {
        let frame: WKFrameInfo
        let capable: Bool
        let playing: Bool
        let score: Double
        let seenAt: TimeInterval
    }

    init(webView: WKWebView, pictureInPicture: SportsSystemPiP) {
        self.webView = webView; self.pictureInPicture = pictureInPicture
        super.init()
        webView.configuration.userContentController.add(self, contentWorld: Self.world, name: Self.name)
        // During element fullscreen WebKit moves the WKWebView into a separate
        // window, leaving a placeholder behind. DOM PiP and native fullscreen
        // callbacks can arrive in either order on foreground restoration.
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.webView === observed else { return }
                self.elementFullscreen = observed.fullscreenState != .notInFullscreen
                self.publishFullscreen()
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshPresentation() }
            }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.startAutomaticPiP() }
            }
    }
    func begin() {
        pictureInPicture?.detach(owner: owner)
        owner = UUID(); frames.removeAll(); activeVideoID = nil; fullscreenVideoIDs.removeAll(); refreshingFrames.removeAll()
        let requestOwner = owner
        pictureInPicture?.attach(owner: owner, capability: .checking,
            request: { [weak self] in guard let self, self.owner == requestOwner else { return }; self.request() },
            stop: { [weak self] in guard let self, self.owner == requestOwner else { return }; self.stop() })
        elementFullscreen = webView.map { $0.fullscreenState != .notInFullscreen } ?? false
        publishFullscreen()
        let script = WKUserScript(source: Self.script(token: owner.uuidString), injectionTime: .atDocumentEnd,
            forMainFrameOnly: false, in: Self.world)
        webView?.configuration.userContentController.addUserScript(script)
    }
    func loaded() { refreshCapability() }
    func terminated() {
        frames.removeAll(); activeVideoID = nil; fullscreenVideoIDs.removeAll(); refreshingFrames.removeAll(); elementFullscreen = false
        publishFullscreen()
        // A dead web content process cannot send a final DOM mode event.
        // Return to the retained error/reload screen instead of trapping it offscreen.
        pictureInPicture?.didStop(owner: owner, restoring: true)
        pictureInPicture?.reportCapability(.unavailable, owner: owner)
    }
    func finish() {
        fullscreenObservation?.invalidate(); fullscreenObservation = nil
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        foregroundObserver = nil
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        backgroundObserver = nil
        pictureInPicture?.detach(owner: owner)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.name, contentWorld: Self.world)
        frames.removeAll(); activeVideoID = nil; fullscreenVideoIDs.removeAll(); refreshingFrames.removeAll(); owner = UUID()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.name, message.webView === webView,
              message.frameInfo.securityOrigin.`protocol` == "https",
              let body = message.body as? [String: Any], body["token"] as? String == owner.uuidString else { return }
        if body["kind"] as? String == "error" {
            pictureInPicture?.failed("This provider could not enter iOS Picture in Picture. Try its video controls or another source.", owner: owner)
            return
        }
        guard let id = body["id"] as? String, id.count < 160 else { refreshCapability(); return }
        let area = (body["area"] as? NSNumber)?.doubleValue ?? 0
        let playing = body["paused"] as? Bool == false
        let active = body["active"] as? Bool == true
        let fullscreen = body["fullscreen"] as? Bool == true
        if fullscreen { fullscreenVideoIDs.insert(id) } else { fullscreenVideoIDs.remove(id) }
        let capable = body["capable"] as? Bool == true && area.isFinite && area > 3200
        frames[id] = VideoFrame(frame: message.frameInfo, capable: capable, playing: playing,
            score: min(max(0, area), 10_000_000) + (playing ? 100_000_000 : 0), seenAt: ProcessInfo.processInfo.systemUptime)
        refreshCapability()
        if active {
            activeVideoID = id
            pictureInPicture?.didStart(owner: owner)
            publishFullscreen()
        } else {
            publishFullscreen()
            if activeVideoID == id {
                activeVideoID = nil
                // Restoring leaves the video playing inline. Closing the system
                // window pauses it; explicit app Restore also marks its intent.
                // A foreground snapshot is authoritative too: a mode event/timer
                // may have been suspended while iOS moved the video out of PiP.
                pictureInPicture?.didStop(owner: owner, restoring: playing || fullscreen || elementFullscreen)
            }
        }
    }
    private func publishFullscreen() {
        pictureInPicture?.reportProviderFullscreen(elementFullscreen || !fullscreenVideoIDs.isEmpty, owner: owner)
    }
    static func shouldStartAutomaticPiP(size: CGSize, playing: Bool, capable: Bool, age: TimeInterval,
        providerFullscreen: Bool, active: Bool) -> Bool {
        size.width > size.height && playing && capable && age >= 0 && age < 3 && !providerFullscreen && !active
    }
    private func startAutomaticPiP() {
        guard let webView, let pictureInPicture else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard frames.values.contains(where: { Self.shouldStartAutomaticPiP(size: webView.bounds.size,
            playing: $0.playing, capable: $0.capable, age: now - $0.seenAt,
            providerFullscreen: elementFullscreen || !fullscreenVideoIDs.isEmpty, active: pictureInPicture.isActive) }) else { return }
        // Uses the existing provider's public PiP API. Only its confirmed mode
        // callback can hide our retained surface; a rejected attempt is silent.
        pictureInPicture.requestAutomatically()
    }
    private func refreshPresentation() {
        guard let webView else { return }
        elementFullscreen = webView.fullscreenState != .notInFullscreen
        publishFullscreen()
        // Refresh known video frames, including cross-origin provider iframes.
        // This reads presentation state only; it never reloads, seeks or plays.
        for (id, video) in frames { refreshFrame(id, frame: video.frame) }
    }
    private func refreshCapability() {
        let now = ProcessInfo.processInfo.systemUptime
        // A suspended document does not emit heartbeats. Keep its known
        // fullscreen ownership until an actual snapshot or invalid-frame result
        // confirms its return/removal; age alone must never raise our window.
        let staleFullscreen = frames.filter { fullscreenVideoIDs.contains($0.key) && now - $0.value.seenAt >= 3 }
        frames = frames.filter { $0.key == activeVideoID || fullscreenVideoIDs.contains($0.key) || now - $0.value.seenAt < 3 }
        if UIApplication.shared.applicationState == .active {
            for (id, video) in staleFullscreen { refreshFrame(id, frame: video.frame) }
        }
        pictureInPicture?.reportCapability(frames.values.contains(where: \.capable) ? .available : .unavailable, owner: owner)
    }
    private func refreshFrame(_ id: String, frame: WKFrameInfo) {
        guard refreshingFrames.insert(id).inserted else { return }
        evaluate("refresh", id: id, frame: frame, reportFailure: false)
    }
    static func confirmsMissingVideo(_ result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let value): return value as? Bool != true
        case .failure(let error):
            let error = error as NSError
            return error.domain == WKError.errorDomain && error.code == WKError.Code.javaScriptInvalidFrameTarget.rawValue
        }
    }
    private func request() {
        refreshCapability()
        guard let candidate = frames.filter({ $0.value.capable }).max(by: { $0.value.score < $1.value.score }) else {
            pictureInPicture?.failed("This source has no video that supports iOS Picture in Picture.", owner: owner); return
        }
        evaluate("request", id: candidate.key, frame: candidate.value.frame, reportFailure: true)
    }
    private func stop() {
        guard let id = activeVideoID, let frame = frames[id]?.frame else { return }
        evaluate("stop", id: id, frame: frame, reportFailure: false)
    }
    private func evaluate(_ action: String, id: String, frame: WKFrameInfo, reportFailure: Bool) {
        let requestOwner = owner
        let encoded = (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        webView?.evaluateJavaScript("window.__streamifySportsPiP && window.__streamifySportsPiP.\(action)(\(encoded))",
            in: frame, in: Self.world) { [weak self] result in
                guard let self, self.owner == requestOwner else { return }
                if action == "refresh" {
                    self.refreshingFrames.remove(id)
                    if Self.confirmsMissingVideo(result) {
                        self.frames.removeValue(forKey: id)
                        self.fullscreenVideoIDs.remove(id)
                        self.publishFullscreen()
                    }
                }
                if reportFailure {
                    guard case .success(let value) = result, value as? Bool == true else {
                        self.pictureInPicture?.failed("This provider rejected iOS Picture in Picture. Start its video first or choose another source.", owner: requestOwner)
                        return
                    }
                }
            }
    }

    static func script(token: String) -> String {
        let encoded = (try? JSONEncoder().encode(token)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function(){
          var token=\(encoded),nodes=new Map(),ids=new WeakMap(),seq=0,prefix=Math.random().toString(36).slice(2);
          function active(v){return v.webkitPresentationMode==='picture-in-picture'||document.pictureInPictureElement===v;}
          function supports(v){try{return v.readyState>=1&&v.videoWidth>0&&!v.disablePictureInPicture&&
            ((typeof v.webkitSetPresentationMode==='function'&&v.webkitSupportsPresentationMode&&v.webkitSupportsPresentationMode('picture-in-picture'))||
             (document.pictureInPictureEnabled&&typeof v.requestPictureInPicture==='function'));}catch(e){return false;}}
          function send(v,kind){var r=v.getBoundingClientRect();try{window.webkit.messageHandlers.streamifySportsPiP.postMessage({
            token:token,kind:kind,id:ids.get(v),active:active(v),fullscreen:v.isConnected&&(v.webkitPresentationMode==='fullscreen'||v.webkitDisplayingFullscreen===true),
            paused:v.paused,capable:v.isConnected&&supports(v),area:Math.max(0,r.width*r.height)});}catch(e){}}
          function mode(v){send(v,'mode');}
          function scan(){document.querySelectorAll('video').forEach(function(v){
            if(!ids.has(v)&&nodes.size<64){var id=prefix+'-'+(++seq);ids.set(v,id);nodes.set(id,v);
              ['loadedmetadata','canplay','play','pause','resize','emptied'].forEach(function(e){v.addEventListener(e,function(){send(v,'snapshot');});});
              ['webkitpresentationmodechanged','webkitbeginfullscreen','webkitendfullscreen','enterpictureinpicture','leavepictureinpicture'].forEach(function(e){v.addEventListener(e,function(){mode(v);});});}
            if(ids.has(v))send(v,'snapshot');
          });nodes.forEach(function(v,id){if(!v.isConnected&&!active(v)){send(v,'snapshot');nodes.delete(id);}});}
          window.__streamifySportsPiP={request:function(id){var v=nodes.get(id);if(!v||!supports(v))return false;
            try{if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('picture-in-picture');
              else v.requestPictureInPicture().catch(function(){try{window.webkit.messageHandlers.streamifySportsPiP.postMessage({token:token,kind:'error'});}catch(e){}});
              return true;}catch(e){return false;}},
            stop:function(id){var v=nodes.get(id);if(!v)return false;try{if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('inline');
              else if(document.pictureInPictureElement===v)document.exitPictureInPicture();return true;}catch(e){return false;}},
            refresh:function(id){var v=nodes.get(id);if(!v)return false;send(v,'snapshot');return true;}};
          new MutationObserver(scan).observe(document,{childList:true,subtree:true});
          document.addEventListener('DOMContentLoaded',scan);
          document.addEventListener('visibilitychange',function(){if(!document.hidden)scan();});
          window.addEventListener('pageshow',scan);scan();setInterval(scan,1000);
        })();
        """
    }
}
