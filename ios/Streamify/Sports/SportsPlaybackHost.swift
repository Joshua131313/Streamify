import SwiftUI
import UIKit
import Combine

enum SportsFullscreenOrientationPolicy {
    static func restoreMask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .allButUpsideDown
        }
    }
}

/// This window retains one full-size source while AVKit/WebKit owns system PiP.
struct SportsPlaybackHost: UIViewRepresentable {
    let session: SportsPlaybackSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> SportsPlaybackAttachment {
        let view = SportsPlaybackAttachment()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] scene in coordinator?.attach(to: scene) }
        return view
    }
    func updateUIView(_ view: SportsPlaybackAttachment, context: Context) {
        if let scene = view.window?.windowScene { context.coordinator.attach(to: scene) }
    }
    static func dismantleUIView(_ view: SportsPlaybackAttachment, coordinator: Coordinator) { coordinator.detach() }

    @MainActor final class Coordinator {
        private let session: SportsPlaybackSession
        private var window: SportsPlaybackWindow?
        private var observation: AnyCancellable?
        private var requestedFullscreenGeometry = false
        private var previousOrientation: UIInterfaceOrientationMask?
        init(session: SportsPlaybackSession) { self.session = session }
        func attach(to scene: UIWindowScene) {
            guard window?.windowScene !== scene else { return }
            detach()
            let window = SportsPlaybackWindow(windowScene: scene)
            window.session = session
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            window.backgroundColor = .clear
            window.isHidden = session.item == nil
            self.window = window
            observation = session.$item.combineLatest(session.$presentation, session.$isVideoFullscreen).receive(on: RunLoop.main)
                .sink { [weak self, weak window] item, mode, fullscreen in
                    guard let self, let window else { return }
                    self.updateFullscreenGeometry(active: item != nil && mode == .expanded && fullscreen, window: window)
                    guard item != nil else {
                        window.isHidden = true
                        window.rootViewController = nil
                        return
                    }
                    if window.rootViewController == nil {
                        let controller = UIHostingController(rootView: SportsPlaybackOverlay(session: self.session).buttonStyle(HapticAutomaticButtonStyle()))
                        controller.view.backgroundColor = .clear
                        window.rootViewController = controller
                    }
                    // Hiding/removing a source view can stop PiP. Transparency
                    // preserves its view, size, player and WebKit document.
                    window.isHidden = false
                    window.alpha = mode == .expanded ? 1 : 0
                    window.rootViewController?.view.accessibilityElementsHidden = mode != .expanded
                    window.rootViewController?.view.accessibilityViewIsModal = mode == .expanded
                }
        }
        func detach() {
            observation?.cancel(); observation = nil
            if let window { updateFullscreenGeometry(active: false, window: window) }
            window?.isHidden = true; window?.rootViewController = nil; window = nil
        }
        private func updateFullscreenGeometry(active: Bool, window: UIWindow) {
            guard active != requestedFullscreenGeometry, let scene = window.windowScene else { return }
            requestedFullscreenGeometry = active
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if active {
                if previousOrientation == nil { previousOrientation = SportsFullscreenOrientationPolicy.restoreMask(for: scene.interfaceOrientation) }
                // This is a request; iOS can decline it (for example in a
                // constrained window). Fullscreen still fills the current scene.
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            } else if let previousOrientation {
                // Keep the original orientation while PiP temporarily exposes
                // the app, including when iOS defers a background geometry request.
                if !session.isVideoFullscreen || session.item == nil { self.previousOrientation = nil }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: previousOrientation))
            }
        }
    }
}

final class SportsPlaybackAttachment: UIView {
    var attach: ((UIWindowScene) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if let scene = window?.windowScene { attach?(scene) } }
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
    init(session: SportsPlaybackSession) {
        self.session = session
        _pictureInPicture = ObservedObject(wrappedValue: session.pictureInPicture)
    }
    var body: some View {
        GeometryReader { geometry in
            if let item = session.item {
                VStack(spacing: 0) {
                    header(item).padding(.top, session.safeAreaInsets.top)
                        .frame(height: session.isVideoFullscreen ? 0 : 60 + session.safeAreaInsets.top)
                        .clipped().opacity(session.isVideoFullscreen ? 0 : 1)
                        .allowsHitTesting(!session.isVideoFullscreen).accessibilityHidden(session.isVideoFullscreen)
                    ProviderPlaybackSurface(url: item.url, reload: session.reload, direct: session.direct,
                        preservePlaybackOnBackground: true, systemPiP: pictureInPicture)
                        .id(item.id)
                    footer(item).padding(.bottom, session.safeAreaInsets.bottom)
                        .frame(height: session.isVideoFullscreen ? 0 : 54 + session.safeAreaInsets.bottom)
                        .clipped().opacity(session.isVideoFullscreen ? 0 : 1)
                        .allowsHitTesting(!session.isVideoFullscreen).accessibilityHidden(session.isVideoFullscreen)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(.black)
                .overlay(alignment: .topTrailing) {
                    if session.isVideoFullscreen {
                        Button(action: session.toggleVideoFullscreen) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(.black.opacity(0.7), in: Circle())
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(HapticPlainButtonStyle())
                            .accessibilityLabel("Exit fullscreen").accessibilityIdentifier("sports-player-exit-fullscreen")
                            .padding(.trailing, max(12, session.safeAreaInsets.right))
                            .padding(.top, max(8, session.safeAreaInsets.top))
                    }
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("sports-player")
                .accessibilityValue("\(item.title), \(session.sourceTitle)")
                .playerSwipeToDismiss { session.close() }
            }
        }.ignoresSafeArea().preferredColorScheme(.dark).foregroundStyle(.white).tint(.white)
        .statusBarHidden(session.isVideoFullscreen)
        .persistentSystemOverlays(session.isVideoFullscreen ? .hidden : .automatic)
        .alert("Picture in Picture", isPresented: Binding(get: { pictureInPicture.message != nil }, set: { if !$0 { pictureInPicture.message = nil } })) {
            Button("OK") { pictureInPicture.message = nil }
        } message: { Text(pictureInPicture.message ?? "This source could not start iOS Picture in Picture.") }
    }
    private func header(_ item: SportsPlaybackItem) -> some View {
        HStack(spacing: 8) {
            Button(action: session.close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Close player").accessibilityIdentifier("sports-player-close")
            Menu {
                ForEach(Array(item.sources.enumerated()), id: \.element.id) { index, source in
                    Button { session.selectSource(source) } label: {
                        if source.url == item.url { Label(source.title, systemImage: "checkmark") }
                        else { Text(source.title) }
                    }.accessibilityIdentifier("sports-player-source-option-\(index)")
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline).lineLimit(1)
                        Text(session.sourceTitle).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Switch stream source")
                .accessibilityValue("\(item.title), \(session.sourceTitle)").accessibilityIdentifier("sports-player-source-picker")
            Button(action: session.toggleVideoFullscreen) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Fullscreen").accessibilityIdentifier("sports-player-fullscreen")
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
