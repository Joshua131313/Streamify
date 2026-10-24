import SwiftUI
import UIKit
import WebKit

enum SportsPlayerDismissPolicy {
    static func canStart(at point: CGPoint, in bounds: CGRect, bottomExclusion: CGFloat = 110) -> Bool {
        guard bounds.width > 0, bounds.height > 0, point.x.isFinite, point.y.isFinite else { return false }
        return bounds.contains(point) && point.y < bounds.maxY - min(max(0, bottomExclusion), bounds.height)
    }

    static func isDownward(_ movement: CGPoint) -> Bool {
        movement.x.isFinite && movement.y.isFinite && movement.y > 0 && movement.y > abs(movement.x) * 1.4
    }

    static func progress(translation: CGSize, size: CGSize) -> CGFloat {
        guard translation.height.isFinite, size.height.isFinite, size.height > 0 else { return 0 }
        return min(1, max(0, translation.height) / max(1, size.height * 0.6))
    }

    static func shouldDismiss(translation: CGSize, velocity: CGPoint, size: CGSize) -> Bool {
        guard size.height.isFinite, size.height > 0,
              isDownward(CGPoint(x: translation.width, y: translation.height)) else { return false }
        let distance = max(100, size.height * 0.2)
        return translation.height >= distance ||
            (translation.height >= 36 && isDownward(velocity) && velocity.y >= 800)
    }
}

private struct SportsPlayerDismissGesture: ViewModifier {
    let enabled: Bool
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize, CGPoint, Bool) -> Void

    func body(content: Content) -> some View {
        content.background {
            SportsPlayerDismissPanObserver(enabled: enabled, onChanged: onChanged, onEnded: onEnded)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

@MainActor private final class SportsPlayerDismissPanMarker: UIView {
    var moved: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); moved?() }
}

/// Observes the sports canvas without replacing WebKit's video interaction.
/// A marker ties the observer to its own controller and window: system video
/// fullscreen, element fullscreen, menus and presentations keep their gestures.
@MainActor private struct SportsPlayerDismissPanObserver: UIViewRepresentable {
    let enabled: Bool
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize, CGPoint, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SportsPlayerDismissPanMarker {
        let marker = SportsPlayerDismissPanMarker(frame: .zero)
        marker.isUserInteractionEnabled = false
        context.coordinator.marker = marker
        marker.moved = { [weak coordinator = context.coordinator] in coordinator?.attach() }
        return marker
    }
    func updateUIView(_ marker: SportsPlayerDismissPanMarker, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach()
        context.coordinator.pan.isEnabled = enabled
    }
    static func dismantleUIView(_ marker: SportsPlayerDismissPanMarker, coordinator: Coordinator) {
        marker.moved = nil
        coordinator.detach()
        coordinator.marker = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SportsPlayerDismissPanObserver
        weak var marker: SportsPlayerDismissPanMarker?
        private weak var window: UIWindow?
        private var eligibleTouch = false
        private var active = false
        lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            return recognizer
        }()
        init(_ parent: SportsPlayerDismissPanObserver) { self.parent = parent }

        func attach() {
            let next = marker?.window
            guard window !== next else { return }
            detach()
            guard let next else { return }
            window = next
            next.addGestureRecognizer(pan)
            pan.isEnabled = parent.enabled
        }

        func detach() {
            if active { end(cancelled: true) }
            window?.removeGestureRecognizer(pan)
            window = nil
            eligibleTouch = false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            eligibleTouch = false
            guard parent.enabled, let marker, let window,
                  touch.view?.window === window, window.isKeyWindow,
                  !window.isHidden, window.alpha > 0.01,
                  SportsPlayerDismissPolicy.canStart(at: touch.location(in: marker), in: marker.bounds),
                  sharesPlayerPresentation(touch.view, marker: marker) else { return false }
            var ancestor = touch.view
            while let view = ancestor {
                if view is UIControl || view is UITextView || view is UISearchBar ||
                    view is UIPickerView || view is UIDatePicker { return false }
                if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
                   scroll.contentSize.width > scroll.bounds.width + 1 || scroll.contentSize.height > scroll.bounds.height + 1 ||
                   scroll.alwaysBounceHorizontal || scroll.alwaysBounceVertical { return false }
                if let web = view as? WKWebView,
                   !SportsPlayerDismissPolicy.canStart(at: touch.location(in: web), in: web.bounds) { return false }
                if view === window { break }
                ancestor = view.superview
            }
            ancestor = marker
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { return false }
                ancestor = view.superview
            }
            eligibleTouch = true
            return true
        }

        private func sharesPlayerPresentation(_ touchedView: UIView?, marker: UIView) -> Bool {
            var responder: UIResponder? = marker
            var host: UIViewController?
            while let current = responder {
                if let controller = current as? UIViewController { host = controller; break }
                responder = current.next
            }
            guard let host, host.presentedViewController == nil else { return false }
            responder = touchedView
            while let current = responder {
                if current === host { return true }
                responder = current.next
            }
            return false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.enabled && eligibleTouch && SportsPlayerDismissPolicy.isDownward(pan.velocity(in: window))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                active = true
                changed()
            case .changed:
                if active { changed() }
            case .ended:
                if active { end(cancelled: false) }
            case .cancelled, .failed:
                if active { end(cancelled: true) }
                eligibleTouch = false
            default: break
            }
        }
        private func changed() {
            let translation = pan.translation(in: window)
            parent.onChanged(CGSize(width: translation.x, height: translation.y))
        }
        private func end(cancelled: Bool) {
            let translation = pan.translation(in: window)
            let velocity = pan.velocity(in: window)
            active = false
            eligibleTouch = false
            parent.onEnded(CGSize(width: translation.x, height: translation.y), velocity, cancelled)
        }
    }
}

extension View {
    func sportsPlayerSwipeDownToDismiss(enabled: Bool,
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping (CGSize, CGPoint, Bool) -> Void) -> some View {
        modifier(SportsPlayerDismissGesture(enabled: enabled, onChanged: onChanged, onEnded: onEnded))
    }
}
