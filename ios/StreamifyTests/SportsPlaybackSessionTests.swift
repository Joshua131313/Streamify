import XCTest
@testable import Streamify

final class SportsPlaybackSessionTests: XCTestCase {
    @MainActor func testPresentationKeepsTheSameStreamOriginAndNativePiPOwner() {
        let source = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo.mp4")!)
        let session = SportsPlaybackSession()
        let origin = SportsPlaybackOrigin()
        session.play(title: "Game", url: source.url, sources: [source], origin: origin)
        let identity = session.item?.id, owner = UUID()
        session.pictureInPicture.attach(owner: owner, capability: .available, request: {}, stop: {})
        session.expand()
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, source.url)
        XCTAssertTrue(session.origin === origin)
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner), "Presentation must not replace the actual PiP/player driver")
        XCTAssertEqual(session.reload, 0)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertTrue(session.isPiPActive)
        session.pictureInPicture.didStop(owner: owner, restoring: true)
        XCTAssertTrue(session.isExpanded)
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner))
        XCTAssertEqual(session.item?.id, identity)
        session.close()
        XCTAssertNil(session.origin, "Closing must release the old return card before another game opens")
    }

    @MainActor func testOnlyConfirmedSystemPiPHidesPlayerAndRestoreKeepsSource() {
        let first = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let second = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession()
        session.play(title: "Away vs Home", url: first.url, sources: [first, second])
        let identity = session.item?.id
        session.selectSource(second)
        let owner = UUID()
        var requested = 0, stopped = 0
        session.pictureInPicture.attach(owner: owner, capability: .available, request: { requested += 1 }, stop: { stopped += 1 })
        session.requestPictureInPicture()
        XCTAssertEqual(requested, 1)
        XCTAssertTrue(session.isExpanded, "An attempted request must not hide the player.")
        XCTAssertFalse(session.isPiPActive)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertTrue(session.isPiPActive)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
        XCTAssertEqual(session.sourceTitle, "Bravo")
        session.expand()
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(session.isPiPActive, "Restore waits for the real PiP stop callback.")
        session.pictureInPicture.didStop(owner: owner, restoring: true)
        XCTAssertTrue(session.isExpanded)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
    }

    @MainActor func testOnlyExplicitCloseEndsSessionAndInvalidSourceIsIgnored() {
        let source = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let session = SportsPlaybackSession()
        session.play(title: "Game", url: source.url, sources: [source])
        let identity = session.item?.id
        session.selectSource(SportsStream(title: "Unknown", url: URL(string: "https://example.com/other")!))
        XCTAssertEqual(session.item?.url, source.url)
        session.play(title: "Insecure", url: URL(string: "http://example.com/insecure")!)
        XCTAssertEqual(session.item?.id, identity)
        session.expand()
        XCTAssertEqual(session.item?.id, identity)
        session.close()
        XCTAssertNil(session.item)
        XCTAssertFalse(session.isExpanded)
        XCTAssertFalse(session.isMinimized)
        XCTAssertEqual(session.reload, 0)
        XCTAssertFalse(session.direct)
    }

    @MainActor func testUnsupportedAndStaleDriversNeverHideOrReplacePlayer() {
        let first = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let second = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession()
        session.play(title: "Game", url: first.url, sources: [first, second])
        let identity = session.item?.id, owner = UUID()
        session.pictureInPicture.attach(owner: owner, capability: .unavailable, request: { XCTFail("Unsupported PiP must not request a fake window") }, stop: {})
        session.requestPictureInPicture()
        XCTAssertTrue(session.isExpanded)
        XCTAssertNotNil(session.pictureInPicture.message)
        session.selectSource(second)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertFalse(session.isPiPActive)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
        session.close()
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertNil(session.item)
    }
}
