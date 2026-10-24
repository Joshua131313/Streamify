import SwiftUI
import WebKit

struct SportsMultiWatchView: View {
    @EnvironmentObject private var queue: SportsWatchQueue
    @EnvironmentObject private var playback: SportsPlaybackSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPicker = false
    @State private var audibleID: String?

    var body: some View {
        SportsWatchLayout {
            ForEach(queue.streams) { stream in
                SportsWatchTile(stream: stream,
                    audible: audibleID == stream.id && scenePhase == .active && playback.item == nil,
                    active: scenePhase == .active && playback.item == nil,
                    toggleAudio: { audibleID = audibleID == stream.id ? nil : stream.id },
                    selectSource: { queue.selectSource(streamID: stream.id, url: $0) },
                    open: { playback.play(title: stream.title, url: stream.url, sources: stream.availableSources) }, remove: { queue.remove(stream) })
                    .id(stream.id)
            }
            if queue.streams.isEmpty || queue.streams.count == 3 {
                VStack(spacing: 14) {
                    if queue.streams.isEmpty {
                        Image(systemName: "rectangle.split.2x2").font(.largeTitle).foregroundStyle(AppTheme.muted)
                        Text("Build your game day").font(.headline)
                        Text("Watch up to four games. Choose one stream to hear.")
                            .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
                    }
                    Button { showPicker = true } label: {
                        Label("Live games", systemImage: "plus").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).frame(minHeight: 44).streamifyControlSurface()
                    }.buttonStyle(.plain).accessibilityIdentifier("sports-multiwatch-add")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(3).background(Color.black).foregroundStyle(AppTheme.foreground)
        .navigationTitle("Multi-watch · \(queue.streams.count)/4").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if queue.streams.count < 4 {
                    Button { showPicker = true } label: { Label("Game", systemImage: "plus").frame(minHeight: 44) }
                        .accessibilityIdentifier("sports-multiwatch-add-toolbar")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-multiwatch-screen")
        .onAppear { if audibleID == nil { audibleID = queue.streams.first?.id } }
        .onChange(of: playback.isMinimized) { _, minimized in
            guard minimized else { return }
            showPicker = false
            dismiss()
        }
        .onChange(of: queue.streams.map(\.id)) { _, ids in
            if let audibleID, !ids.contains(audibleID) { self.audibleID = ids.first }
            if ids.count == 1 { audibleID = ids.first }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack { SportsLiveGamePicker { stream in
                if queue.streams.isEmpty { audibleID = stream.id }
                queue.add(stream); showPicker = false
            }.environmentObject(queue) }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }
}

/// A single stable layout retains each WKWebView as the queue grows or shrinks.
private struct SportsWatchLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 600)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = subviews.count >= 3 ? 2 : 1
        let rows = subviews.count >= 2 ? 2 : 1
        let width = bounds.width / CGFloat(columns), height = bounds.height / CGFloat(rows)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + CGFloat(index % columns) * width, y: bounds.minY + CGFloat(index / columns) * height),
                       anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
        }
    }
}

private struct SportsLiveGamePicker: View {
    let choose: (SportsStream) -> Void
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var queue: SportsWatchQueue
    @Environment(\.dismiss) private var dismiss
    @State private var games: [SportsGame] = []
    @State private var loading = true
    @State private var loadingGame: String?
    @State private var error: String?
    @State private var revision = 0
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Live now or starting within an hour").font(.subheadline).foregroundStyle(AppTheme.muted)
                if loading { ProgressView("Finding games…").frame(maxWidth: .infinity).padding(24) }
                if let error { Text(error).font(.footnote).foregroundStyle(AppTheme.muted) }
                if !loading && games.isEmpty {
                    StateMessage(symbol: "sportscourt", title: "No live games found", message: "Check again closer to game time.", actionTitle: "Refresh", action: { revision += 1 })
                }
                ForEach(games) { game in
                    Button { loadStream(game) } label: {
                        HStack(spacing: 12) {
                            Image("league-\(game.league.rawValue)").resizable().scaledToFit().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(game.away.abbreviation) vs \(game.home.abbreviation)").font(.subheadline.weight(.semibold))
                                Text(game.isLive ? "Live · \(game.status)" : game.date?.formatted(date: .omitted, time: .shortened) ?? "TBD").font(.caption).foregroundStyle(AppTheme.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if loadingGame == game.id { ProgressView() } else { Image(systemName: "play.fill") }
                        }.padding(14).frame(minHeight: 60).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 1) }
                    }.buttonStyle(.plain).disabled(loadingGame != nil || queue.streams.count >= 4)
                        .accessibilityIdentifier("sports-live-game-\(game.id)")
                }
            }.padding(20)
        }.background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
            .navigationTitle("Add a game").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .accessibilityIdentifier("sports-live-picker")
            .task(id: revision) { await loadGames() }
            .onDisappear { streamTask?.cancel() }
    }

    private func loadGames() async {
        loading = true; error = nil
        defer { loading = false }
        var loaded: [SportsGame] = [], unavailable = false
        // Include yesterday and tomorrow to cover live games across midnight.
        for offset in -1...1 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { continue }
            do {
                let result = try await SportsService(backend: settings.apiBase).schedule(leagues: SportsLeague.allCases, day: day)
                loaded += result.games; unavailable = unavailable || result.partial
            } catch is CancellationError { return }
            catch { unavailable = true }
        }
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        games = loaded.filter { game in
            seen.insert(game.id).inserted && game.canWatch
        }.sorted { lhs, rhs in lhs.isLive != rhs.isLive ? lhs.isLive : (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture) }
        if unavailable { error = "Some schedules are unavailable. Showing the games that loaded." }
    }

    private func loadStream(_ game: SportsGame) {
        guard loadingGame == nil, queue.streams.count < 4 else { return }
        loadingGame = game.id; error = nil
        streamTask = Task { @MainActor in
            defer { loadingGame = nil }
            do {
                let sources = try await SportsService().streams(game)
                guard let source = sources.first else { error = "No stream is available for this game yet. Try another game."; return }
                try Task.checkCancellation()
                guard !queue.streams.contains(where: { stream in stream.availableSources.contains { $0.url == source.url } }) else { error = "This game is already playing."; return }
                choose(SportsStream(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: source.url, alternatives: sources))
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct SportsWatchTile: View {
    let stream: SportsStream
    let audible: Bool
    let active: Bool
    let toggleAudio: () -> Void
    let selectSource: (URL) -> Void
    let open: () -> Void
    let remove: () -> Void
    @State private var revision = 0
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(stream.title).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
                Button(action: toggleAudio) { Image(systemName: audible ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(audible ? "Mute \(stream.title)" : "Listen to \(stream.title)")
                Menu {
                    Menu {
                        ForEach(stream.availableSources) { source in
                            Button { error = nil; selectSource(source.url) } label: {
                                if source.url == stream.url { Label(source.title, systemImage: "checkmark") }
                                else { Text(source.title) }
                            }
                        }
                    } label: { Label("Select stream", systemImage: "play.rectangle") }
                    Button("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right", action: open)
                    Button("Reload", systemImage: "arrow.clockwise") { revision += 1; error = nil }
                    Link(destination: stream.url) { Label("Open in browser", systemImage: "safari") }
                    Button("Remove", systemImage: "xmark", action: remove)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Options for \(stream.title)")
                    .accessibilityIdentifier("sports-tile-options-\(stream.id)")
            }.buttonStyle(.plain).background(AppTheme.panel)
            if let error { Text(error).font(.caption2).foregroundStyle(AppTheme.muted).padding(8) }
            SportsTileWebView(url: stream.url, revision: revision, audible: audible, active: active, error: $error)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        }.background(.black).clipShape(RoundedRectangle(cornerRadius: 10)).padding(3)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sports-watch-tile")
            .accessibilityValue(stream.availableSources.first { $0.url == stream.url }?.title ?? stream.title)
    }
}

private struct SportsTileWebView: UIViewRepresentable {
    let url: URL
    let revision: Int
    let audible: Bool
    let active: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(source: Self.audioScript(audible: audible), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .black; web.scrollView.isScrollEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let key = "\(url.absoluteString)-\(revision)"
        if context.coordinator.loadedKey != key {
            context.coordinator.loadedKey = key
            web.configuration.userContentController.removeAllUserScripts()
            web.configuration.userContentController.addUserScript(WKUserScript(source: Self.audioScript(audible: audible && active), injectionTime: .atDocumentStart, forMainFrameOnly: false))
            #if DEBUG
            if PreviewFixtures.enabled { web.loadHTMLString(PreviewFixtures.playerHTML, baseURL: url) }
            else { web.load(URLRequest(url: url)) }
            #else
            web.load(URLRequest(url: url))
            #endif
        }
        let state = "\(audible && active)-\(active)"
        if context.coordinator.mediaState != state {
            context.coordinator.mediaState = state
            web.evaluateJavaScript(Self.audioUpdate(audible: audible && active))
            web.setAllMediaPlaybackSuspended(!active, completionHandler: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.evaluateJavaScript(audioUpdate(audible: false))
        web.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        web.stopLoading(); web.navigationDelegate = nil
        web.configuration.userContentController.removeAllUserScripts()
        web.loadHTMLString("", baseURL: nil)
    }

    private static func audioUpdate(audible: Bool) -> String {
        "window.postMessage({streamifyAudio: true, audible: \(audible ? "true" : "false")}, '*');"
    }

    /// Install in every frame. Parent messages propagate into cross-origin
    /// embeds, and providers cannot unmute an unselected HTML media element.
    private static func audioScript(audible: Bool) -> String {
        """
        (() => {
          if (window.__streamifyAudioInstalled) return;
          window.__streamifyAudioInstalled = true;
          let audible = \(audible ? "true" : "false");
          const proto = HTMLMediaElement.prototype;
          const muted = Object.getOwnPropertyDescriptor(proto, 'muted');
          if (!muted || !muted.set || !muted.get) return;
          Object.defineProperty(proto, 'muted', {configurable:true, get:muted.get,
            set(value) { muted.set.call(this, audible ? value : true); }});
          const apply = () => document.querySelectorAll('video,audio').forEach(v => {
            if (muted.get.call(v) !== !audible) muted.set.call(v, !audible);
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
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SportsTileWebView
        var loadedKey = ""
        var mediaState = ""
        init(_ parent: SportsTileWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            guard sportsHTTPSURL(url.absoluteString) != nil, let frame = navigationAction.targetFrame else { decisionHandler(.cancel); return }
            decisionHandler(frame.isMainFrame && url.host != parent.url.host ? .cancel : .allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(SportsTileWebView.audioUpdate(audible: parent.audible && parent.active))
            webView.setAllMediaPlaybackSuspended(!parent.active, completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DispatchQueue.main.async { self.parent.error = "Source unavailable. Use options to retry." }
        }
        private func show(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async { self.parent.error = "Source unavailable. Use options to retry." }
        }
    }
}
