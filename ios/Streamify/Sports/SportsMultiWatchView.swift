import SwiftUI
import WebKit

struct SportsMultiWatchView: View {
    @EnvironmentObject private var queue: SportsWatchQueue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: SportsStream?
    var body: some View {
        ScrollView {
            if queue.streams.isEmpty {
                StateMessage(symbol: "rectangle.split.2x2", title: "Build your game day", message: "Open a live game's Watch sources and add a source to multi-watch. You can keep up to four games here.").padding(.top, 70)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: sizeClass == .regular ? 2 : 1), spacing: 18) {
                    ForEach(queue.streams) { stream in SportsWatchTile(stream: stream, open: { selected = stream }, remove: { queue.remove(stream) }) }
                }.padding(16)
            }
        }.background(AppTheme.canvas).navigationTitle("Multi-watch · \(queue.streams.count)/4").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(item: $selected) { stream in ProviderPlayerView(title: stream.title, url: stream.url) }
    }
}

private struct SportsWatchTile: View {
    let stream: SportsStream
    let open: () -> Void
    let remove: () -> Void
    @State private var revision = 0
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                SportsTileWebView(url: stream.url, revision: revision, error: $error)
            }.aspectRatio(16.0 / 9.0, contentMode: .fit).clipped()
            if let error { Text(error).font(.caption).foregroundStyle(AppTheme.muted).padding(12) }
            HStack(spacing: 4) {
                Text(stream.title).font(.caption.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button { revision += 1; error = nil } label: { Image(systemName: "arrow.clockwise").frame(width: 40, height: 44) }.accessibilityLabel("Reload \(stream.title)")
                Button(action: open) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 40, height: 44) }.accessibilityLabel("Expand \(stream.title)")
                Button(action: remove) { Image(systemName: "xmark").frame(width: 40, height: 44) }.accessibilityLabel("Remove \(stream.title)")
            }.buttonStyle(.plain).padding(.leading, 14).padding(.trailing, 4)
        }.background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SportsTileWebView: UIViewRepresentable {
    let url: URL
    let revision: Int
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let key = "\(url.absoluteString)-\(revision)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        web.load(URLRequest(url: url))
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { web.stopLoading(); web.loadHTMLString("", baseURL: nil); web.navigationDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SportsTileWebView
        var loadedKey = ""
        init(_ parent: SportsTileWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            guard sportsHTTPSURL(url.absoluteString) != nil, let frame = navigationAction.targetFrame else { decisionHandler(.cancel); return }
            if frame.isMainFrame && url.host != parent.url.host { decisionHandler(.cancel) } else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { DispatchQueue.main.async { self.parent.error = "The source stopped. Reload or open it in the full player." } }
        private func show(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async { self.parent.error = "This source could not load. Reload or choose another source." }
        }
    }
}
