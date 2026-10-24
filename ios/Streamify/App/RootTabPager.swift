import SwiftUI
import UIKit
import WebKit
import AVFoundation

enum RootTabPaging {
    static func offset(_ translation: CGFloat, index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard translation.isFinite, width.isFinite, width > 0 else { return 0 }
        let value = min(width, max(-width, translation))
        if index == 0 && value > 0 || index == count - 1 && value < 0 { return value * 0.28 }
        return value
    }

    static func destination(index: Int, count: Int, width: CGFloat, translation: CGFloat, velocity: CGFloat) -> Int {
        guard count > 0, width.isFinite, width > 0, translation.isFinite, velocity.isFinite else { return index }
        let projected = translation + velocity * 0.14
        guard translation * projected > 0 else { return index }
        let movedFar = abs(translation) > width * 0.26
        let flicked = abs(velocity) > 700 && abs(translation) > 18
        guard movedFar || flicked else { return index }
        return min(count - 1, max(0, index + (projected < 0 ? 1 : -1)))
    }
}

/// All four stacks remain mounted. Only an eligible root-level horizontal pan
/// moves this surface; native carousels, text fields, sliders and players win.
struct RootTabPager<Page: View>: View {
    @Binding var selection: AppTab
    let enabled: Bool
    @ViewBuilder let page: (AppTab) -> Page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var startingIndex: Int?
    @State private var feedback = 0

    private var index: Int { AppTab.allCases.firstIndex(of: selection) ?? 0 }
    private var snap: Animation? { reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    page(tab).frame(width: width, height: geometry.size.height)
                        .accessibilityHidden(tab != selection)
                        .allowsHitTesting(tab == selection)
                }
            }
            .frame(width: width * CGFloat(AppTab.allCases.count), alignment: .leading)
            .offset(x: -CGFloat(index) * width + dragOffset)
            .frame(width: width, height: geometry.size.height, alignment: .leading)
            .clipped()
            .background {
                RootTabPanObserver(enabled: enabled, began: { startingIndex = index }, changed: { translation in
                    guard enabled, let origin = startingIndex else { return }
                    dragOffset = RootTabPaging.offset(translation, index: origin, count: AppTab.allCases.count, width: width)
                }, ended: { translation, velocity, cancelled in
                    guard let origin = startingIndex else { return }
                    let next = cancelled || !enabled ? origin : RootTabPaging.destination(index: origin,
                        count: AppTab.allCases.count, width: width, translation: translation, velocity: velocity)
                    withAnimation(snap) {
                        selection = AppTab.allCases[next]
                        dragOffset = 0; startingIndex = nil
                    }
                    if next != origin { feedback += 1 }
                }).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("root-tab-pager")
        .animation(snap, value: selection)
        .sensoryFeedback(.selection, trigger: feedback)
        .onChange(of: selection) { _, _ in startingIndex = nil; dragOffset = 0 }
        .onChange(of: enabled) { _, active in
            if !active { withAnimation(snap) { startingIndex = nil; dragOffset = 0 } }
        }
    }
}

@MainActor
private final class RootTabPanMarker: UIView {
    var moved: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); moved?() }
}

@MainActor
private struct RootTabPanObserver: UIViewRepresentable {
    let enabled: Bool
    let began: () -> Void
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> RootTabPanMarker {
        let marker = RootTabPanMarker(frame: .zero)
        marker.isUserInteractionEnabled = false
        context.coordinator.marker = marker
        marker.moved = { [weak coordinator = context.coordinator] in coordinator?.attach() }
        return marker
    }
    func updateUIView(_ marker: RootTabPanMarker, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach()
        context.coordinator.pan.isEnabled = enabled
    }
    static func dismantleUIView(_ marker: RootTabPanMarker, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RootTabPanObserver
        weak var marker: RootTabPanMarker?
        private weak var window: UIWindow?
        private var eligibleTouch = false
        lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            return recognizer
        }()

        init(_ parent: RootTabPanObserver) { self.parent = parent }
        func attach() {
            guard let next = marker?.window, window !== next else { return }
            detach(); window = next; next.addGestureRecognizer(pan); pan.isEnabled = parent.enabled
        }
        func detach() { window?.removeGestureRecognizer(pan); window = nil; eligibleTouch = false }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            eligibleTouch = false
            guard parent.enabled, let marker, let window, touch.view?.window === window,
                  !hasPresentation(window.rootViewController),
                  marker.bounds.contains(touch.location(in: marker)) else { return false }
            var candidate = touch.view
            while let view = candidate {
                if view is UITextField || view is UITextView || view is UISearchBar || view is UISlider ||
                    view is UIPickerView || view is UIDatePicker || view is WKWebView || view.layer is AVPlayerLayer { return false }
                let className = String(describing: type(of: view))
                if className.contains("AVPlayer") || className.contains("AVPlayback") || className.contains("Slider") { return false }
                if let scroll = view as? UIScrollView,
                   scroll.isScrollEnabled && (scroll.isPagingEnabled || scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 1) { return false }
                if view === window { break }
                candidate = view.superview
            }
            eligibleTouch = true
            return true
        }
        private func hasPresentation(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            return controller.presentedViewController != nil || controller.children.contains { hasPresentation($0) }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.enabled, eligibleTouch else { return false }
            let velocity = pan.velocity(in: window)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: window).x
            switch recognizer.state {
            case .began: parent.began(); parent.changed(translation)
            case .changed: parent.changed(translation)
            case .ended: parent.ended(translation, recognizer.velocity(in: window).x, false)
            case .cancelled, .failed: parent.ended(translation, 0, true)
            default: break
            }
        }
    }
}
