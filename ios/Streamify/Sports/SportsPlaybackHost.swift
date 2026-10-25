import SwiftUI
import UIKit
import Combine

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

/// This window retains one full-size source while AVKit/WebKit owns system PiP.
struct SportsPlaybackHost: UIViewRepresentable {
    let session: SportsPlaybackSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> SportsPlaybackAttachment {
        let view = SportsPlaybackAttachment()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }
    func updateUIView(_ view: SportsPlaybackAttachment, context: Context) {
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
                        let controller = UIHostingController(rootView: SportsPlaybackOverlay(session: self.session,
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
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sourceFrame: () -> CGRect?
    @State private var drag = CGSize.zero
    @State private var returnFrame: CGRect?
    @State private var dismissing = false
    @State private var dismissalToken = UUID()
    init(session: SportsPlaybackSession, sourceFrame: @escaping () -> CGRect?) {
        self.session = session
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
                .onChange(of: geometry.size) { _, _ in resetDismissal() }
            }
        }.ignoresSafeArea().preferredColorScheme(.dark).foregroundStyle(.white).tint(.white)
        .onChange(of: session.item?.id) { _, _ in resetDismissal() }
        .onChange(of: session.item?.url) { _, _ in resetDismissal() }
        .onChange(of: session.presentation) { _, _ in resetDismissal() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { resetDismissal() } }
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
        VStack(spacing: 0) {
            header(item).padding(.top, session.safeAreaInsets.top)
                .frame(height: 60 + session.safeAreaInsets.top)
            ProviderPlaybackSurface(url: item.url, reload: session.reload, direct: session.direct,
                preservePlaybackOnBackground: true, preferProviderControlsFullscreen: true, systemPiP: pictureInPicture)
                .id(item.id)
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
            footer(item).padding(.bottom, session.safeAreaInsets.bottom)
                .frame(height: 54 + session.safeAreaInsets.bottom)
        }
        .background(.black)
    }
    private func header(_ item: SportsPlaybackItem) -> some View {
        HStack(spacing: 8) {
            Button(action: session.close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Close player").accessibilityIdentifier("sports-player-close")
            Menu {
                ForEach(Array(item.sources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        AppHaptics.tap()
                        session.selectSource(source)
                    } label: {
                        if source.url == item.url { Label(source.title, systemImage: "checkmark") }
                        else { Text(source.title) }
                    }.buttonStyle(.automatic)
                        .accessibilityIdentifier("sports-player-source-option-\(index)")
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline).lineLimit(1)
                        Text(session.sourceTitle).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Switch stream source")
                .accessibilityValue("\(item.title), \(session.sourceTitle)").accessibilityIdentifier("sports-player-source-picker")
            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            Button(action: session.requestPictureInPicture) { Image(systemName: "pip.enter").frame(width: 44, height: 44) }
                .accessibilityLabel("Picture in Picture")
                .accessibilityValue(pictureInPicture.isRequesting ? "Starting" : pictureInPicture.capability.rawValue)
                .accessibilityIdentifier("sports-player-pip")
        }.padding(.horizontal, max(8, session.safeAreaInsets.left)).buttonStyle(HapticPlainButtonStyle())
    }
    private func footer(_ item: SportsPlaybackItem) -> some View {
        HStack(spacing: 16) {
            Button(action: session.reloadCurrent) { Label("Reload", systemImage: "arrow.clockwise").frame(minHeight: 44) }
            Spacer(minLength: 0)
            Button(action: session.toggleDirect) { Label(session.direct ? "Embed mode" : "Direct mode", systemImage: "rectangle.on.rectangle").frame(minHeight: 44) }
            Spacer(minLength: 0)
            Button { openURL(item.url) } label: { Image(systemName: "safari").frame(width: 44, height: 44) }.accessibilityLabel("Open in browser")
        }.font(.caption.weight(.semibold)).padding(.horizontal, max(16, session.safeAreaInsets.left)).buttonStyle(HapticPlainButtonStyle())
    }
}
