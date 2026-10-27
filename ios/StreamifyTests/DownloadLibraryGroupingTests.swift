import Foundation
import XCTest
@testable import Streamify

final class DownloadLibraryGroupingTests: XCTestCase {
    func testToolbarAveragesNativeAndFileProgressAndExcludesInactiveItems() throws {
        var file = item(show: 42, season: 1, episode: 1)
        file.status = .downloading; file.bytesWritten = 25; file.expectedBytes = 100
        var hls = item(show: 42, season: 1, episode: 2)
        hls.status = .downloading; hls.transport = .hlsVOD; hls.hlsFractionCompleted = 0.75
        let completed = item(show: 42, season: 1, episode: 3)
        XCTAssertEqual(try XCTUnwrap(DownloadToolbarProgress.average(in: [file, hls, completed])), 0.5, accuracy: 0.0001)
        hls.status = .cancelled
        XCTAssertEqual(try XCTUnwrap(DownloadToolbarProgress.average(in: [file, hls, completed])), 0.25, accuracy: 0.0001)
        file.expectedBytes = 0
        XCTAssertNil(DownloadToolbarProgress.average(in: [file, hls]))
        XCTAssertNil(DownloadToolbarProgress.average(in: [completed]))
    }

    func testSingleEpisodeAlwaysOpensAShowGroupAndMovieWithSameIDStaysAFile() throws {
        let episode = item(show: 42, season: 1, episode: 1)
        var movie = item(show: 42, season: 1, episode: 1)
        movie.catalog = CatalogDownloadDescriptor(id: 42, kind: "movie", title: "A movie", season: 1, episode: 1, episodeTitle: nil)
        let entries = DownloadLibraryGrouping.entries(in: [episode, movie])
        XCTAssertEqual(entries.count, 2)
        let group = try XCTUnwrap(DownloadLibraryGrouping.series(id: 42, in: [episode, movie]))
        XCTAssertEqual(group.episodes.map(\.id), [episode.id])
        XCTAssertTrue(entries.contains { if case .video(let file) = $0 { return file.id == movie.id }; return false })
        XCTAssertTrue(entries.contains { if case .series(let show) = $0 { return show.id == 42 && show.episodes.count == 1 }; return false })
    }

    func testShowIdentityNeverMergesDifferentShowsWithTheSameTitleOrImportedFiles() throws {
        let first = item(show: 42, season: 1, episode: 1)
        let second = item(show: 43, season: 1, episode: 1)
        var imported = item(show: 42, season: 1, episode: 1)
        imported.catalog = nil
        imported.catalogKey = nil
        imported.title = "Shared show title"
        let entries = DownloadLibraryGrouping.entries(in: [first, second, imported])
        XCTAssertEqual(Set(entries.map(\.id)), ["tv:42", "tv:43", "video:\(imported.id.uuidString)"])
        XCTAssertEqual(try XCTUnwrap(DownloadLibraryGrouping.series(id: 42, in: [first, second, imported])).episodes.map(\.id), [first.id])
        XCTAssertNil(DownloadLibraryGrouping.series(id: 99, in: [first, second, imported]))
        XCTAssertNil(DownloadLibraryGrouping.series(id: 0, in: [first]))
    }

    func testEpisodePageSortsBySeasonThenEpisodeWithoutDroppingAnyTransferState() throws {
        var secondSeason = item(show: 42, season: 2, episode: 1)
        secondSeason.status = .failed
        var later = item(show: 42, season: 1, episode: 9)
        later.status = .downloading
        var earlier = item(show: 42, season: 1, episode: 2)
        earlier.status = .cancelled
        let first = item(show: 42, season: 1, episode: 1)
        let group = try XCTUnwrap(DownloadLibraryGrouping.series(id: 42, in: [secondSeason, later, earlier, first]))
        XCTAssertEqual(group.episodes.map(\.id), [first.id, earlier.id, later.id, secondSeason.id])
        XCTAssertEqual(group.seasons, [1, 2])
        XCTAssertEqual(group.readyCount, 1)
        XCTAssertEqual(group.active.map(\.id), [later.id])
        XCTAssertEqual(Set(group.retryable.map(\.id)), [earlier.id, secondSeason.id])
    }

    func testActivityUsesOnlyActiveWeightedBytesAndUnknownTotalsStayIndeterminate() throws {
        var first = item(show: 42, season: 1, episode: 1)
        first.status = .downloading; first.bytesWritten = 25; first.expectedBytes = 100
        var second = item(show: 42, season: 1, episode: 2)
        second.status = .downloading; second.bytesWritten = 50; second.expectedBytes = 200
        var complete = item(show: 42, season: 1, episode: 3)
        complete.bytesWritten = 900; complete.expectedBytes = 900
        let known = try XCTUnwrap(DownloadLibraryGrouping.series(id: 42, in: [first, second, complete]))
        XCTAssertEqual(try XCTUnwrap(known.progress), 0.25, accuracy: 0.0001)
        XCTAssertEqual(known.bytesWritten, 975)
        second.expectedBytes = 0
        XCTAssertNil(DownloadLibraryGrouping.series(id: 42, in: [first, second, complete])?.progress)
        XCTAssertNil(DownloadLibraryGrouping.series(id: 42, in: [complete])?.progress)
        first.bytesWritten = 900
        XCTAssertEqual(DownloadLibraryGrouping.series(id: 42, in: [first])?.progress, 1)
    }

    func testGroupingKeepsExactFilesArtworkCatalogAndRetryIdentity() throws {
        var original = item(show: 42, season: 2, episode: 3)
        original.quality = 1080
        original.fileName = "local-existing-file.mp4"
        original.posterSource = "https://image.example/show.jpg"
        original.posterFileName = "\(original.id.uuidString)-artwork-\(UUID().uuidString).jpg"
        original.error = "Previous transfer failed"
        original.taskIdentifier = 90
        original.pendingFileName = "pending-existing-file.mp4"
        let grouped = try XCTUnwrap(DownloadLibraryGrouping.series(id: 42, in: [original])?.episodes.first)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(grouped), try encoder.encode(original), "Grouping must never create new file IDs, discard recovery metadata or rewrite catalog state.")
    }

    func testRootOrderMatchesTitleOrderAndSizeCannotOverflowOnOldMetadata() throws {
        var last = item(show: 42, season: 1, episode: 1)
        last.catalog = CatalogDownloadDescriptor(id: 42, kind: "tv", title: "Zebra", season: 1, episode: 1, episodeTitle: nil)
        var first = item(show: 43, season: 1, episode: 1)
        first.catalog = CatalogDownloadDescriptor(id: 43, kind: "movie", title: "Alpha", season: 1, episode: 1, episodeTitle: nil)
        XCTAssertEqual(DownloadLibraryGrouping.entries(in: [last, first]).map(\.title), ["Alpha", "Zebra"])
        var second = item(show: 42, season: 1, episode: 2)
        last.bytesWritten = Int64.max; second.bytesWritten = 10
        XCTAssertEqual(DownloadLibraryGrouping.series(id: 42, in: [last, second])?.bytesWritten, Int64.max)
        second.bytesWritten = -10
        XCTAssertEqual(DownloadLibraryGrouping.series(id: 42, in: [second])?.bytesWritten, 0)
    }

    private func item(show: Int, season: Int, episode: Int) -> DownloadItem {
        DownloadItem(id: UUID(), title: "Shared show title · S\(season) E\(episode)", source: "https://video.example/file.mp4",
            fileName: "existing-\(season)-\(episode).mp4", createdAt: Date(timeIntervalSince1970: Double(season * 100 + episode)),
            status: .completed, bytesWritten: 100, expectedBytes: 100, catalogKey: "tv:\(show):\(season):\(episode)", quality: 720,
            catalog: CatalogDownloadDescriptor(id: show, kind: "tv", title: "Shared show title", season: season, episode: episode, episodeTitle: "Episode \(episode)"))
    }
}
