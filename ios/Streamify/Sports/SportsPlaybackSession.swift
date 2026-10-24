import Foundation
import Combine
import UIKit

struct SportsPlaybackItem: Identifiable {
    let id: UUID
    let title: String
    var url: URL
    let sources: [SportsStream]
}

enum SportsPlaybackPresentation: Equatable { case expanded, minimized }

/// Owned by the app, never by a recyclable schedule row or a presented sheet.
/// Scene activation does not replace the item, source, or playback surface.
@MainActor
final class SportsPlaybackSession: ObservableObject {
    @Published private(set) var item: SportsPlaybackItem?
    @Published private(set) var presentation: SportsPlaybackPresentation = .expanded
    @Published private(set) var reload = 0
    @Published private(set) var direct = false
    @Published private(set) var safeAreaInsets = UIEdgeInsets.zero
    @Published private(set) var keyboardInset: CGFloat = 0
    var interactionFrame = CGRect.zero

    var isExpanded: Bool { item != nil && presentation == .expanded }
    var isMinimized: Bool { item != nil && presentation == .minimized }
    var sourceTitle: String { item.flatMap { item in item.sources.first { $0.url == item.url }?.title } ?? "Current source" }

    func play(title: String, url: URL, sources: [SportsStream] = []) {
        guard sportsHTTPSURL(url.absoluteString) != nil else { return }
        var seen = Set<URL>()
        var choices = sources.flatMap(\.availableSources).filter { seen.insert($0.url).inserted }
        if !seen.contains(url) { choices.insert(SportsStream(title: "Current source", url: url), at: 0) }
        if item?.url == url, item?.title == title { expand(); return }
        item = SportsPlaybackItem(id: UUID(), title: title, url: url, sources: choices)
        reload = 0; direct = false; presentation = .expanded
    }

    func selectSource(_ source: SportsStream) {
        guard var current = item, current.url != source.url,
              current.sources.contains(where: { $0.url == source.url }) else { return }
        current.url = source.url
        item = current
        reload = 0; direct = false
    }
    func reloadCurrent() { guard item != nil else { return }; reload += 1 }
    func toggleDirect() { guard item != nil else { return }; direct.toggle() }
    func minimize() { guard item != nil else { return }; interactionFrame = .zero; presentation = .minimized }
    func expand() { guard item != nil else { return }; presentation = .expanded }
    func close() {
        item = nil
        reload = 0; direct = false; presentation = .expanded; interactionFrame = .zero
    }
    func updateSafeArea(_ value: UIEdgeInsets) { if safeAreaInsets != value { safeAreaInsets = value } }
    func updateKeyboardInset(_ value: CGFloat) { if keyboardInset != value { keyboardInset = max(0, value) } }
}
