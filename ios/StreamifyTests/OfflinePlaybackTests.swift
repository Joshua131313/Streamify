import XCTest
import AVFoundation
@testable import Streamify

final class OfflinePlaybackTests: XCTestCase {
    func testResumeSkipsFreshCompletedAndInvalidPositions() {
        XCTAssertEqual(OfflinePlaybackPolicy.resume(400, duration: 1_800), 400)
        XCTAssertEqual(OfflinePlaybackPolicy.resume(4, duration: 1_800), 0)
        XCTAssertEqual(OfflinePlaybackPolicy.resume(1_710, duration: 1_800), 0)
        XCTAssertEqual(OfflinePlaybackPolicy.resume(.nan, duration: 1_800), 0)
        XCTAssertEqual(OfflinePlaybackPolicy.resume(400, duration: .infinity), 0)
        XCTAssertEqual(OfflinePlaybackPolicy.resume(400, duration: 0), 0)
    }
    func testSeekClampsToRealMediaBoundsWithoutInventingTime() {
        XCTAssertEqual(OfflinePlaybackPolicy.seek(-10, duration: 1_800), 0)
        XCTAssertEqual(OfflinePlaybackPolicy.seek(1_810, duration: 1_800), 1_800)
        XCTAssertEqual(OfflinePlaybackPolicy.seek(400, duration: 1_800), 400)
        XCTAssertEqual(OfflinePlaybackPolicy.seek(.nan, duration: 1_800), 0)
        XCTAssertEqual(OfflinePlaybackPolicy.seek(10, duration: 0), 0)
    }
    func testEndingStateRequiresTheActualEndpointAndDoesNotFinishANearEndSkip() {
        XCTAssertTrue(OfflinePlaybackPolicy.isAtEnd(600, duration: 600))
        XCTAssertTrue(OfflinePlaybackPolicy.isAtEnd(599.999, duration: 600))
        XCTAssertFalse(OfflinePlaybackPolicy.isAtEnd(599.8, duration: 600))
        XCTAssertFalse(OfflinePlaybackPolicy.isAtEnd(0, duration: 0))
        XCTAssertFalse(OfflinePlaybackPolicy.isAtEnd(.nan, duration: 600))
    }

    @MainActor
    func testActualLocalPlayerSkipScrubReplayAndTeardown() async throws {
        let source = try XCTUnwrap(Bundle.main.url(forResource: "offline-player", withExtension: "mp4"))
        let item = try await DownloadFiles.importVideo(source)
        let local = try XCTUnwrap(item.fileURL)
        let suite = "OfflinePlaybackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = OfflinePlaybackModel(defaults: defaults)
        defer {
            model.teardown()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: local)
        }
        await model.load(item: item)
        let started = await settled(timeout: .seconds(30)) { model.isReady && model.isPlaying && !model.isBuffering }
        XCTAssertTrue(started, model.error ?? "Actual local fixture must begin playback")
        let player = try XCTUnwrap(model.player)
        model.pauseForBackground()
        let paused = await settled { !model.isPlaying }
        XCTAssertTrue(paused)
        model.seek(to: 3.3)
        await assertSeek(model, player: player, target: 3.3)

        let before = player.currentTime().seconds
        model.skip(by: 10)
        await assertSeek(model, player: player, target: before + 10)
        XCTAssertEqual(player.rate, 0, "Skipping while paused must not start playback.")

        let rapidStart = player.currentTime().seconds
        model.skip(by: 10); model.skip(by: 10); model.skip(by: 10); model.skip(by: -10)
        await assertSeek(model, player: player, target: rapidStart + 20)
        model.seek(to: 420.2)
        await assertSeek(model, player: player, target: 420.2)
        XCTAssertEqual(player.rate, 0)

        model.seek(to: model.duration - 0.5)
        await assertSeek(model, player: player, target: model.duration - 0.5)
        model.togglePlayback()
        let ended = await settled { model.finished }
        XCTAssertTrue(ended, "Replay must also work after the real end-of-file notification.")
        model.replay()
        let replayed = await settled { !model.isBuffering && model.isPlaying && player.currentTime().seconds < 5 }
        XCTAssertTrue(replayed, model.seekMessage ?? "Replay must seek to the actual beginning and start playback.")
        model.seek(to: 300)
        model.teardown()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(model.player)
        XCTAssertFalse(model.isBuffering)
        XCTAssertEqual(model.position, 0)
        XCTAssertEqual(model.duration, 0, "A late native callback must not update a torn-down or replacement player.")
    }

    @MainActor private func assertSeek(_ model: OfflinePlaybackModel, player: AVPlayer, target: Double,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        let completed = await settled {
            !model.isBuffering && abs(player.currentTime().seconds - target) <= 1.2
                && abs(model.position - player.currentTime().seconds) <= 0.3
        }
        XCTAssertTrue(completed, "Seek target=\(target), native=\(player.currentTime().seconds), published=\(model.position), loading=\(model.isBuffering), error=\(model.seekMessage ?? model.error ?? "none")", file: file, line: line)
        XCTAssertNil(model.seekMessage, file: file, line: line)
    }

    @MainActor private func settled(timeout: Duration = .seconds(12), _ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate()
    }
}
