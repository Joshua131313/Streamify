import SwiftUI
import UIKit

extension Notification.Name {
    static let rootTabDoubleTap = Notification.Name("StreamifyRootTabDoubleTap")
}

/// Scroll the current root viewport without rebuilding it or changing filters.
struct RootTabScrollToTop: UIViewRepresentable {
    let tab: AppTab
    func makeUIView(context: Context) -> Observer {
        let view = Observer(frame: .zero); view.tab = tab.rawValue; view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: Observer, context: Context) { uiView.tab = tab.rawValue }
    final class Observer: UIView {
        var tab = ""
        private var token: NSObjectProtocol?
        override init(frame: CGRect) {
            super.init(frame: frame)
            token = NotificationCenter.default.addObserver(forName: .rootTabDoubleTap, object: nil, queue: .main) { [weak self] note in
                guard let self, note.object as? String == self.tab, let window = self.window else { return }
                func scrolls(_ view: UIView) -> [UIScrollView] {
                    guard !view.isHidden, view.alpha > 0.01 else { return [] }
                    return (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
                }
                let frame = self.convert(self.bounds, to: window)
                let candidates = scrolls(window).filter { scroll in
                    let rect = scroll.convert(scroll.bounds, to: window)
                    return scroll.isScrollEnabled && scroll.bounds.height > 200 && scroll.contentSize.height > scroll.bounds.height &&
                        rect.intersection(frame).height > min(frame.height, rect.height) * 0.75
                }
                guard let scroll = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}
