import Foundation
import WebKit

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
    private struct VideoFrame {
        let frame: WKFrameInfo
        let capable: Bool
        let score: Double
        let seenAt: TimeInterval
    }

    init(webView: WKWebView, pictureInPicture: SportsSystemPiP) {
        self.webView = webView; self.pictureInPicture = pictureInPicture
        super.init()
        webView.configuration.userContentController.add(self, contentWorld: Self.world, name: Self.name)
    }
    func begin() {
        pictureInPicture?.detach(owner: owner)
        owner = UUID(); frames.removeAll(); activeVideoID = nil
        let requestOwner = owner
        pictureInPicture?.attach(owner: owner, capability: .checking,
            request: { [weak self] in guard let self, self.owner == requestOwner else { return }; self.request() },
            stop: { [weak self] in guard let self, self.owner == requestOwner else { return }; self.stop() })
        let script = WKUserScript(source: Self.script(token: owner.uuidString), injectionTime: .atDocumentEnd,
            forMainFrameOnly: false, in: Self.world)
        webView?.configuration.userContentController.addUserScript(script)
    }
    func loaded() { refreshCapability() }
    func terminated() {
        frames.removeAll(); activeVideoID = nil
        // A dead web content process cannot send a final DOM mode event.
        // Return to the retained error/reload screen instead of trapping it offscreen.
        pictureInPicture?.didStop(owner: owner, restoring: true)
        pictureInPicture?.reportCapability(.unavailable, owner: owner)
    }
    func finish() {
        pictureInPicture?.detach(owner: owner)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.name, contentWorld: Self.world)
        frames.removeAll(); activeVideoID = nil; owner = UUID()
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
        let capable = body["capable"] as? Bool == true && area.isFinite && area > 3200
        frames[id] = VideoFrame(frame: message.frameInfo, capable: capable,
            score: min(max(0, area), 10_000_000) + (playing ? 100_000_000 : 0), seenAt: ProcessInfo.processInfo.systemUptime)
        refreshCapability()
        if active {
            activeVideoID = id
            pictureInPicture?.didStart(owner: owner)
        } else if activeVideoID == id, body["kind"] as? String == "mode" {
            activeVideoID = nil
            // Restoring leaves the video playing inline. Closing the system
            // window pauses it; explicit app Restore also marks its intent.
            pictureInPicture?.didStop(owner: owner, restoring: playing)
        }
    }
    private func refreshCapability() {
        let now = ProcessInfo.processInfo.systemUptime
        frames = frames.filter { $0.key == activeVideoID || now - $0.value.seenAt < 3 }
        pictureInPicture?.reportCapability(frames.values.contains(where: \.capable) ? .available : .unavailable, owner: owner)
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
            token:token,kind:kind,id:ids.get(v),active:active(v),paused:v.paused,capable:v.isConnected&&supports(v),area:Math.max(0,r.width*r.height)});}catch(e){}}
          function mode(v){setTimeout(function(){send(v,'mode');},80);}
          function scan(){document.querySelectorAll('video').forEach(function(v){
            if(!ids.has(v)&&nodes.size<64){var id=prefix+'-'+(++seq);ids.set(v,id);nodes.set(id,v);
              ['loadedmetadata','canplay','play','pause','resize','emptied'].forEach(function(e){v.addEventListener(e,function(){send(v,'snapshot');});});
              ['webkitpresentationmodechanged','enterpictureinpicture','leavepictureinpicture'].forEach(function(e){v.addEventListener(e,function(){mode(v);});});}
            if(ids.has(v))send(v,'snapshot');
          });nodes.forEach(function(v,id){if(!v.isConnected&&!active(v)){send(v,'snapshot');nodes.delete(id);}});}
          window.__streamifySportsPiP={request:function(id){var v=nodes.get(id);if(!v||!supports(v))return false;
            try{if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('picture-in-picture');
              else v.requestPictureInPicture().catch(function(){try{window.webkit.messageHandlers.streamifySportsPiP.postMessage({token:token,kind:'error'});}catch(e){}});
              return true;}catch(e){return false;}},
            stop:function(id){var v=nodes.get(id);if(!v)return false;try{if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('inline');
              else if(document.pictureInPictureElement===v)document.exitPictureInPicture();return true;}catch(e){return false;}}};
          new MutationObserver(scan).observe(document,{childList:true,subtree:true});
          document.addEventListener('DOMContentLoaded',scan);scan();setInterval(scan,1000);
        })();
        """
    }
}
