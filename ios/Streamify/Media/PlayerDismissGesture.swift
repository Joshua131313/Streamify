import SwiftUI
import UIKit

enum PlayerDismissGate {
    static func canStart(at point: CGPoint, in bounds: CGRect) -> Bool {
        bounds.width > 0 && bounds.height > 0 && bounds.contains(point)
    }
    static func isLeftward(_ movement: CGPoint) -> Bool {
        movement.x < 0 && abs(movement.x) > abs(movement.y) * 1.6
    }
    static func shouldDismiss(_ translation: CGPoint) -> Bool {
        translation.x < -90 && isLeftward(translation)
    }
}

private struct PlayerDismissGesture: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.background {
            PlayerDismissPanObserver(action: action).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

@MainActor
private final class PlayerDismissPanMarker: UIView {
    var moved: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); moved?() }
}

/// A window observer receives WKWebView touches across the player's canvas.
/// The marker excludes other screens and presentations above this player.
@MainActor
private struct PlayerDismissPanObserver: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PlayerDismissPanMarker {
        let marker = PlayerDismissPanMarker(frame: .zero)
        marker.isUserInteractionEnabled = false
        context.coordinator.marker = marker
        marker.moved = { [weak coordinator = context.coordinator] in coordinator?.attach() }
        return marker
    }
    func updateUIView(_ marker: PlayerDismissPanMarker, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach()
    }
    static func dismantleUIView(_ marker: PlayerDismissPanMarker, coordinator: Coordinator) {
        marker.moved = nil
        coordinator.detach()
        coordinator.marker = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerDismissPanObserver
        weak var marker: PlayerDismissPanMarker?
        private weak var window: UIWindow?
        private var eligibleTouch = false
        lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            return recognizer
        }()
        init(_ parent: PlayerDismissPanObserver) { self.parent = parent }
        func attach() {
            let next = marker?.window
            guard window !== next else { return }
            detach()
            guard let next else { return }
            window = next
            next.addGestureRecognizer(pan)
        }
        func detach() {
            window?.removeGestureRecognizer(pan)
            window = nil
            eligibleTouch = false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            eligibleTouch = false
            guard let marker, let window, touch.view?.window === window,
                  !window.isHidden, window.alpha > 0.01,
                  PlayerDismissGate.canStart(at: touch.location(in: marker), in: marker.bounds),
                  sharesPlayerPresentation(touch.view, marker: marker) else { return false }
            var controlAncestor = touch.view
            while let view = controlAncestor {
                if view is UIControl || view is UITextView || view is UISearchBar ||
                    view is UIPickerView || view is UIDatePicker { return false }
                if view === window { break }
                controlAncestor = view.superview
            }
            var ancestor: UIView? = marker
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { return false }
                ancestor = view.superview
            }
            eligibleTouch = true
            return true
        }
        private func sharesPlayerPresentation(_ touchedView: UIView?, marker: UIView) -> Bool {
            var markerResponder: UIResponder? = marker
            var host: UIViewController?
            while let responder = markerResponder {
                if let controller = responder as? UIViewController { host = controller; break }
                markerResponder = responder.next
            }
            guard let host else { return false }
            var responder: UIResponder? = touchedView
            while let current = responder {
                if current === host { return true }
                responder = current.next
            }
            return false
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            eligibleTouch && PlayerDismissGate.isLeftward(pan.velocity(in: window))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .ended:
                let shouldDismiss = eligibleTouch && PlayerDismissGate.shouldDismiss(recognizer.translation(in: window))
                eligibleTouch = false
                if shouldDismiss { parent.action() }
            case .cancelled, .failed: eligibleTouch = false
            default: break
            }
        }
    }
}

extension View {
    func playerSwipeToDismiss(action: @escaping () -> Void) -> some View {
        modifier(PlayerDismissGesture(action: action))
    }
}
