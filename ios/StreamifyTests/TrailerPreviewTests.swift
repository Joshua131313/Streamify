import Foundation
import XCTest
@testable import Streamify

final class TrailerPreviewTests: XCTestCase {
    func testTrailerURLsRequireYouTubeHostHTTPSAndExactVideoIdentity() {
        let id = "M7lc1UVf-VE"
        for value in ["https://www.youtube.com/watch?v=\(id)", "https://youtu.be/\(id)?t=3", "https://www.youtube.com/embed/\(id)", "https://m.youtube.com/watch?v=\(id)", "https://www.youtube-nocookie.com/embed/\(id)"] {
            XCTAssertEqual(TrailerDocument.videoID(from: URL(string: value)), id)
        }
        for value in ["https://youtube.com.evil.example/watch?v=\(id)", "https://example.com/watch?v=\(id)", "http://www.youtube.com/watch?v=\(id)", "https://user@www.youtube.com/watch?v=\(id)", "https://www.youtube.com/watch?v=\(id)&v=abcdefghijk", "https://youtu.be/\(id)/extra", "https://www.youtube.com:444/watch?v=\(id)", "https://www.youtube.com/watch?v=short"] {
            XCTAssertNil(TrailerDocument.videoID(from: URL(string: value)), value)
        }
        XCTAssertNil(TrailerDocument.videoID(from: nil))
        XCTAssertFalse(TrailerDocument.validID("\(id)\n"))
        XCTAssertFalse(TrailerDocument.validID("abcde'fghij"))
    }

    func testDocumentUsesInstalledBundleIdentityAndEscapesScriptBoundary() throws {
        let token = "</script><script>alert('x')</script>\u{2028}"
        let document = try XCTUnwrap(TrailerDocument.document(videoID: "M7lc1UVf-VE", bundleIdentifier: "Com.Streamify.App.Team123", token: token))
        XCTAssertEqual(TrailerDocument.origin(bundleIdentifier: "Com.Streamify.App.Team123").absoluteString, "https://com.streamify.app.team123/")
        XCTAssertTrue(document.contains("com.streamify.app.team123"))
        XCTAssertTrue(document.contains("strict-origin-when-cross-origin"))
        XCTAssertTrue(document.contains("controls:1"), "The official player controls and branding must remain available.")
        XCTAssertTrue(document.contains("playsinline:1"))
        XCTAssertTrue(document.contains("onAutoplayBlocked"))
        XCTAssertTrue(document.contains("onError"))
        XCTAssertFalse(document.contains(token))
        XCTAssertTrue(document.contains("\\u003c"))
        XCTAssertEqual(TrailerDocument.origin(bundleIdentifier: "evil.example/\"</script>").absoluteString, "https://com.streamify.app/")
        XCTAssertNil(TrailerDocument.document(videoID: "bad');alert(1)", bundleIdentifier: nil, token: "fixture"))
    }

    func testFailureIsTerminalAndAlwaysKeepsPosterVisible() {
        var state = TrailerPlaybackState.loading
        XCTAssertFalse(state.revealsPlayer)
        XCTAssertFalse(state.wantsPlayback(active: true))
        state.receive(event: "ready")
        XCTAssertTrue(state.revealsPlayer)
        XCTAssertTrue(state.wantsPlayback(active: true))
        state.receive(event: "state", value: 1)
        XCTAssertEqual(state, .playing)
        XCTAssertFalse(state.wantsPlayback(active: false), "Background, disappearance and offscreen activity must pause playback.")
        state.receive(event: "error", value: 153)
        XCTAssertEqual(state, .failed)
        XCTAssertFalse(state.revealsPlayer)
        XCTAssertFalse(state.wantsPlayback(active: true))
        state.receive(event: "state", value: 1)
        XCTAssertEqual(state, .failed, "Late player callbacks must not uncover a failed player.")
        var blocked = TrailerPlaybackState.ready
        blocked.receive(event: "blocked")
        XCTAssertEqual(blocked, .failed)
        XCTAssertFalse(blocked.revealsPlayer)
    }

    func testEndedVideoWaitsForReplayInsteadOfResumingOnForeground() {
        var state = TrailerPlaybackState.playing
        state.receive(event: "state", value: 0)
        XCTAssertEqual(state, .ended)
        XCTAssertFalse(state.wantsPlayback(active: true))
        state.receive(event: "state", value: 2)
        XCTAssertEqual(state, .ended, "A pause acknowledgement after ending must preserve the replay button.")
        state.receive(event: "state", value: 1)
        XCTAssertEqual(state, .playing)
    }

    func testPauseAndMuteUseTypedArguments() {
        let pause = TrailerPlaybackCommand.activity(false)
        XCTAssertEqual(pause.arguments["wanted"] as? Bool, false)
        XCTAssertTrue(pause.script.contains("setWanted(wanted)"))
        XCTAssertFalse(pause.script.contains("false"), "Runtime values belong in arguments, never executable JavaScript.")
        XCTAssertEqual(TrailerPlaybackCommand.mute(true).arguments["muted"] as? Bool, true)
        XCTAssertTrue(TrailerPlaybackCommand.replay.arguments.isEmpty)
        XCTAssertTrue(TrailerPlaybackCommand.destroy.script.contains("destroy()"))
    }
}
