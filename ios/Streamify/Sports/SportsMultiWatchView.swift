import SwiftUI
import WebKit

struct SportsMultiWatchView: View {
    @EnvironmentObject private var queue: SportsWatchQueue
    @EnvironmentObject private var playback: SportsPlaybackSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPicker = false
    @StateObject private var audio = SportsMultiWatchAudio()
    private var tilesActive: Bool { scenePhase == .active && playback.item == nil }

    var body: some View {
        SportsWatchLayout {
            ForEach(queue.streams) { stream in
                SportsWatchTile(stream: stream,
                    audible: audio.audibleID == stream.id && tilesActive,
                    active: tilesActive, audio: audio,
                    toggleAudio: { audio.select(audio.selectedID == stream.id ? nil : stream.id) },
                    selectSource: { queue.selectSource(streamID: stream.id, url: $0) },
                    open: { origin in playback.play(title: stream.title, url: stream.url, sources: stream.availableSources, origin: origin) }, remove: { queue.remove(stream) })
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
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-multiwatch-add")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(3).background(Color.black).foregroundStyle(AppTheme.foreground)
        .safeAreaInset(edge: .bottom) {
            if let error = audio.errorMessage {
                HStack(spacing: 12) {
                    Text(error).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Retry") { audio.retry() }.frame(minWidth: 44, minHeight: 44)
                }.padding(.horizontal, 12).background(AppTheme.panel)
                    .accessibilityIdentifier("sports-multiwatch-audio-error")
            }
        }
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
        .onAppear {
            #if DEBUG
            if PreviewFixtures.enabled, ProcessInfo.processInfo.arguments.contains("--ui-multiwatch-two"), queue.streams.isEmpty {
                queue.add(SportsStream(title: "Game one", url: URL(string: "https://fixture.streamify.test/multi-one")!))
                queue.add(SportsStream(title: "Game two", url: URL(string: "https://fixture.streamify.test/multi-two")!))
            }
            #endif
            if audio.selectedID == nil { audio.select(queue.streams.first?.id) }
        }
        .onChange(of: tilesActive, initial: true) { _, active in audio.setActive(active) }
        .onDisappear { audio.setActive(false) }
        .onChange(of: playback.isMinimized) { _, minimized in
            guard minimized else { return }
            showPicker = false
            dismiss()
        }
        .onChange(of: queue.streams.map(\.id)) { _, ids in
            if let selected = audio.selectedID, !ids.contains(selected) { audio.select(ids.first) }
            if ids.count == 1 { audio.select(ids.first) }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack { SportsLiveGamePicker { stream in
                if queue.streams.isEmpty { audio.select(stream.id) }
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
        let columns = subviews.count >= 3 || (subviews.count == 2 && bounds.width > bounds.height) ? 2 : 1
        let rows = max(1, (subviews.count + columns - 1) / columns)
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
                    }.buttonStyle(HapticPlainButtonStyle()).disabled(loadingGame != nil || queue.streams.count >= 4)
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
    let audio: SportsMultiWatchAudio
    let toggleAudio: () -> Void
    let selectSource: (URL) -> Void
    let open: (SportsPlaybackOrigin) -> Void
    let remove: () -> Void
    @StateObject private var playbackOrigin = SportsPlaybackOrigin()
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
                            Button {
                                AppHaptics.tap()
                                error = nil; selectSource(source.url)
                            } label: {
                                if source.url == stream.url { Label(source.title, systemImage: "checkmark") }
                                else { Text(source.title) }
                            }.buttonStyle(.automatic)
                        }
                    } label: { Label("Select stream", systemImage: "play.rectangle") }
                        .buttonStyle(.plain)
                    Button("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right") {
                        AppHaptics.tap(); open(playbackOrigin)
                    }.buttonStyle(.automatic)
                    Button("Reload", systemImage: "arrow.clockwise") {
                        AppHaptics.tap(); revision += 1; error = nil
                    }.buttonStyle(.automatic)
                    Link(destination: stream.url) { Label("Open in browser", systemImage: "safari") }
                        .buttonStyle(.automatic)
                    Button("Remove", systemImage: "xmark") {
                        AppHaptics.tap(); remove()
                    }.buttonStyle(.automatic)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Options for \(stream.title)")
                    .accessibilityIdentifier("sports-tile-options-\(stream.id)")
            }.buttonStyle(HapticPlainButtonStyle()).background(AppTheme.panel)
            if let error { Text(error).font(.caption2).foregroundStyle(.white.opacity(0.75)).padding(8) }
            SportsTileWebView(streamID: stream.id, audio: audio, url: stream.url, revision: revision, active: active, error: $error)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        }.background(.black).clipShape(RoundedRectangle(cornerRadius: 10)).padding(3)
            .sportsPlaybackOrigin(playbackOrigin)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sports-watch-tile")
            .accessibilityValue(stream.availableSources.first { $0.url == stream.url }?.title ?? stream.title)
    }
}

private struct SportsTileWebView: UIViewRepresentable {
    let streamID: String
    let audio: SportsMultiWatchAudio
    let url: URL
    let revision: Int
    let active: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "streamifyTileAudio")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.audioScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.isOpaque = false; web.backgroundColor = .black; web.scrollView.isScrollEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let key = "\(url.absoluteString)-\(revision)"
        if context.coordinator.loadedKey != key {
            context.coordinator.loadedKey = key
            web.configuration.userContentController.removeAllUserScripts()
            web.configuration.userContentController.addUserScript(WKUserScript(source: Self.audioScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            #if DEBUG
            if PreviewFixtures.enabled {
                let html = ProcessInfo.processInfo.arguments.contains("--ui-multiwatch-two") ? Self.rotationFixtureHTML : PreviewFixtures.playerHTML
                web.loadHTMLString(html, baseURL: url)
            }
            else { web.load(URLRequest(url: url)) }
            #else
            web.load(URLRequest(url: url))
            #endif
        }
        let state = "\(active)"
        if context.coordinator.mediaState != state {
            context.coordinator.mediaState = state
            web.setAllMediaPlaybackSuspended(!active, completionHandler: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.retire(web)
    }

    /// Install in every frame. Parent messages propagate into cross-origin
    /// embeds, and providers cannot unmute an unselected HTML media element.
    private static var audioScript: String {
        """
        (() => {
          if (window.__streamifyAudioInstalled) return;
          window.__streamifyAudioInstalled = true;
          let audible = false;
          let nextRequest = 0;
          const pending = new Map();
          const proto = HTMLMediaElement.prototype;
          const muted = Object.getOwnPropertyDescriptor(proto, 'muted');
          if (!muted || !muted.set || !muted.get) return;
          Object.defineProperty(proto, 'muted', {configurable:true, get:muted.get,
            set(value) { muted.set.call(this, audible ? value : true); }});
          const apply = () => document.querySelectorAll('video,audio').forEach(v => {
            if (muted.get.call(v) !== !audible) muted.set.call(v, !audible);
          });
          window.__streamifySetAudible = async value => {
            audible = value === true; apply();
            const acknowledgements = [];
            for (let i=0; i<frames.length; i++) {
              const child = frames[i], requestID = String(++nextRequest);
              acknowledgements.push(new Promise((resolve, reject) => {
                const timer = setTimeout(() => { pending.delete(requestID); reject(new Error('Audio frame did not acknowledge')); }, 1500);
                pending.set(requestID, {child, finish: ok => { clearTimeout(timer); pending.delete(requestID); ok ? resolve() : reject(new Error('Audio frame failed')); }});
                child.postMessage({streamifyAudio:true, audible, requestID}, '*');
              }));
            }
            const results = await Promise.allSettled(acknowledgements);
            if (results.some(result => result.status === 'rejected')) throw new Error('Audio frame did not acknowledge');
            return true;
          };
          window.addEventListener('message', e => {
            if (e.data?.streamifyAudioAck === true) {
              const request = pending.get(e.data.requestID);
              if (request && e.source === request.child) request.finish(e.data.ok === true);
              return;
            }
            if (e.source !== window && e.source !== parent) return;
            if (e.data?.streamifyAudio !== true || typeof e.data.audible !== 'boolean' || typeof e.data.requestID !== 'string') return;
            const source = e.source, requestID = e.data.requestID;
            window.__streamifySetAudible(e.data.audible).then(
              () => source.postMessage({streamifyAudioAck:true, requestID, ok:true}, '*'),
              () => source.postMessage({streamifyAudioAck:true, requestID, ok:false}, '*'));
          });
          document.addEventListener('play', apply, true);
          document.addEventListener('volumechange', () => { if (!audible) apply(); }, true);
          new MutationObserver(apply).observe(document, {childList:true, subtree:true});
          apply();
          // A provider can create/navigate its actual media iframe after the
          // main document finishes. Re-enter the native serial mute barrier;
          // never let a late frame unmute itself independently.
          window.webkit?.messageHandlers?.streamifyTileAudio?.postMessage({ready:true});
        })();
        """
    }

    #if DEBUG
    /// Real bundled media exposes its playback state for rotation/audio UI
    /// checks; no provider, external request or synthetic playback flag.
    private static var rotationFixtureHTML: String {
        let data = Bundle.main.url(forResource: "offline-player", withExtension: "mp4")
            .flatMap { try? Data(contentsOf: $0) }?.base64EncodedString() ?? ""
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#111;color:white;font:10px -apple-system}video{width:100%;height:calc(100% - 42px);object-fit:contain}p{margin:2px 4px}</style>
        </head><body><video id="video" autoplay muted loop playsinline src="data:video/mp4;base64,\(data)"></video>
        <p id="document"></p><p id="state"></p><p id="time"></p><script>
        const video=document.getElementById('video');
        document.getElementById('document').textContent='Multi-watch document '+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
        function report(){
          const state='Multi-watch media '+(video.paused?'paused':'playing')+' '+(video.muted?'muted':'audible');
          if(document.getElementById('state').textContent!==state)document.getElementById('state').textContent=state;
          const time='Multi-watch time '+Math.floor(video.currentTime*10);
          if(document.getElementById('time').textContent!==time)document.getElementById('time').textContent=time;
        }
        ['playing','pause','volumechange','loadeddata'].forEach(event=>video.addEventListener(event,report));setInterval(report,250);report();
        </script></body></html>
        """
    }
    #endif

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, SportsMultiWatchAudioTarget {
        var parent: SportsTileWebView
        weak var web: WKWebView?
        var loadedKey = ""
        var mediaState = ""
        private var retiring = false
        private var retirementConfirmed = false
        private var retirementWaiters: [CheckedContinuation<Void, Never>] = []
        init(_ parent: SportsTileWebView) { self.parent = parent }
        func setAudible(_ audible: Bool) async throws {
            if retiring {
                if !retirementConfirmed { await withCheckedContinuation { retirementWaiters.append($0) } }
                return
            }
            guard let web else { return }
            _ = try await web.callAsyncJavaScript("return await window.__streamifySetAudible(audible);",
                arguments: ["audible": audible], in: nil, contentWorld: .page)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !retiring, message.name == "streamifyTileAudio", let body = message.body as? [String: Any], body["ready"] as? Bool == true else { return }
            parent.audio.retry()
        }
        func retire(_ web: WKWebView, processTerminated: Bool = false) {
            guard !retiring else { return }
            retiring = true
            parent.audio.unregister(self, id: parent.streamID)
            if processTerminated { confirmRetirement(); return }
            web.navigationDelegate = nil
            // This is teardown, never an audio-button operation. Keep this
            // target in the mute barrier until WebKit confirms media stopped.
            web.setAllMediaPlaybackSuspended(true) {
                self.confirmRetirement()
                web.stopLoading()
                web.configuration.userContentController.removeScriptMessageHandler(forName: "streamifyTileAudio")
                web.configuration.userContentController.removeAllUserScripts()
                web.loadHTMLString("", baseURL: nil)
            }
        }
        private func confirmRetirement() {
            retirementConfirmed = true
            let waiters = retirementWaiters
            retirementWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            guard sportsHTTPSURL(url.absoluteString) != nil, let frame = navigationAction.targetFrame else { decisionHandler(.cancel); return }
            decisionHandler(frame.isMainFrame && url.host != parent.url.host ? .cancel : .allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retiring = false; retirementConfirmed = false
            webView.setAllMediaPlaybackSuspended(!parent.active, completionHandler: nil)
            parent.audio.register(self, id: parent.streamID)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            retire(webView, processTerminated: true)
            DispatchQueue.main.async { self.parent.error = "Source unavailable. Use options to retry." }
        }
        private func show(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async { self.parent.error = "Source unavailable. Use options to retry." }
        }
    }
}
