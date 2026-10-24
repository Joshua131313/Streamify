import XCTest
@testable import Streamify

final class PlaybackCheckpointTests: XCTestCase {
    func testRejectsLoadingInvalidAndAdLengthSamples() {
        var checkpoint = PlaybackCheckpoint()
        XCTAssertNil(checkpoint.sample(position: 0, duration: 1_800, now: 0))
        XCTAssertNil(checkpoint.sample(position: .nan, duration: 1_800, now: 0))
        XCTAssertNil(checkpoint.sample(position: 20, duration: .infinity, now: 0))
        XCTAssertNil(checkpoint.sample(position: 20, duration: 30, now: 0))
        XCTAssertNil(checkpoint.sample(position: 20, duration: 50_000, now: 0))
        XCTAssertNil(checkpoint.sample(position: 2_000, duration: 1_800, now: 0))
        XCTAssertEqual(checkpoint.sample(position: 5, duration: 1_800, now: 0)?.position, 5)
    }

    func testNormalAndForcedCheckpointsAreBoundedAndFlushLatestSample() {
        var checkpoint = PlaybackCheckpoint()
        XCTAssertNotNil(checkpoint.sample(position: 100, duration: 1_800, now: 0))
        XCTAssertNil(checkpoint.sample(position: 102, duration: 1_800, now: 0.2, force: true))
        XCTAssertNil(checkpoint.sample(position: 103, duration: 1_800, now: 0.9, force: true))
        XCTAssertEqual(checkpoint.flush(now: 1)?.position, 103)
        XCTAssertNil(checkpoint.sample(position: 105, duration: 1_800, now: 3))
        XCTAssertEqual(checkpoint.sample(position: 109, duration: 1_800, now: 6)?.position, 109)
        XCTAssertNil(checkpoint.flush(now: 8), "An unchanged lifecycle event must not rewrite history")
        XCTAssertEqual(checkpoint.sample(position: 1_803, duration: 1_800, now: 10, force: true)?.position, 1_800)
    }

    func testResumeIsBoundToExactEpisodeAndSkipsCompletedEntries() {
        let media = MediaItem(id: 77, kind: .tv, title: "Fixture")
        let entry = WatchEntry(media: media, season: 2, episode: 3, positionSeconds: 400, durationSeconds: 1_800)
        XCTAssertEqual(PlaybackIdentity(mediaKey: media.key, season: 2, episode: 3).resumeSeconds(from: entry), 400)
        XCTAssertEqual(PlaybackIdentity(mediaKey: media.key, season: 2, episode: 4).resumeSeconds(from: entry), 0)
        XCTAssertEqual(PlaybackIdentity(mediaKey: "movie:77", season: 2, episode: 3).resumeSeconds(from: entry), 0)
        let complete = WatchEntry(media: media, season: 2, episode: 3, positionSeconds: 1_710, durationSeconds: 1_800)
        XCTAssertEqual(PlaybackIdentity(mediaKey: media.key, season: 2, episode: 3).resumeSeconds(from: complete), 0)
    }
}
