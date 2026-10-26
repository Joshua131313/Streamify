import XCTest
@testable import Streamify

@MainActor final class HistoryArtworkTests: XCTestCase {
    func testInvalidBackdropFallsBackToValidPoster() {
        for invalid in ["", " null ", "undefined", "/", "http://invalid.example/image.jpg"] {
            let item = MediaItem(id: 1, kind: .tv, title: "Show", posterPath: "/poster.jpg", backdropPath: invalid)
            XCTAssertEqual(item.backdropURL, item.posterURL)
            XCTAssertEqual(item.heroBackdropURL?.lastPathComponent, "poster.jpg")
        }
    }
    func testSparsePlaybackMetadataRetainsArtworkAcrossEpisodesAndRepairKeepsProgress() throws {
        let defaults = UserDefaults(suiteName: "HistoryArtwork.\(UUID().uuidString)")!
        let store = LibraryStore(defaults: defaults)
        let rich = MediaItem(id: 1, kind: .tv, title: "Show", posterPath: "/poster.jpg", backdropPath: "/backdrop.jpg")
        store.record(rich, season: 1, episode: 1, positionSeconds: 120, durationSeconds: 1800)
        store.record(MediaItem(id: 1, kind: .tv, title: "Show"), season: 1, episode: 2, positionSeconds: 45, durationSeconds: 1700)
        let before = try XCTUnwrap(store.history.first)
        XCTAssertEqual(before.media.posterPath, rich.posterPath)
        XCTAssertEqual(before.media.backdropPath, rich.backdropPath)
        var replacement = rich; replacement.backdropPath = "/new-backdrop.jpg"
        store.repairHistoryArtwork(replacement)
        let after = try XCTUnwrap(store.history.first)
        XCTAssertEqual(after.watchedAt, before.watchedAt)
        XCTAssertEqual(after.season, 1); XCTAssertEqual(after.episode, 2)
        XCTAssertEqual(after.positionSeconds, 45); XCTAssertEqual(after.durationSeconds, 1700)
        XCTAssertEqual(after.media.backdropPath, replacement.backdropPath)
        XCTAssertEqual(LibraryStore(defaults: defaults).history.first?.media.backdropPath, replacement.backdropPath)
        store.removeHistory(replacement)
        store.repairHistoryArtwork(rich)
        XCTAssertTrue(store.history.isEmpty, "A late metadata result must not recreate deleted history.")
    }
}
