import SwiftUI
import UIKit
import Combine

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
            observation = session.$item.combineLatest(session.$presentation).receive(on: RunLoop.main)
                .sink { [weak self, weak window] item, mode in
                    guard let self, let window else { return }
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
            window?.isHidden = true; window?.rootViewController = nil; window = nil
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
                        .frame(height: 60 + session.safeAreaInsets.top)
                    ProviderPlaybackSurface(url: item.url, reload: session.reload, direct: session.direct,
                        preservePlaybackOnBackground: true, systemPiP: pictureInPicture)
                        .id(item.id)
                    footer(item).padding(.bottom, session.safeAreaInsets.bottom)
                        .frame(height: 54 + session.safeAreaInsets.bottom)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(.black)
                .accessibilityElement(children: .contain).accessibilityIdentifier("sports-player")
                .accessibilityValue("\(item.title), \(session.sourceTitle)")
                .playerSwipeToDismiss { session.close() }
            }
        }.ignoresSafeArea().preferredColorScheme(.dark).foregroundStyle(.white).tint(.white)
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