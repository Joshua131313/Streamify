import XCTest
@testable import Streamify

@MainActor
final class SportsMultiWatchAudioTests: XCTestCase {
    func testEveryMuteAcknowledgesBeforeTheNextPlayerUnmutes() async {
        let log = AudioLog(), audio = SportsMultiWatchAudio()
        let first = AudioTarget("first", log), second = AudioTarget("second", log)
        audio.register(first, id: "first"); audio.register(second, id: "second")
        audio.setActive(true); audio.select("first")
        await eventually { audio.audibleID == "first" }
        log.events = []
        first.holdMute = true
        audio.select("second")
        await eventually { first.continuation != nil }
        XCTAssertFalse(second.audible, "The old frame has not acknowledged muting yet.")
        XCTAssertFalse(log.events.contains("second:unmute:start"))
        first.release()
        await eventually { audio.audibleID == "second" }
        XCTAssertFalse(first.audible); XCTAssertTrue(second.audible)
        let unmute = log.events.firstIndex(of: "second:unmute:start")!
        XCTAssertLessThan(log.events.firstIndex(of: "first:mute:end")!, unmute)
        XCTAssertLessThan(log.events.firstIndex(of: "second:mute:end")!, unmute)
    }

    func testRapidSelectionAndBackgroundDoNotCommitAStaleUnmute() async {
        let log = AudioLog(), audio = SportsMultiWatchAudio()
        let first = AudioTarget("first", log), second = AudioTarget("second", log)
        audio.register(first, id: "first"); audio.register(second, id: "second")
        audio.setActive(true); audio.select("first")
        await eventually { audio.audibleID == "first" }
        log.events = []; first.holdMute = true
        audio.select("second")
        await eventually { first.continuation != nil }
        audio.select("first"); audio.setActive(false)
        first.release()
        await eventually { !first.audible && !second.audible && log.events.filter { $0 == "first:mute:end" }.count >= 2 }
        XCTAssertFalse(log.events.contains { $0.contains(":unmute:start") })
        XCTAssertNil(audio.audibleID)
        audio.setActive(true)
        await eventually { audio.audibleID == "first" }
    }

    func testReplacingOrRemovingPlayerDuringUnmuteRetainsItInMuteBarrier() async {
        let log = AudioLog(), audio = SportsMultiWatchAudio()
        let old = AudioTarget("old", log), replacement = AudioTarget("new", log)
        old.holdUnmute = true
        audio.register(old, id: "tile"); audio.setActive(true); audio.select("tile")
        await eventually { old.continuation != nil && old.audible }
        audio.unregister(old, id: "tile")
        audio.register(replacement, id: "tile")
        old.release()
        await eventually { audio.audibleID == "tile" && replacement.audible }
        XCTAssertFalse(old.audible)
        let unmute = log.events.firstIndex(of: "new:unmute:start")!
        XCTAssertLessThan(log.events.lastIndex(of: "old:mute:end")!, unmute)
    }

    func testMuteFailureStaysClosedAndExplicitRetryCanRecover() async {
        let log = AudioLog(), audio = SportsMultiWatchAudio()
        let first = AudioTarget("first", log), second = AudioTarget("second", log)
        audio.register(first, id: "first"); audio.register(second, id: "second")
        audio.setActive(true); audio.select("first")
        await eventually { audio.audibleID == "first" }
        log.events = []; first.failMute = true
        audio.select("second")
        await eventually { audio.errorMessage != nil }
        XCTAssertNil(audio.audibleID); XCTAssertFalse(second.audible)
        XCTAssertFalse(log.events.contains("second:unmute:start"))
        first.failMute = false; audio.retry()
        await eventually { audio.audibleID == "second" }
        XCTAssertNil(audio.errorMessage); XCTAssertFalse(first.audible)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition(), "Audio coordinator did not settle", file: file, line: line)
    }
}

@MainActor private final class AudioLog { var events: [String] = [] }

@MainActor private final class AudioTarget: SportsMultiWatchAudioTarget {
    let name: String
    let log: AudioLog
    var audible = false
    var holdMute = false
    var holdUnmute = false
    var failMute = false
    var continuation: CheckedContinuation<Void, Never>?
    init(_ name: String, _ log: AudioLog) { self.name = name; self.log = log }
    func setAudible(_ value: Bool) async throws {
        let operation = value ? "unmute" : "mute"
        log.events.append("\(name):\(operation):start")
        if !value, failMute { throw NSError(domain: "AudioFixture", code: 1) }
        if value { audible = true }
        if value ? holdUnmute : holdMute {
            holdMute = false; holdUnmute = false
            await withCheckedContinuation { continuation = $0 }
        }
        audible = value
        log.events.append("\(name):\(operation):end")
    }
    func release() { continuation?.resume(); continuation = nil }
}
