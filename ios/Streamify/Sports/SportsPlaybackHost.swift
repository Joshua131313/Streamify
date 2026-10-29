import SwiftUI
import UIKit
import Combine
import WebKit

/// Fullscreen is an actual WebKit-owned window, not just a different player size.
/// Remember its ownership so PiP restoration cannot raise our empty placeholder
/// above it, and acquire app focus only after WebKit returns the inline surface.
struct SportsPlaybackWindowFocus {
    enum Target: Equatable { case application, player, provider }
    private(set) var target: Target = .application

    mutating func transition(expanded: Bool, providerFullscreen: Bool) -> Target? {
        let next: Target = expanded ? (providerFullscreen ? .provider : .player) : .application
        guard next != target else { return nil }
        target = next
        return next
    }
}

/// Landscape chrome overlays the video. Reserving portrait bars in a short
/// landscape viewport letterboxes an already aspect-fitted provider twice.
struct SportsPlayerVideoLayout {
    let size: CGSize
    let safeArea: UIEdgeInsets
    var isLandscape: Bool { size.width > size.height }
    var headerHeight: CGFloat { (isLandscape ? 60 : 108) + safeArea.top }
    var footerHeight: CGFloat { 54 + safeArea.bottom }
    var videoFrame: CGRect {
        CGRect(x: 0, y: isLandscape ? 0 : headerHeight, width: size.width,
               height: isLandscape ? size.height : max(0, size.height - headerHeight - footerHeight))
    }
}

/// A manually hosted player window does not inherit the SwiftUI App scene's
/// scenePhase. Observe its actual scene so live choices load on presentation
/// and polling pauses while that scene is inactive or in the background.
@MainActor
private final class SportsPlaybackSceneActivity: ObservableObject {
    @Published private(set) var isActive: Bool
    private var observations = Set<AnyCancellable>()

    init(scene: UIWindowScene) {
        isActive = scene.activationState == .foregroundActive
        NotificationCenter.default.publisher(for: UIScene.didActivateNotification, object: scene)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isActive = true }.store(in: &observations)
        for event in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
            NotificationCenter.default.publisher(for: event, object: scene)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.isActive = false }.store(in: &observations)
        }
        // The overlay owns this observer. Closing the session removes its
        // hosting controller, releasing these subscriptions and its task.
    }
}

/// This window retains one full-size source while AVKit/WebKit owns system PiP.
struct SportsPlaybackHost: UIViewRepresentable {
    let session: SportsPlaybackSession
    var apiBase: String = ""
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> SportsPlaybackAttachment {
        session.configureBackend(apiBase)
        let view = SportsPlaybackAttachment()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }
    func updateUIView(_ view: SportsPlaybackAttachment, context: Context) {
        session.configureBackend(apiBase)
        if let window = view.window { context.coordinator.attach(to: window) }
    }
    static func dismantleUIView(_ view: SportsPlaybackAttachment, coordinator: Coordinator) { coordinator.detach() }

    @MainActor final class Coordinator {
        private let session: SportsPlaybackSession
        private var window: SportsPlaybackWindow?
        private weak var applicationWindow: UIWindow?
        private var focus = SportsPlaybackWindowFocus()
        private var observation: AnyCancellable?
        init(session: SportsPlaybackSession) { self.session = session }
        func attach(to applicationWindow: UIWindow) {
            guard let scene = applicationWindow.windowScene else { return }
            guard window?.windowScene !== scene else { return }
            detach()
            self.applicationWindow = applicationWindow
            let window = SportsPlaybackWindow(windowScene: scene)
            window.session = session
            // WebKit presents element fullscreen in its own normal-level window.
            // An elevated app window covers that video with our black backdrop.
            window.windowLevel = .normal
            window.backgroundColor = .clear
            window.isHidden = session.item == nil
            self.window = window
            observation = session.$item.combineLatest(session.$presentation, session.pictureInPicture.$providerOwnsFullscreen)
                .receive(on: RunLoop.main)
                .sink { [weak self, weak window] item, mode, providerFullscreen in
                    guard let self, let window else { return }
                    guard item != nil else {
                        self.updateWindowFocus(expanded: false, providerFullscreen: false, window: window)
                        window.isHidden = true
                        window.rootViewController = nil
                        return
                    }
                    if window.rootViewController == nil {
                        guard let scene = window.windowScene else { return }
                        let controller = UIHostingController(rootView: SportsPlaybackOverlay(session: self.session,
                            activity: SportsPlaybackSceneActivity(scene: scene),
                            sourceFrame: { [weak self, weak window] in
                                guard let window else { return nil }
                                return self?.session.origin?.frame(in: window)
                            }).buttonStyle(HapticAutomaticButtonStyle()))
                        controller.view.backgroundColor = .clear
                        window.rootViewController = controller
                    }
                    // Hiding/removing a source view can stop PiP. Transparency
                    // preserves its view, size, player and WebKit document.
                    window.isHidden = false
                    window.alpha = mode == .expanded ? 1 : 0
                    window.accessibilityElementsHidden = mode != .expanded
                    self.updateWindowFocus(expanded: mode == .expanded, providerFullscreen: providerFullscreen, window: window)
                    window.rootViewController?.view.accessibilityElementsHidden = mode != .expanded
                    window.rootViewController?.view.accessibilityViewIsModal = mode == .expanded
                }
        }
        func detach() {
            observation?.cancel(); observation = nil
            if let window {
                updateWindowFocus(expanded: false, providerFullscreen: false, window: window)
            }
            window?.isHidden = true; window?.rootViewController = nil; window = nil
            applicationWindow = nil
        }
        private func updateWindowFocus(expanded: Bool, providerFullscreen: Bool, window: UIWindow) {
            guard let target = focus.transition(expanded: expanded, providerFullscreen: providerFullscreen) else { return }
            switch target {
            case .player:
                window.makeKeyAndVisible()
                window.rootViewController?.view.setNeedsLayout()
                window.rootViewController?.view.layoutIfNeeded()
            case .application:
                if let applicationWindow, !applicationWindow.isHidden { applicationWindow.makeKey() }
            case .provider:
                // WebKit owns the actual video and its controls until its
                // fullscreen-state observer confirms that it has returned.
                break
            }
        }
    }
}

final class SportsPlaybackAttachment: UIView {
    var attach: ((UIWindow) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if let window { attach?(window) } }
}

private final class SportsPlaybackWindow: UIWindow {
    weak var session: SportsPlaybackSession?
    var onPlayerTouch: (() -> Void)?
    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        // Observe delivery instead of competing with WebKit's recognizers.
        // A failed passive recognizer can miss later provider interactions.
        if session?.isExpanded == true, event.type == .touches,
           event.allTouches?.contains(where: { $0.phase == .began && $0.window === self }) == true {
            onPlayerTouch?()
        }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard session?.isExpanded == true else { return nil }
        return super.hitTest(point, with: event)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = safeAreaInsets
        DispatchQueue.main.async { [weak self] in self?.session?.updateSafeArea(insets) }
    }
}

private struct SportsPlaybackOverlay: View {
    @ObservedObject var session: SportsPlaybackSession
    @ObservedObject private var pictureInPicture: SportsSystemPiP
    @ObservedObject private var activity: SportsPlaybackSceneActivity
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sourceFrame: () -> CGRect?
    @State private var drag = CGSize.zero
    @State private var returnFrame: CGRect?
    @State private var dismissing = false
    @State private var dismissalToken = UUID()
    @State private var landscapeControlsVisible = false
    @State private var showChat = false
    @State private var landscapeOptionsVisible = true
    @State private var optionsHideTask: Task<Void, Never>?
    init(session: SportsPlaybackSession, activity: SportsPlaybackSceneActivity, sourceFrame: @escaping () -> CGRect?) {
        self.session = session
        self.activity = activity
        self.sourceFrame = sourceFrame
        _pictureInPicture = ObservedObject(wrappedValue: session.pictureInPicture)
    }
    var body: some View {
        GeometryReader { geometry in
            if let item = session.item {
                let rect = displayedFrame(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(dismissing ? 0 : max(0, 0.35 - Double(drag.height / max(1, geometry.size.height))))
                        .allowsHitTesting(false).accessibilityHidden(true)
                    playerCanvas(item, size: geometry.size)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(rect.width / max(1, geometry.size.width))
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : dismissing ? 20 : min(24, max(0, drag.height) / 5), style: .continuous))
                        .opacity(dismissing ? 0 : 1)
                        .position(x: rect.midX, y: rect.midY)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityElement(children: .contain).accessibilityIdentifier("sports-player")
                .accessibilityValue("\(item.title), \(session.sourceTitle)")
                .onChange(of: geometry.size) { _, _ in resetDismissal(); landscapeControlsVisible = false; revealLandscapeOptions() }
                .background {
                    SportsPlayerTouchObserver {
                        // Updating the hosting tree during a native Menu press
                        // can cancel its selection. Only the hidden affordance
                        // needs to react to a raw video touch.
                        if geometry.size.width > geometry.size.height && !landscapeControlsVisible && !showChat {
                            revealLandscapeOptions()
                        }
                    }.frame(width: 0, height: 0)
                }
                .onAppear(perform: revealLandscapeOptions)
                .onDisappear { optionsHideTask?.cancel(); optionsHideTask = nil }
            }
        }.ignoresSafeArea().preferredColorScheme(.dark).foregroundStyle(.white).tint(.white)
        // Keep the source layer mounted for system PiP while hiding its
        // invisible SwiftUI controls from VoiceOver and interaction.
        .accessibilityHidden(!session.isExpanded).allowsHitTesting(session.isExpanded)
        .sheet(isPresented: $showChat) {
            if let game = session.item?.game {
                SportsGameChatScreen(game: game, sceneIsActive: activity.isActive).presentationDetents([.medium, .large])
            }
        }
        .onChange(of: session.item?.game?.id) { _, _ in showChat = false }
        .onChange(of: showChat) { _, open in if !open { revealLandscapeOptions() } }
        .onChange(of: session.item?.id) { _, _ in resetDismissal() }
        .onChange(of: session.item?.url) { _, _ in resetDismissal() }
        .onChange(of: session.presentation) { _, _ in resetDismissal() }
        .onChange(of: activity.isActive) { _, active in if !active { resetDismissal() } }
        .task(id: "\(session.item?.id.uuidString ?? "")-\(activity.isActive)-\(session.isExpanded)") {
            guard activity.isActive, session.isExpanded else { return }
            repeat {
                await session.refreshLiveGames()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
        .alert("Couldn’t switch game", isPresented: Binding(get: { session.gameSelectionError != nil },
            set: { if !$0 { session.gameSelectionError = nil } })) {
                Button("OK") { session.gameSelectionError = nil }
        } message: { Text(session.gameSelectionError ?? "Your current stream is still playing.") }
        .alert("Picture in Picture", isPresented: Binding(get: { pictureInPicture.message != nil }, set: { if !$0 { pictureInPicture.message = nil } })) {
            Button("OK") { pictureInPicture.message = nil }
        } message: { Text(pictureInPicture.message ?? "This source could not start iOS Picture in Picture.") }
    }
    private func displayedFrame(in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        guard !reduceMotion else { return bounds }
        if dismissing {
            return returnFrame ?? CGRect(x: size.width * 0.12, y: size.height * 0.55,
                width: size.width * 0.76, height: size.height * 0.35)
        }
        let vertical = max(0, drag.height)
        let scale = 1 - min(0.18, SportsPlayerDismissPolicy.progress(translation: drag, size: size) * 0.3)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: (size.width - width) / 2 + drag.width * 0.2,
            y: (size.height - height) / 2 + vertical * 0.8, width: width, height: height)
    }
    private func finishDismissal(item: SportsPlaybackItem) {
        guard !dismissing, session.item?.id == item.id, session.isExpanded else { return }
        returnFrame = sourceFrame() ?? returnFrame
        let token = UUID()
        dismissalToken = token
        AppHaptics.tap()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete) {
            dismissing = true
        } completion: {
            guard dismissalToken == token, session.item?.id == item.id,
                  session.item?.url == item.url, session.isExpanded else { return }
            session.close()
        }
    }
    private func resetDismissal() {
        dismissalToken = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag = .zero; returnFrame = nil; dismissing = false }
    }
    private func playerCanvas(_ item: SportsPlaybackItem, size: CGSize) -> some View {
        let layout = SportsPlayerVideoLayout(size: size, safeArea: session.safeAreaInsets)
        let controlsVisible = !layout.isLandscape || landscapeControlsVisible
        return ZStack(alignment: .topLeading) {
            ProviderPlaybackSurface(url: item.url, reload: session.reload, direct: session.direct,
                preservePlaybackOnBackground: true, preferProviderControlsFullscreen: true, systemPiP: pictureInPicture,
                loadingGame: item.game, loadingSubtitle: session.sourceTitle)
                .id(item.id)
                .frame(width: layout.videoFrame.width, height: layout.videoFrame.height)
                .accessibilityElement(children: .contain).accessibilityIdentifier("sports-video-surface")
                .position(x: layout.videoFrame.midX, y: layout.videoFrame.midY)
                .sportsPlayerSwipeDownToDismiss(enabled: session.isExpanded && !dismissing,
                    onChanged: { translation in
                        if drag == .zero { returnFrame = sourceFrame() }
                        drag = translation
                    }, onEnded: { translation, velocity, cancelled in
                        if !cancelled && SportsPlayerDismissPolicy.shouldDismiss(translation: translation, velocity: velocity, size: size) {
                            finishDismissal(item: item)
                        } else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) { drag = .zero }
                        }
                    })
            if controlsVisible { VStack(spacing: 0) {
                header(item, landscape: layout.isLandscape)
                    .padding(.trailing, layout.isLandscape ? 48 : 0)
                    .padding(.top, session.safeAreaInsets.top).frame(height: layout.headerHeight)
                    .background(.black.opacity(layout.isLandscape ? 0.65 : 1))
                Spacer(minLength: 0)
                footer(item).padding(.bottom, session.safeAreaInsets.bottom).frame(height: layout.footerHeight)
                    .background(.black.opacity(layout.isLandscape ? 0.65 : 1))
            }
            .transition(.opacity) }
            if layout.isLandscape && (landscapeOptionsVisible || landscapeControlsVisible) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { landscapeControlsVisible.toggle() }
                        revealLandscapeOptions()
                    } label: {
                        Image(systemName: landscapeControlsVisible ? "chevron.up" : "ellipsis")
                            .font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }.buttonStyle(HapticPlainButtonStyle())
                        .accessibilityLabel(landscapeControlsVisible ? "Hide player options" : "Show player options")
                        .accessibilityIdentifier("sports-landscape-options")
                }.padding(.trailing, max(12, session.safeAreaInsets.right))
                    .padding(.top, session.safeAreaInsets.top + 6)
                    .transition(.opacity)
            }
        }
        .background(.black)
    }
    private func header(_ item: SportsPlaybackItem, landscape: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(action: session.close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close player").accessibilityIdentifier("sports-player-close")
                gamePicker(item)
                if landscape { sourcePicker(item); presentationButtons }
            }
            if !landscape {
                HStack(spacing: 8) { sourcePicker(item); presentationButtons }
            }
        }.padding(.horizontal, max(12, session.safeAreaInsets.left))
            .buttonStyle(HapticPlainButtonStyle())
    }

    private func gamePicker(_ item: SportsPlaybackItem) -> some View {
        Menu {
            if let current = item.game, !session.liveGames.contains(where: { $0.id == current.id }) {
                Label("Watching · \(current.league.title) · \(item.title)", systemImage: "checkmark")
            }
            ForEach(SportsLeague.allCases) { league in
                let games = session.liveGames.filter { $0.league == league }
                if !games.isEmpty {
                    Section(league.title) {
                        ForEach(games) { game in
                            Button {
                                AppHaptics.tap()
                                Task { await session.selectGame(game) }
                            } label: {
                                let name = "\(game.away.name) vs \(game.home.name)"
                                if item.game?.id == game.id { Label(name, systemImage: "checkmark") }
                                else { Text(name) }
                            }.accessibilityIdentifier("sports-player-game-option-\(game.id)")
                        }
                    }
                }
            }
            if session.liveGames.isEmpty {
                Text(session.gamesLoading ? "Finding live games…" : "No other live games right now")
            }
            if let error = session.gamesError { Text(error) }
            Button {
                AppHaptics.tap()
                Task { await session.refreshLiveGames(forceReload: true) }
            } label: { Label("Refresh live games", systemImage: "arrow.clockwise") }
        } label: {
            pickerLabel(caption: session.switchingGameID == nil ? "Game" : "Finding streams…",
                title: item.game.map { "\($0.league.title) · \(item.title)" } ?? item.title)
        }.buttonStyle(.plain).disabled(session.switchingGameID != nil)
            .accessibilityLabel("Switch live game")
            .accessibilityValue(item.game.map { "\($0.league.title), \($0.away.name) vs \($0.home.name)" } ?? item.title)
            .accessibilityIdentifier("sports-player-game-picker")
    }

    private func sourcePicker(_ item: SportsPlaybackItem) -> some View {
        Menu {
            ForEach(Array(item.sources.enumerated()), id: \.element.id) { index, source in
                Button {
                    AppHaptics.tap()
                    session.selectSource(source)
                } label: {
                    if source.url == item.url { Label(source.title, systemImage: "checkmark") }
                    else { Text(source.title) }
                }.accessibilityIdentifier("sports-player-source-option-\(index)")
            }
        } label: { pickerLabel(caption: "Stream", title: session.sourceTitle) }
            .buttonStyle(.plain).disabled(session.switchingGameID != nil)
            .accessibilityLabel("Switch stream source")
            .accessibilityValue("\(item.title), \(session.sourceTitle)")
            .accessibilityIdentifier("sports-player-source-picker")
    }

    private func pickerLabel(caption: String, title: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
        }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var presentationButtons: some View {
        Group {
            if session.item?.game != nil {
                Button { showChat = true } label: { Image(systemName: "bubble.left.and.bubble.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Game chat").accessibilityIdentifier("sports-player-chat")
            }
            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            Button(action: session.requestPictureInPicture) { Image(systemName: "pip.enter").frame(width: 44, height: 44) }
                .accessibilityLabel("Picture in Picture")
                .accessibilityValue(pictureInPicture.isRequesting ? "Starting" : pictureInPicture.capability.rawValue)
                .accessibilityIdentifier("sports-player-pip")
        }
    }
    private func revealLandscapeOptions() {
        landscapeOptionsVisible = true
        optionsHideTask?.cancel()
        optionsHideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, !landscapeControlsVisible, !showChat else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { landscapeOptionsVisible = false }
        }
    }
    private func footer(_ item: SportsPlaybackItem) -> some View {
        HStack(spacing: 8) {
            Button(action: session.reloadCurrent) { utilityLabel("Reload", symbol: "arrow.clockwise") }
                .accessibilityIdentifier("sports-player-reload")
            Button(action: session.toggleDirect) { utilityLabel(session.direct ? "Embed mode" : "Direct mode", symbol: "rectangle.on.rectangle") }
                .accessibilityIdentifier("sports-player-direct")
            Button { openURL(item.url) } label: { utilityLabel("Safari", symbol: "safari") }
                .accessibilityLabel("Open in browser").accessibilityIdentifier("sports-player-browser")
        }.font(.caption.weight(.semibold)).padding(.horizontal, max(12, session.safeAreaInsets.left)).buttonStyle(HapticPlainButtonStyle())
    }
    private func utilityLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).lineLimit(1).minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
    }
}

/// Records a touch without claiming it, cancelling controls or delaying WebKit.
private struct SportsPlayerTouchObserver: UIViewRepresentable {
    var onTouch: () -> Void
    func makeUIView(context: Context) -> ObserverView { ObserverView(onTouch: onTouch) }
    func updateUIView(_ view: ObserverView, context: Context) { view.onTouch = onTouch }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }
    final class ObserverView: UIView {
        var onTouch: () -> Void
        private weak var playerWindow: SportsPlaybackWindow?
        init(onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            playerWindow = window as? SportsPlaybackWindow
            playerWindow?.onPlayerTouch = { [weak self] in self?.onTouch() }
        }
        func detach() {
            playerWindow?.onPlayerTouch = nil
            playerWindow = nil
        }
    }
}
