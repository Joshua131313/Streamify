import SwiftUI
import WebKit
import AVKit
import AVFoundation
import Combine

/// Activates foreground movie audio, including playback while the iPhone's silent switch is on.
enum PlaybackAudioSession {
    @MainActor static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
    }
}

@MainActor
private final class NativePlaybackModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var statusObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var generation = UUID()

    func load(_ url: URL) async {
        stop()
        let request = UUID()
        generation = request
        loading = true
        error = nil
        do {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            try Task.checkCancellation()
            guard generation == request else { return }
            guard playable else {
                throw AnimePlaybackError.unavailable("This source is not a video format that iOS can play. Try another source or open it in Safari.")
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
                        self.player?.play()
                    case .failed:
                        self.fail(item.error?.localizedDescription ?? "iOS could not load this video. Try another source.")
                    case .unknown:
                        break
                    @unknown default:
                        self.fail("iOS could not start this source. Reload or choose another source.")
                    }
                }
            }
            failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                    ?? "This video stopped unexpectedly. Reload or choose another source."
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    self.fail(message)
                }
            }
        } catch is CancellationError {
            if generation == request { stop() }
        } catch {
            if generation == request { fail(error.localizedDescription) }
        }
    }

    func pause() { player?.pause() }
    func stop() {
        generation = UUID()
        statusObservation?.invalidate()
        statusObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        loading = false
    }
    private func fail(_ message: String) {
        player?.pause()
        loading = false
        error = message
    }
    deinit {
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}

/// Native chrome stays outside the provider frame so Close and Reload remain available.
struct ProviderPlayerView: View {
    let title: String
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reload = 0
    @State private var direct = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close player")
                Text(title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            }.padding(.horizontal, 8)
            ProviderPlaybackSurface(url: url, reload: reload, direct: direct)
            HStack(spacing: 16) {
                Button { reload += 1 } label: { Label("Reload", systemImage: "arrow.clockwise") }
                Spacer(minLength: 0)
                Button { direct.toggle() } label: { Label(direct ? "Embed mode" : "Direct mode", systemImage: "rectangle.on.rectangle") }
                Spacer(minLength: 0)
                Button { openURL(url) } label: { Image(systemName: "safari").frame(width: 44, height: 44) }
                    .accessibilityLabel("Open in browser")
            }.font(.caption.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 54)
        }
        .background(.black).foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

@MainActor
struct ProviderPlaybackSurface: View {
    let url: URL
    var reload: Int = 0
    var direct = false
    var referer: URL? = nil
    @State private var loading = true
    @State private var error: String?
    @StateObject private var nativePlayback = NativePlaybackModel()
    @Environment(\.scenePhase) private var scenePhase

    private var isVideoFile: Bool { ["m3u8", "mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) }

    var body: some View {
        ZStack {
            Color.black
            if secureURL(url.absoluteString) == nil {
                Text("Only secure HTTPS player addresses are supported.").foregroundStyle(.white).padding()
            } else if isVideoFile {
                VideoPlayer(player: nativePlayback.player)
                    .task(id: "\(url.absoluteString):\(reload)") {
                        await nativePlayback.load(url)
                    }
                if nativePlayback.loading { loadingIndicator("Loading video…") }
                if let error = nativePlayback.error { failureMessage(error) }
            } else {
                PlayerWebView(url: url, reload: reload, direct: direct, referer: referer, loading: $loading, error: $error)
                if loading {
                    loadingIndicator("Connecting to source…")
                }
                if let error {
                    failureMessage(error)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { nativePlayback.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { nativePlayback.pause() } }
    }

    private func loadingIndicator(_ message: String) -> some View {
        VStack(spacing: 12) { ProgressView().tint(.white); Text(message).font(.caption) }
            .foregroundStyle(.white).padding(20).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
    }

    private func failureMessage(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash").font(.title2)
            Text("Source couldn’t load").font(.headline)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            Text("Reload, switch providers, or open this source in Safari.").font(.caption).foregroundStyle(.white.opacity(0.7))
        }.foregroundStyle(.white).padding(24).frame(maxWidth: 400)
            .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).padding()
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
    @Binding var loading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
        webView.stopLoading()
        // Defer bindings until after SwiftUI's representable update cycle.
        DispatchQueue.main.async { loading = true; error = nil }
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
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PlayerWebView
        var key = ""
        var providerHost = ""
        init(_ parent: PlayerWebView) { self.parent = parent }

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
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
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
