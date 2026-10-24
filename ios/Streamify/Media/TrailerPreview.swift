import SwiftUI
import WebKit

/// The player stays 240 points high; native controls sit below YouTube's own controls.
struct TrailerPreview: View {
    let url: URL?
    let poster: URL?
    let active: Bool

    var body: some View {
        Group {
            if let identifier = TrailerDocument.videoID(from: url) {
                TrailerPreviewPlayer(videoID: identifier, poster: poster, active: active).id(identifier)
            } else {
                RemoteArtwork(url: poster).frame(height: 240).clipped().accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("trailer-preview")
    }
}

private struct TrailerPreviewPlayer: View {
    let videoID: String
    let poster: URL?
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TrailerPreviewModel()
    @State private var visible = false

    private var shouldPlay: Bool { active && visible && scenePhase == .active }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RemoteArtwork(url: poster).accessibilityHidden(true)
                TrailerWebView(videoID: videoID, active: shouldPlay, model: model)
            }
            .frame(height: 240).clipped()
            HStack(spacing: 12) {
                Text("Trailer").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                Spacer()
                if model.state == .ended {
                    Button {
                        model.replay += 1
                    } label: {
                        Label("Replay", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }
                    .disabled(!shouldPlay).accessibilityIdentifier("trailer-replay")
                }
                Button {
                    model.muted.toggle()
                } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel(model.muted ? "Unmute trailer" : "Mute trailer")
                .accessibilityIdentifier("trailer-mute")
                .disabled(!shouldPlay || !model.state.revealsPlayer)
            }
            .buttonStyle(.plain).foregroundStyle(AppTheme.foreground)
            .padding(.horizontal, 12).background(AppTheme.panel)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

enum TrailerPlaybackState: Equatable {
    case loading, ready, playing, paused, buffering, ended, failed
    var revealsPlayer: Bool { self != .loading && self != .failed }
    func wantsPlayback(active: Bool) -> Bool { active && revealsPlayer && self != .ended }

    mutating func receive(event: String, value: Int? = nil) {
        guard self != .failed else { return }
        switch event {
        case "ready": if self == .loading { self = .ready }
        case "error", "blocked": self = .failed
        case "state":
            switch value {
            case 0: self = .ended
            case 1: self = .playing
            case 2: if self != .ended { self = .paused }
            case 3: self = .buffering
            case 5: if self == .loading { self = .ready }
            default: break
            }
        default: break
        }
    }
}

@MainActor
private final class TrailerPreviewModel: ObservableObject {
    @Published var state = TrailerPlaybackState.loading
    @Published var muted = true
    @Published var replay = 0
}

/// Values cross the JavaScript bridge as typed arguments, never executable interpolation.
enum TrailerPlaybackCommand {
    case activity(Bool), mute(Bool), replay, destroy
    var script: String {
        switch self {
        case .activity: return "window.streamifyTrailer && window.streamifyTrailer.setWanted(wanted);"
        case .mute: return "window.streamifyTrailer && window.streamifyTrailer.setMuted(muted);"
        case .replay: return "window.streamifyTrailer && window.streamifyTrailer.replay();"
        case .destroy: return "window.streamifyTrailer && window.streamifyTrailer.destroy();"
        }
    }
    var arguments: [String: Any] {
        switch self {
        case .activity(let active): return ["wanted": active]
        case .mute(let muted): return ["muted": muted]
        case .replay, .destroy: return [:]
        }
    }
}

enum TrailerDocument {
    static func validID(_ value: String) -> Bool {
        value.utf8.count == 11 && value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
    static func videoID(from url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)
        let candidate: String?
        if ["youtu.be", "www.youtu.be"].contains(host), segments.count == 1 {
            candidate = segments[0]
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com", "youtube-nocookie.com"].contains(host) {
            if url.path == "/watch" {
                let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "v" } ?? []
                candidate = values.count == 1 ? values[0].value : nil
            } else if segments.count == 2, ["embed", "shorts"].contains(segments[0]) {
                candidate = segments[1]
            } else { candidate = nil }
        } else { candidate = nil }
        guard let candidate, validID(candidate) else { return nil }
        return candidate
    }

    /// YouTube requires the ID registered by the OS, including a sideloader's suffix.
    static func origin(bundleIdentifier: String?) -> URL {
        let value = bundleIdentifier?.lowercased() ?? "com.streamify.app"
        let valid = value.range(of: "^[a-z0-9-]+(?:\\.[a-z0-9-]+)+$", options: .regularExpression) != nil
        return URL(string: "https://\(valid ? value : "com.streamify.app")/")!
    }

    static func document(videoID: String, bundleIdentifier: String?, token: String) -> String? {
        guard validID(videoID) else { return nil }
        let origin = origin(bundleIdentifier: bundleIdentifier).absoluteString
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": videoID, "origin": origin, "token": token], options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let configuration = json.replacingOccurrences(of: "<", with: "\\u003c").replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026").replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body,#player{margin:0;width:100%;height:100%;background:#000}iframe{display:block;width:100%;height:100%;border:0}body{overflow:hidden}</style></head><body><div id="player"></div><script>
        const config=\(configuration);let player,ready=false,wanted=false,muted=true,ended=false,timer,lastMuted=true;
        function report(event,value){window.webkit.messageHandlers.trailer.postMessage({token:config.token,event:event,value:value});}
        function control(){if(!ready)return;if(wanted&&!ended)player.playVideo();else player.pauseVideo();}
        window.streamifyTrailer={setWanted:function(value){wanted=value===true;control();},setMuted:function(value){muted=value===true;if(ready){muted?player.mute():player.unMute();lastMuted=muted;report('muted',muted);}},replay:function(){if(ready&&wanted){ended=false;player.seekTo(0,true);player.playVideo();}},destroy:function(){wanted=false;clearInterval(timer);if(ready){player.pauseVideo();player.destroy();}ready=false;}};
        function onYouTubeIframeAPIReady(){player=new YT.Player('player',{videoId:config.id,width:'100%',height:'100%',playerVars:{playsinline:1,controls:1,rel:0,autoplay:0,origin:config.origin,widget_referrer:config.origin},events:{onReady:function(){ready=true;player.mute();report('ready');timer=setInterval(function(){if(!ready)return;const next=player.isMuted();if(next!==lastMuted){lastMuted=next;muted=next;report('muted',next);}},1000);},onStateChange:function(event){ended=event.data===0;report('state',event.data);if(event.data===1&&!wanted)player.pauseVideo();},onError:function(event){wanted=false;report('error',event.data);},onAutoplayBlocked:function(){wanted=false;report('blocked');}}});}
        window.addEventListener('pagehide',function(){window.streamifyTrailer.setWanted(false);});
        </script><script src="https://www.youtube.com/iframe_api" onerror="report('error');"></script></body></html>
        """
    }
}

private struct TrailerWebView: UIViewRepresentable {
    let videoID: String
    let active: Bool
    @ObservedObject var model: TrailerPreviewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.userContentController.add(context.coordinator, name: "trailer")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isHidden = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        context.coordinator.connect(web)
        let bundleIdentifier = Bundle.main.bundleIdentifier
        #if DEBUG
        if PreviewFixtures.enabled {
            web.loadHTMLString(PreviewFixtures.trailerHTML(token: context.coordinator.token), baseURL: TrailerDocument.origin(bundleIdentifier: bundleIdentifier))
            return web
        }
        #endif
        if let html = TrailerDocument.document(videoID: videoID, bundleIdentifier: bundleIdentifier, token: context.coordinator.token) {
            web.loadHTMLString(html, baseURL: TrailerDocument.origin(bundleIdentifier: bundleIdentifier))
        }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.update(active: active) }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.dismantle() }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let token = UUID().uuidString
        let model: TrailerPreviewModel
        weak var web: WKWebView?
        private var observers: [NSObjectProtocol] = []
        private var timeout: DispatchWorkItem?
        private var destroyed = false
        private var active = false
        private var sentActive: Bool?
        private var sentMuted: Bool?
        private var sentReplay = 0

        init(model: TrailerPreviewModel) { self.model = model }
        func connect(_ web: WKWebView) {
            self.web = web
            observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() }
            })
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.model.state == .loading else { return }
                self.model.state = .failed
                self.pause()
            }
            self.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        }

        func update(active: Bool) {
            guard !destroyed, let web else { return }
            self.active = active
            web.isHidden = !model.state.revealsPlayer
            let wantsPlayback = model.state.wantsPlayback(active: active)
            if sentActive != wantsPlayback {
                web.setAllMediaPlaybackSuspended(!wantsPlayback, completionHandler: nil)
                command(.activity(wantsPlayback))
                sentActive = wantsPlayback
            }
            if model.state.revealsPlayer, sentMuted != model.muted {
                command(.mute(model.muted)); sentMuted = model.muted
            }
            if sentReplay != model.replay, active, model.state == .ended {
                sentReplay = model.replay
                // Clear the terminal state before resuming the previously suspended player.
                web.setAllMediaPlaybackSuspended(false, completionHandler: nil)
                command(.activity(true)); command(.replay)
                sentActive = true
            }
        }
        private func command(_ value: TrailerPlaybackCommand) {
            web?.callAsyncJavaScript(value.script, arguments: value.arguments, in: nil, in: .page, completionHandler: nil)
        }
        private func pause() {
            active = false
            sentActive = false
            command(.activity(false))
            web?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !destroyed, message.frameInfo.isMainFrame, message.name == "trailer", let body = message.body as? [String: Any],
                  body["token"] as? String == token, let event = body["event"] as? String else { return }
            if event == "muted", let muted = body["value"] as? Bool { model.muted = muted; sentMuted = muted; return }
            model.state.receive(event: event, value: body["value"] as? Int)
            if event == "ready" { timeout?.cancel(); timeout = nil; sentActive = nil; sentMuted = nil }
            if model.state == .failed { pause() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame?.isMainFrame == true {
                let origin = TrailerDocument.origin(bundleIdentifier: Bundle.main.bundleIdentifier)
                if url.absoluteString == "about:blank" || url.host == origin.host { decisionHandler(.allow); return }
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated, secureURL(url.absoluteString) != nil { UIApplication.shared.open(url) }
            } else { decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if active, let url = navigationAction.request.url, secureURL(url.absoluteString) != nil { UIApplication.shared.open(url) }
            return nil
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            guard !destroyed, (error as NSError).code != NSURLErrorCancelled else { return }
            model.state = .failed; pause()
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { model.state = .failed; pause() }
        func dismantle() {
            guard !destroyed else { return }
            pause(); command(.destroy)
            destroyed = true
            timeout?.cancel(); timeout = nil
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
            web?.configuration.userContentController.removeScriptMessageHandler(forName: "trailer")
            web?.stopLoading()
            web?.navigationDelegate = nil
            web?.uiDelegate = nil
            web?.loadHTMLString("", baseURL: nil)
            web = nil
        }
        deinit {
            timeout?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
