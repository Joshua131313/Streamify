import Foundation
import Combine
import UIKit

struct SportsPlaybackItem: Identifiable {
    let id: UUID
    let title: String
    var url: URL
    let sources: [SportsStream]
}

enum SportsPlaybackPresentation: Equatable { case expanded, systemPictureInPicture }

/// Owned by the app, never by a recyclable schedule row or a presented sheet.
/// Scene activation does not replace the item, source, or playback surface.
@MainActor
final class SportsPlaybackSession: ObservableObject {
    @Published private(set) var item: SportsPlaybackItem?
    @Published private(set) var presentation: SportsPlaybackPresentation = .expanded
    @Published private(set) var reload = 0
    @Published private(set) var direct = false
    @Published private(set) var isVideoFullscreen = false
    @Published private(set) var safeAreaInsets = UIEdgeInsets.zero
    @Published private(set) var origin: SportsPlaybackOrigin?
    let pictureInPicture = SportsSystemPiP()

    var isExpanded: Bool { item != nil && presentation == .expanded }
    var isPiPActive: Bool { item != nil && presentation == .systemPictureInPicture }
    // Existing context sheets dismiss only after confirmed system PiP starts.
    var isMinimized: Bool { isPiPActive }
    var sourceTitle: String { item.flatMap { item in item.sources.first { $0.url == item.url }?.title } ?? "Current source" }

    init() {
        pictureInPicture.onStateChange = { [weak self] active, restoring in
            guard let self, self.item != nil else { return }
            if active { self.presentation = .systemPictureInPicture }
            else if restoring { self.presentation = .expanded }
            else { self.close() }
        }
    }

    func play(title: String, url: URL, sources: [SportsStream] = [], origin: SportsPlaybackOrigin? = nil) {
        guard sportsHTTPSURL(url.absoluteString) != nil else { return }
        var seen = Set<URL>()
        var choices = sources.flatMap(\.availableSources).filter { seen.insert($0.url).inserted }
        if !seen.contains(url) { choices.insert(SportsStream(title: "Current source", url: url), at: 0) }
        if item?.url == url, item?.title == title {
            if let origin { self.origin = origin }
            expand(); return
        }
        pictureInPicture.reset()
        self.origin = origin
        item = SportsPlaybackItem(id: UUID(), title: title, url: url, sources: choices)
        reload = 0; direct = false; isVideoFullscreen = false; presentation = .expanded
    }

    func selectSource(_ source: SportsStream) {
        guard var current = item, current.url != source.url,
              current.sources.contains(where: { $0.url == source.url }) else { return }
        current.url = source.url
        pictureInPicture.reset()
        item = current
        reload = 0; direct = false
    }
    func reloadCurrent() { guard item != nil else { return }; pictureInPicture.reset(); reload += 1 }
    func toggleDirect() { guard item != nil else { return }; pictureInPicture.reset(); direct.toggle() }
    func toggleVideoFullscreen() {
        guard isExpanded else { return }
        isVideoFullscreen.toggle()
    }
    func requestPictureInPicture() { guard item != nil else { return }; pictureInPicture.request() }
    func expand() {
        guard item != nil else { return }
        if pictureInPicture.isActive { pictureInPicture.restore() }
        else { presentation = .expanded }
    }
    func close() {
        pictureInPicture.reset()
        item = nil
        origin = nil
        reload = 0; direct = false; isVideoFullscreen = false; presentation = .expanded
    }
    func updateSafeArea(_ value: UIEdgeInsets) { if safeAreaInsets != value { safeAreaInsets = value } }
}
