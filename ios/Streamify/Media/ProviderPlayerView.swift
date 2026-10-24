import SwiftUI
import WebKit
import AVKit
import AVFoundation
import Combine

/// A media suffix is a routing hint, not proof that the device can decode it.
/// Direct mode must still offer a different renderer when native playback fails.
enum ProviderPlaybackRoute: Equatable {
    case nativeVideo, webDirect, webEmbed

    static func resolve(url: URL, direct: Bool, webFallback: Bool = false) -> Self {
        let mediaAddress = ["m3u8", "mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
        if mediaAddress { return direct || webFallback ? .webDirect : .nativeVideo }
        return direct ? .webDirect : .webEmbed
    }
}

enum ProviderPlaybackFailure {
    /// These public error domains distinguish access/network failures from a
    /// missing decoder. An unclassified AVFoundation failure is not a codec diagnosis.
    static func message(for error: Error?, fallback: String) -> String {
        var current = error as NSError?
        for _ in 0..<6 {
            guard let item = current else { break }
            if item.domain == NSURLErrorDomain {
                if [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                    NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed].contains(item.code) {
                    return "The video source could not be reached. Check your connection or try another source."
                }
                if item.code == URLError.userAuthenticationRequired.rawValue {
                    return "This source requires access that the iOS player does not have. Try the web player or another source."
                }
            }
            if item.domain == AVFoundationErrorDomain {
                switch item.code {
                case AVError.Code.fileFormatNotRecognized.rawValue:
                    return "The iOS player could not recognize this file or stream. Try the web player or another source."
                case AVError.Code.decoderNotFound.rawValue:
                    return "This source needs a decoder that the iOS player cannot use. Choose another source."
                case AVError.Code.contentIsProtected.rawValue:
                    return "This source is protected and the iOS player could not access it. Choose another source."
                default: break
                }
            }
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return error?.localizedDescription ?? fallback
    }
}

/// Activates foreground movie audio, including playback while the iPhone's silent switch is on.
enum PlaybackAudioSession {
    @MainActor static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
    }
}

private final class NativePlaybackTimeObservation {
    var player: AVPlayer?
    var token: Any?
    func clear() {
        if let token { player?.removeTimeObserver(token) }
        token = nil; player = nil
    }
    deinit { clear() }
}

@MainActor
private final class NativePlaybackModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var statusObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var endingObserver: NSObjectProtocol?
    private let timeObservation = NativePlaybackTimeObservation()
    private var checkpoint = PlaybackCheckpoint()
    private var onProgress: ((Double, Double) -> Void)?
    private var resumeSeconds: Double = 0
    private var restored = false
    private var restoring = false
    private var generation = UUID()

    func load(_ url: URL, resumeSeconds: Double = 0, onProgress: ((Double, Double) -> Void)? = nil) async {
        stop()
        self.resumeSeconds = resumeSeconds
        self.onProgress = onProgress
        checkpoint = PlaybackCheckpoint(); restored = false; restoring = false
        let request = UUID()
        generation = request
        loading = true
        error = nil
        do {
            var assetURL = url
            #if DEBUG
            assetURL = PreviewFixtures.nativePlayerURL(for: url) ?? url
            #endif
            let asset = AVURLAsset(url: assetURL)
            let playable = try await asset.load(.isPlayable)
            try Task.checkCancellation()
            guard generation == request else { return }
            guard playable else {
                throw AnimePlaybackError.unavailable("The iOS player could not read this source. Try the web player or another source.")
            }
            try PlaybackAudioSession.activate()
            let item = AVPlayerItem(asset: asset)
            let created = AVPlayer(playerItem: item)
            created.allowsExternalPlayback = true
            player = created
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.loading = false
                        self.restoreIfPossible()
                        self.player?.play()
                    case .failed:
                        self.fail(ProviderPlaybackFailure.message(for: item.error, fallback: "iOS could not load this video. Try another source."))
                    case .unknown:
                        break
                    @unknown default:
                        self.fail("iOS could not start this source. Reload or choose another source.")
                    }
                }
            }
            timeObservation.player = created
            timeObservation.token = created.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    self.restoreIfPossible(); self.capture()
                }
            }
            playbackObservation = created.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
                guard observed.timeControlStatus == .paused else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    self.capture(force: true)
                }
            }
            endingObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    self.capture(force: true, ended: true)
                }
            }
            failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                let message = ProviderPlaybackFailure.message(for: notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error,
                    fallback: "This video stopped unexpectedly. Reload or choose another source.")
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    self.fail(message)
                }
            }
        } catch is CancellationError {
            if generation == request { stop() }
        } catch {
            if generation == request { fail(ProviderPlaybackFailure.message(for: error, fallback: "The iOS player could not load this source.")) }
        }
    }

    func pause() { capture(force: true); player?.pause() }
    func stop() {
        capture(force: true)
        generation = UUID()
        statusObservation?.invalidate()
        statusObservation = nil
        playbackObservation?.invalidate(); playbackObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        if let endingObserver { NotificationCenter.default.removeObserver(endingObserver) }
        endingObserver = nil
        timeObservation.clear()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        loading = false
        onProgress = nil
    }
    private func restoreIfPossible() {
        guard !restored, !restoring, let player, let item = player.currentItem,
              item.status == .readyToPlay else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, (60...43_200).contains(duration) else { return }
        restored = true
        guard resumeSeconds.isFinite, resumeSeconds >= 5, resumeSeconds < duration * 0.95 else { return }
        restoring = true
        let request = generation
        player.seek(to: CMTime(seconds: min(resumeSeconds, duration - 1), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == request else { return }
                self.restoring = false
            }
        }
    }
    private func capture(force: Bool = false, ended: Bool = false) {
        guard restored, !restoring, let player, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        if let sample = checkpoint.sample(position: ended ? duration : player.currentTime().seconds,
            duration: duration, now: ProcessInfo.processInfo.systemUptime, force: force) {
            onProgress?(sample.position, sample.duration)
        }
    }
    private func fail(_ message: String) {
        player?.pause()
        loading = false
        error = message
    }
    deinit {
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let endingObserver { NotificationCenter.default.removeObserver(endingObserver) }
    }
}

/// Native chrome stays outside the provider frame so Close and Reload remain available.
struct ProviderPlayerView: View {
    let title: String
    let url: URL
    var sources: [SportsStream] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reload = 0
    @State private var direct = false
    @State private var selectedSourceURL: URL?

    private var effectiveURL: URL { selectedSourceURL ?? url }
    private var availableSources: [SportsStream] {
        var seen = Set<URL>()
        return sources.filter { seen.insert($0.url).inserted }
    }
    private var sourceTitle: String {
        availableSources.first(where: { $0.url == effectiveURL })?.title ?? "Current source"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close player")
                if availableSources.isEmpty {
                    Text(title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Menu {
                        ForEach(Array(availableSources.enumerated()), id: \.element.id) { index, source in
                            Button { selectSource(source) } label: {
                                if source.url == effectiveURL { Label(source.title, systemImage: "checkmark") }
                                else { Text(source.title) }
                            }
                            .accessibilityIdentifier("sports-player-source-option-\(index)")
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title).font(.headline).lineLimit(1)
                                Text(sourceTitle).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel("Switch stream source")
                    .accessibilityValue("\(title), \(sourceTitle)")
                    .accessibilityIdentifier("sports-player-source-picker")
                }
                AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            }.padding(.horizontal, 8)
            ProviderPlaybackSurface(url: effectiveURL, reload: reload, direct: direct)
                .id(effectiveURL)
            HStack(spacing: 16) {
                Button { reload += 1 } label: { Label("Reload", systemImage: "arrow.clockwise") }
                Spacer(minLength: 0)
                Button { direct.toggle() } label: { Label(direct ? "Embed mode" : "Direct mode", systemImage: "rectangle.on.rectangle") }
                Spacer(minLength: 0)
                Button { openURL(effectiveURL) } label: { Image(systemName: "safari").frame(width: 44, height: 44) }
                    .accessibilityLabel("Open in browser")
            }.font(.caption.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 54)
        }
        .background(.black).foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .playerSwipeToDismiss { dismiss() }
        .onChange(of: url) { _, _ in selectedSourceURL = nil; reload = 0; direct = false }
    }

    private func selectSource(_ source: SportsStream) {
        guard source.url != effectiveURL else { return }
        selectedSourceURL = source.url
        reload = 0
        direct = false
    }
}

@MainActor
struct ProviderPlaybackSurface: View {
    let url: URL
    var reload: Int = 0
    var direct = false
    var referer: URL? = nil
    var resumeSeconds: Double = 0
    var onProgress: ((Double, Double) -> Void)? = nil
    /// App-owned sports playback stays mounted for native/WebKit PiP. Other
    /// presentations retain their existing background-pause behavior.
    var preservePlaybackOnBackground = false
    var systemPiP: SportsSystemPiP? = nil
    @State private var loading = true
    @State private var error: String?
    @State private var webFallbackURL: URL?
    @StateObject private var nativePlayback = NativePlaybackModel()
    @Environment(\.scenePhase) private var scenePhase

    private var usesWebFallback: Bool { webFallbackURL == url }
    private var route: ProviderPlaybackRoute { .resolve(url: url, direct: direct, webFallback: usesWebFallback) }

    var body: some View {
        ZStack {
            Color.black
            if secureURL(url.absoluteString) == nil {
                Text("Only secure HTTPS player addresses are supported.").foregroundStyle(.white).padding()
            } else if route == .nativeVideo {
                Group {
                    if let systemPiP { SportsNativePlayerSurface(player: nativePlayback.player, pictureInPicture: systemPiP) }
                    else { VideoPlayer(player: nativePlayback.player) }
                }
                    .task(id: "\(url.absoluteString):\(reload):\(direct)") {
                        await nativePlayback.load(url, resumeSeconds: resumeSeconds, onProgress: onProgress)
                    }
                    .onDisappear { nativePlayback.stop() }
                if nativePlayback.loading { loadingIndicator("Loading video…") }
                if let error = nativePlayback.error { failureMessage(error, canTryWeb: true) }
            } else {
                PlayerWebView(url: url, reload: reload, direct: route == .webDirect, referer: referer,
                    resumeSeconds: resumeSeconds, onProgress: onProgress, systemPiP: systemPiP, loading: $loading, error: $error)
                if loading {
                    loadingIndicator("Connecting to source…")
                }
                if let error {
                    failureMessage(error)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if usesWebFallback {
                Button { changeFallback(false) } label: {
                    Label("Use iOS player", systemImage: "play.rectangle").font(.caption.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(SecondaryButtonStyle()).padding(12)
                    .accessibilityIdentifier("player-use-native")
            }
        }
        .onDisappear { nativePlayback.stop() }
        .onChange(of: url) { _, _ in webFallbackURL = nil }
        .onChange(of: direct) { _, _ in webFallbackURL = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active && !preservePlaybackOnBackground { nativePlayback.pause() } }
    }

    private func loadingIndicator(_ message: String) -> some View {
        VStack(spacing: 12) { ProgressView().tint(.white); Text(message).font(.caption) }
            .foregroundStyle(.white).padding(20).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
    }

    private func failureMessage(_ message: String, canTryWeb: Bool = false) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash").font(.title2)
            Text("Source couldn’t load").font(.headline)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            if canTryWeb {
                Button("Try web player") { changeFallback(true) }.buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("player-try-web")
                Text("The web player may handle this source differently. A source with an unsupported codec can still fail.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Reload, switch providers, or open this source in Safari.").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }.foregroundStyle(.white).padding(24).frame(maxWidth: 400)
            .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).padding()
    }

    private func changeFallback(_ enabled: Bool) {
        // Reset the old PiP owner before its view detaches; otherwise a detach
        // callback could be mistaken for an explicit close of the sports session.
        systemPiP?.reset()
        nativePlayback.stop()
        loading = true; error = nil
        webFallbackURL = enabled ? url : nil
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(red: 1, green: 0.27, blue: 0.31, alpha: 1)
        view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct PlayerWebView: UIViewRepresentable {
    let url: URL
    let reload: Int
    let direct: Bool
    let referer: URL?
    let resumeSeconds: Double
    let onProgress: ((Double, Double) -> Void)?
    let systemPiP: SportsSystemPiP?
    @Binding var loading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "streamifyProgress")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        if let systemPiP { context.coordinator.pipBridge = SportsWebPiPBridge(webView: webView, pictureInPicture: systemPiP) }
        context.coordinator.observeLifecycle()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let key = "\(url.absoluteString)|\(reload)|\(direct)|\(referer?.absoluteString ?? "")"
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        context.coordinator.providerHost = url.host?.lowercased() ?? ""
        context.coordinator.beginSession(webView)
        webView.stopLoading()
        // Defer bindings until after SwiftUI's representable update cycle.
        DispatchQueue.main.async { loading = true; error = nil }
        #if DEBUG
        if PreviewFixtures.enabled {
            webView.loadHTMLString(PreviewFixtures.playerHTML, baseURL: url)
            return
        }
        #endif
        if direct {
            var request = URLRequest(url: url)
            if let referer, secureURL(referer.absoluteString) != nil { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
            webView.load(request)
        }
        else {
            let escaped = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            webView.loadHTMLString("""
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
                <style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
                </head><body><iframe src="\(escaped)" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>
                """, baseURL: referer ?? url)
        }
    }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.finishSession()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "streamifyProgress")
        uiView.configuration.userContentController.removeAllUserScripts()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: PlayerWebView
        var key = ""
        var providerHost = ""
        weak var webView: WKWebView?
        private var token = UUID().uuidString
        private var checkpoint = PlaybackCheckpoint()
        private var lastMessageAt = -Double.infinity
        private var lifecycleObservers: [NSObjectProtocol] = []
        var pipBridge: SportsWebPiPBridge?
        init(_ parent: PlayerWebView) { self.parent = parent }

        func observeLifecycle() {
            for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
                lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.flush() }
                })
            }
        }

        func beginSession(_ webView: WKWebView) {
            flush()
            token = UUID().uuidString
            checkpoint = PlaybackCheckpoint(); lastMessageAt = -Double.infinity
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            pipBridge?.begin()
            if parent.onProgress != nil {
                controller.addUserScript(WKUserScript(source: PlaybackProgressScript.document(token: token, resumeSeconds: parent.resumeSeconds),
                    injectionTime: .atDocumentEnd, forMainFrameOnly: false))
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard parent.onProgress != nil, message.name == "streamifyProgress", message.webView === webView,
                  message.frameInfo.securityOrigin.`protocol` == "https",
                  let body = message.body as? [String: Any], body["token"] as? String == token,
                  let position = body["position"] as? NSNumber, let duration = body["duration"] as? NSNumber else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastMessageAt >= 0.25 else { return }
            lastMessageAt = now
            if let sample = checkpoint.sample(position: position.doubleValue, duration: duration.doubleValue,
                now: now, force: body["force"] as? Bool == true) {
                parent.onProgress?(sample.position, sample.duration)
            }
        }

        private func flush() {
            webView?.evaluateJavaScript("window.__streamifyFlushProgress&&window.__streamifyFlushProgress();", completionHandler: nil)
            if let sample = checkpoint.flush(now: ProcessInfo.processInfo.systemUptime) {
                parent.onProgress?(sample.position, sample.duration)
            }
        }

        func finishSession() {
            flush()
            pipBridge?.finish(); pipBridge = nil
            token = UUID().uuidString
            lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
            lifecycleObservers.removeAll()
        }

        deinit { lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) } }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let address = navigationAction.request.url else { decisionHandler(.cancel); return }
            let scheme = address.scheme?.lowercased() ?? ""
            // Provider popups never become windows or launch another app.
            guard navigationAction.targetFrame != nil else { decisionHandler(.cancel); return }
            if address.absoluteString == "about:blank" { decisionHandler(.allow); return }
            guard scheme == "https", address.user == nil, address.password == nil else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame?.isMainFrame == true {
                let host = address.host?.lowercased() ?? ""
                let isEmbedDocument = !parent.direct && address == parent.referer
                guard host == providerHost || host.hasSuffix("." + providerHost) || isEmbedDocument else { decisionHandler(.cancel); return }
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false; pipBridge?.loaded() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            pipBridge?.terminated()
            parent.loading = false
            parent.error = "The player was stopped by iOS. Reload this source to continue."
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            parent.loading = false; parent.error = error.localizedDescription
        }
    }
}
