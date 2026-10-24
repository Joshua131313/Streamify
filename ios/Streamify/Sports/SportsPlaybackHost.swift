import SwiftUI
import UIKit
import Combine

/// A non-key window keeps the same player above native game/queue sheets. It
/// forwards touches outside the minimized card to the app's original window.
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
        private var keyboardObservation: AnyCancellable?
        init(session: SportsPlaybackSession) { self.session = session }
        func attach(to scene: UIWindowScene) {
            guard window?.windowScene !== scene else { return }
            detach()
            let window = SportsPlaybackWindow(windowScene: scene)
            window.session = session
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            window.backgroundColor = .clear
            let controller = UIHostingController(rootView: SportsPlaybackOverlay(session: session))
            controller.view.backgroundColor = .clear
            window.rootViewController = controller
            window.isHidden = session.item == nil
            // Do not call makeKeyAndVisible: search and keyboard stay attached to
            // the normal app window while the miniature player is visible.
            self.window = window
            observation = session.$item.combineLatest(session.$presentation).sink { [weak window] item, mode in
                window?.isHidden = item == nil
                window?.rootViewController?.view.accessibilityViewIsModal = item != nil && mode == .expanded
            }
            keyboardObservation = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
                .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
                .receive(on: RunLoop.main).sink { [weak self, weak window] notification in
                    guard let self, let window else { return }
                    if notification.name == UIResponder.keyboardWillHideNotification { self.session.updateKeyboardInset(0); return }
                    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                    let keyboard = window.convert(frame, from: nil)
                    self.session.updateKeyboardInset(keyboard.intersects(window.bounds) ? max(0, window.bounds.maxY - keyboard.minY) : 0)
                }
        }
        func detach() {
            observation?.cancel(); observation = nil
            keyboardObservation?.cancel(); keyboardObservation = nil
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
        guard let session, session.item != nil else { return nil }
        if session.isMinimized && !session.interactionFrame.contains(point) { return nil }
        return super.hitTest(point, with: event)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = safeAreaInsets
        DispatchQueue.main.async { [weak self] in self?.session?.updateSafeArea(insets) }
    }
}

private struct SportsPlaybackBounds: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct SportsPlaybackOverlay: View {
    @ObservedObject var session: SportsPlaybackSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var drag = CGSize.zero
    @State private var parked = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            if let item = session.item {
                let frame = playerFrame(in: geometry.size)
                VStack(spacing: 0) {
                    header(item)
                        .padding(.top, session.isExpanded ? session.safeAreaInsets.top : 0)
                        .frame(height: session.isExpanded ? 60 + session.safeAreaInsets.top : 0)
                        .opacity(session.isExpanded ? 1 : 0).clipped().allowsHitTesting(session.isExpanded).accessibilityHidden(!session.isExpanded)
                    ProviderPlaybackSurface(url: item.url, reload: session.reload, direct: session.direct,
                        preservePlaybackOnBackground: true)
                        .id(item.id)
                        .allowsHitTesting(session.isExpanded).accessibilityHidden(!session.isExpanded)
                    footer(item)
                        .padding(.bottom, session.isExpanded ? session.safeAreaInsets.bottom : 0)
                        .frame(height: session.isExpanded ? 54 + session.safeAreaInsets.bottom : 0)
                        .opacity(session.isExpanded ? 1 : 0).clipped().allowsHitTesting(session.isExpanded).accessibilityHidden(!session.isExpanded)
                }
                .frame(width: frame.width, height: frame.height)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: session.isExpanded ? 0 : 14))
                .overlay {
                    if session.isMinimized { miniControls(item) }
                }
                .overlay { if session.isMinimized { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1) } }
                .shadow(color: .black.opacity(session.isExpanded ? 0 : 0.45), radius: 14, y: 5)
                .offset(x: frame.minX, y: frame.minY)
                .background {
                    Color.clear.preference(key: SportsPlaybackBounds.self, value: frame)
                }
                .onPreferenceChange(SportsPlaybackBounds.self) { session.interactionFrame = $0 }
                .playerSwipeToDismiss { if session.isExpanded { session.close() } }
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                    guard session.isMinimized else { return }; drag = value.translation
                }.onEnded { value in
                    guard session.isMinimized else { return }
                    let settled = playerFrame(in: geometry.size)
                    let insets = session.safeAreaInsets
                    let baseX = max(insets.left + 12, geometry.size.width - insets.right - settled.width - 12)
                    let bottomClearance = max(insets.bottom + 78, session.keyboardInset + 12)
                    let baseY = max(insets.top + 12, geometry.size.height - settled.height - bottomClearance)
                    parked = CGSize(width: settled.minX - baseX, height: settled.minY - baseY); drag = .zero
                })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(session.isMinimized ? "sports-mini-player" : "sports-player")
                .accessibilityValue("\(item.title), \(session.sourceTitle)")
                .onChange(of: session.presentation) { _, mode in if mode == .expanded { drag = .zero; parked = .zero } }
            }
        }
        .ignoresSafeArea().preferredColorScheme(.dark).foregroundStyle(.white).tint(.white)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: session.presentation)
    }

    private func playerFrame(in size: CGSize) -> CGRect {
        guard session.isMinimized else { return CGRect(origin: .zero, size: size) }
        let insets = session.safeAreaInsets
        let width = min(320, max(200, size.width * 0.48))
        let height = width * 9 / 16
        let left = insets.left + 12, right = max(left, size.width - insets.right - width - 12)
        let bottomClearance = max(insets.bottom + 78, session.keyboardInset + 12)
        let top = insets.top + 12, bottom = max(top, size.height - height - bottomClearance)
        return CGRect(x: min(right, max(left, right + parked.width + drag.width)),
            y: min(bottom, max(top, bottom + parked.height + drag.height)), width: width, height: height)
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
            }.buttonStyle(.plain).accessibilityLabel("Switch stream source")
                .accessibilityValue("\(item.title), \(session.sourceTitle)").accessibilityIdentifier("sports-player-source-picker")
            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                session.minimize()
            } label: { Image(systemName: "pip.enter").frame(width: 44, height: 44) }
                .accessibilityLabel("Minimize player").accessibilityHint("Keep watching while browsing Streamify")
                .accessibilityIdentifier("sports-player-minimize")
        }.padding(.horizontal, max(8, session.safeAreaInsets.left)).buttonStyle(.plain)
    }

    private func footer(_ item: SportsPlaybackItem) -> some View {
        HStack(spacing: 16) {
            Button(action: session.reloadCurrent) { Label("Reload", systemImage: "arrow.clockwise").frame(minHeight: 44) }
            Spacer(minLength: 0)
            Button(action: session.toggleDirect) { Label(session.direct ? "Embed mode" : "Direct mode", systemImage: "rectangle.on.rectangle").frame(minHeight: 44) }
            Spacer(minLength: 0)
            Button { openURL(item.url) } label: { Image(systemName: "safari").frame(width: 44, height: 44) }.accessibilityLabel("Open in browser")
        }.font(.caption.weight(.semibold)).padding(.horizontal, max(16, session.safeAreaInsets.left)).buttonStyle(.plain)
    }

    private func miniControls(_ item: SportsPlaybackItem) -> some View {
        ZStack {
            Button(action: session.expand) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Restore \(item.title)").accessibilityIdentifier("sports-mini-restore")
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: session.close) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel("Close mini player").accessibilityIdentifier("sports-mini-close")
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(session.sourceTitle).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
