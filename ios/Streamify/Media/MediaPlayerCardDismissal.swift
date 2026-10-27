import SwiftUI
import UIKit

// Reuse the sports player's weak, live card reference. A recycled or obscured
// source falls back to the same card-shaped dismissal instead of a stale frame.
typealias MediaPlaybackOrigin = SportsPlaybackOrigin

struct MediaPlaybackOriginCard<Content: View>: View {
    @StateObject private var origin = MediaPlaybackOrigin()
    private let content: (MediaPlaybackOrigin) -> Content
    init(@ViewBuilder content: @escaping (MediaPlaybackOrigin) -> Content) { self.content = content }
    var body: some View { content(origin).sportsPlaybackOrigin(origin) }
}

@MainActor private final class MediaPlayerDismissTarget: ObservableObject {
    weak var marker: UIView?
    func frame(from origin: MediaPlaybackOrigin?) -> CGRect? {
        guard let marker, let window = marker.window, let frame = origin?.frame(in: window) else { return nil }
        return marker.convert(frame, from: window)
    }
}

private struct MediaPlayerDismissTargetAttachment: UIViewRepresentable {
    let target: MediaPlayerDismissTarget
    func makeUIView(context: Context) -> UIView {
        let marker = UIView()
        marker.isUserInteractionEnabled = false
        target.marker = marker
        return marker
    }
    func updateUIView(_ marker: UIView, context: Context) { target.marker = marker }
    static func dismantleUIView(_ marker: UIView, coordinator: ()) { }
}

/// Retains the existing video at its full layout size while its card transforms.
/// The shared sports recognizer excludes native controls, provider fullscreen,
/// menus, sheets and the bottom video-control strip.
private struct MediaPlayerCardDismissal: ViewModifier {
    let origin: MediaPlaybackOrigin?
    let sessionKey: String
    let enabled: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var target = MediaPlayerDismissTarget()
    @State private var drag = CGSize.zero
    @State private var returnFrame: CGRect?
    @State private var dismissing = false
    @State private var dismissalToken = UUID()

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let rect = displayedFrame(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(dismissing ? 0 : max(0, 1 - Double(drag.height / max(1, geometry.size.height)) * 2))
                    .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .sportsPlayerSwipeDownToDismiss(enabled: enabled && !dismissing && scenePhase == .active,
                        onChanged: { translation in
                            if drag == .zero { returnFrame = target.frame(from: origin) }
                            drag = translation
                        }, onEnded: { translation, velocity, cancelled in
                            if !cancelled && SportsPlayerDismissPolicy.shouldDismiss(translation: translation, velocity: velocity, size: geometry.size) {
                                finishDismissal()
                            } else {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) { drag = .zero }
                            }
                        })
                    .scaleEffect(rect.width / max(1, geometry.size.width))
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : dismissing ? 20 : min(24, max(0, drag.height) / 5), style: .continuous))
                    .opacity(dismissing ? 0 : 1)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(!dismissing)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background { MediaPlayerDismissTargetAttachment(target: target).allowsHitTesting(false).accessibilityHidden(true) }
            .onChange(of: geometry.size) { _, _ in reset() }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("media-player")
        .accessibilityAction(.escape) { action() }
        .onChange(of: sessionKey) { _, _ in reset() }
        .onChange(of: enabled) { _, active in if !active { reset() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { reset() } }
        .onDisappear(perform: reset)
    }

    private func displayedFrame(in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        guard !reduceMotion else { return bounds }
        if dismissing {
            return returnFrame ?? CGRect(x: size.width * 0.12, y: size.height * 0.55,
                width: size.width * 0.76, height: size.height * 0.35)
        }
        let scale = 1 - min(0.18, SportsPlayerDismissPolicy.progress(translation: drag, size: size) * 0.3)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: (size.width - width) / 2 + drag.width * 0.2,
            y: (size.height - height) / 2 + max(0, drag.height) * 0.8, width: width, height: height)
    }

    private func finishDismissal() {
        guard !dismissing else { return }
        returnFrame = target.frame(from: origin) ?? returnFrame
        let token = UUID()
        dismissalToken = token
        AppHaptics.tap()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete) {
            dismissing = true
        } completion: {
            guard dismissalToken == token else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { action() }
        }
    }

    private func reset() {
        dismissalToken = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag = .zero; returnFrame = nil; dismissing = false }
    }
}

extension View {
    func mediaPlayerCardDismissal(origin: MediaPlaybackOrigin?, sessionKey: String, enabled: Bool,
        action: @escaping () -> Void) -> some View {
        modifier(MediaPlayerCardDismissal(origin: origin, sessionKey: sessionKey, enabled: enabled, action: action))
    }
}
