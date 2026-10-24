import SwiftUI
import UIKit
import WebKit

/// Native markers protect explicit action buttons without relying on SwiftUI
/// rendering every Button as a UIControl. Weak views never retain recycled rows.
@MainActor
final class SportsDaySwipeScope: ObservableObject {
    private let excluded = NSHashTable<UIView>.weakObjects()
    private(set) var generation = 0
    func invalidateRequests() { generation &+= 1 }
    fileprivate func add(_ view: UIView) { excluded.add(view) }
    fileprivate func excludes(_ touch: UITouch, in window: UIWindow) -> Bool {
        excluded.allObjects.contains { view in
            view.window === window && !view.isHidden && view.alpha > 0.01 && view.bounds.contains(touch.location(in: view))
        }
    }
}

private struct SportsDaySwipeExclusion: UIViewRepresentable {
    let scope: SportsDaySwipeScope
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        scope.add(view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { scope.add(view) }
}

extension View {
    func sportsDaySwipeExcluded(_ scope: SportsDaySwipeScope?) -> some View {
        background {
            if let scope { SportsDaySwipeExclusion(scope: scope).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }
}

enum SportsDaySwipeGate {
    static func horizontal(_ value: CGPoint) -> Bool {
        value.x.isFinite && value.y.isFinite && abs(value.x) > abs(value.y) * 1.8
    }
    static func direction(translation: CGPoint) -> Int? {
        guard horizontal(translation), abs(translation.x) >= 72 else { return nil }
        return translation.x < 0 ? 1 : -1
    }
}

@MainActor
fileprivate final class SportsDaySwipeMarker: UIView {
    var moved: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); moved?() }
}

/// The pan observes this schedule's window, while its marker and touch gates
/// exclude headers, other tabs, sheets, controls and horizontal scrolling rails.
@MainActor
struct SportsDaySwipeObserver: UIViewRepresentable {
    let scope: SportsDaySwipeScope
    let enabled: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let changeDay: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = SportsDaySwipeMarker()
        view.isUserInteractionEnabled = false
        context.coordinator.marker = view
        view.moved = { [weak coordinator = context.coordinator] in coordinator?.attach() }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach()
        context.coordinator.pan.isEnabled = enabled
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        (view as? SportsDaySwipeMarker)?.moved = nil
        coordinator.detach()
        coordinator.marker = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SportsDaySwipeObserver
        fileprivate weak var marker: SportsDaySwipeMarker?
        private weak var window: UIWindow?
        private weak var verticalScroll: UIScrollView?
        private var initialVerticalOffset: CGFloat = 0
        private var eligible = false
        private var initialDirection = 0
        lazy var pan: UIPanGestureRecognizer = {
            let value = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            value.delegate = self
            value.maximumNumberOfTouches = 1
            value.cancelsTouchesInView = true
            value.delaysTouchesBegan = false
            value.delaysTouchesEnded = false
            return value
        }()
        init(_ parent: SportsDaySwipeObserver) { self.parent = parent }
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
            window?.removeGestureRecognizer(pan)
            window = nil
            eligible = false
            verticalScroll = nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            eligible = false
            verticalScroll = nil
            initialDirection = 0
            guard parent.enabled, let marker, let window, touch.view?.window === window,
                  !window.isHidden, window.alpha > 0.01,
                  !hasPresentation(window.rootViewController),
                  marker.bounds.contains(touch.location(in: marker)),
                  !parent.scope.excludes(touch, in: window) else { return false }
            var ancestor: UIView? = marker
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 || (view.clipsToBounds && !view.bounds.contains(touch.location(in: view))) { return false }
                ancestor = view.superview
            }
            var candidate = touch.view
            while let view = candidate {
                if view is UITextField || view is UITextView || view is UISearchBar || view is UISlider ||
                    view is UISwitch || view is UIStepper || view is UIPickerView || view is UIDatePicker || view is WKWebView { return false }
                if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                    if scroll.isPagingEnabled || scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 1 { return false }
                    if verticalScroll == nil { verticalScroll = scroll; initialVerticalOffset = verticalOffset(scroll) }
                }
                if view === window { break }
                candidate = view.superview
            }
            eligible = true
            return true
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.enabled, eligible, !verticallyScrolled else { return false }
            let velocity = pan.velocity(in: window)
            guard SportsDaySwipeGate.horizontal(velocity) else { return false }
            initialDirection = velocity.x < 0 ? 1 : -1
            return initialDirection == 1 ? parent.canGoForward : parent.canGoBack
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        private func verticalOffset(_ scroll: UIScrollView) -> CGFloat { scroll.contentOffset.y + scroll.adjustedContentInset.top }
        private var verticallyScrolled: Bool { verticalScroll.map { abs(verticalOffset($0) - initialVerticalOffset) > 5 } ?? false }
        private func hasPresentation(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            return controller.presentedViewController != nil || controller.children.contains { hasPresentation($0) }
        }
        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: window)
            switch recognizer.state {
            case .changed:
                if verticallyScrolled || abs(translation.y) > max(18, abs(translation.x) * 0.65) { eligible = false }
            case .ended:
                defer { eligible = false }
                guard parent.enabled, eligible, !verticallyScrolled,
                      let direction = SportsDaySwipeGate.direction(translation: translation), direction == initialDirection,
                      direction == 1 ? parent.canGoForward : parent.canGoBack else { return }
                parent.changeDay(direction)
            case .cancelled, .failed: eligible = false
            default: break
            }
        }
    }
}
