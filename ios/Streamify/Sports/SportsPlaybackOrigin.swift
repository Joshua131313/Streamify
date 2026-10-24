import SwiftUI
import UIKit

/// A live, weak reference to the card that opened playback. Its frame is resolved
/// at dismissal, so scrolling or removing a source never sends video to an old row.
@MainActor
final class SportsPlaybackOrigin: ObservableObject {
    private weak var marker: UIView?

    fileprivate func attach(_ view: UIView) { marker = view }
    fileprivate func detach(_ view: UIView) { if marker === view { marker = nil } }

    func frame(in window: UIWindow) -> CGRect? {
        guard let marker, let sourceWindow = marker.window,
              let scene = sourceWindow.windowScene, scene === window.windowScene,
              !sourceWindow.isHidden, sourceWindow.alpha > 0.01,
              marker.bounds.width >= 48, marker.bounds.height >= 36 else { return nil }

        let sourceFrame = marker.convert(marker.bounds, to: sourceWindow)
        guard Self.usable(sourceFrame) else { return nil }
        var visibleFrame = sourceFrame.intersection(sourceWindow.bounds)
        var ancestor: UIView? = marker
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else { return nil }
            if view.clipsToBounds {
                visibleFrame = visibleFrame.intersection(view.convert(view.bounds, to: sourceWindow))
            }
            if view === sourceWindow { break }
            ancestor = view.superview
        }
        // A mostly clipped or recycled card is a worse target than a simple fade.
        guard !visibleFrame.isNull, visibleFrame.width >= sourceFrame.width * 0.6,
              visibleFrame.height >= sourceFrame.height * 0.6 else { return nil }
        let target = marker.convert(marker.bounds, to: window)
        guard Self.usable(target), target.intersects(window.bounds) else { return nil }
        return target
    }

    private static func usable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite &&
            frame.width >= 48 && frame.height >= 36 && !frame.isNull && !frame.isInfinite
    }
}

@MainActor
private final class SportsPlaybackOriginMarker: UIView {
    weak var origin: SportsPlaybackOrigin?
}

private struct SportsPlaybackOriginAttachment: UIViewRepresentable {
    let origin: SportsPlaybackOrigin
    func makeUIView(context: Context) -> SportsPlaybackOriginMarker {
        let marker = SportsPlaybackOriginMarker()
        marker.isUserInteractionEnabled = false
        marker.origin = origin
        origin.attach(marker)
        return marker
    }
    func updateUIView(_ marker: SportsPlaybackOriginMarker, context: Context) {
        if marker.origin !== origin { marker.origin?.detach(marker) }
        marker.origin = origin
        origin.attach(marker)
    }
    static func dismantleUIView(_ marker: SportsPlaybackOriginMarker, coordinator: ()) {
        marker.origin?.detach(marker)
        marker.origin = nil
    }
}

extension View {
    func sportsPlaybackOrigin(_ origin: SportsPlaybackOrigin) -> some View {
        background { SportsPlaybackOriginAttachment(origin: origin).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

/// Each repeated source owns a separate identity, even when several cards can
/// launch the same stream from different sheets or carousels.
struct SportsPlaybackOriginCard<Content: View>: View {
    @StateObject private var origin = SportsPlaybackOrigin()
    private let content: (SportsPlaybackOrigin) -> Content
    init(@ViewBuilder content: @escaping (SportsPlaybackOrigin) -> Content) { self.content = content }
    var body: some View { content(origin).sportsPlaybackOrigin(origin) }
}
