import XCTest
@testable import Streamify

final class SportsPlaybackSessionTests: XCTestCase {
    @MainActor func testMinimizeRestoreKeepsIdentityAndSelectedSource() {
        let first = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let second = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession()
        session.play(title: "Away vs Home", url: first.url, sources: [first, second])
        let identity = session.item?.id
        session.selectSource(second)
        session.toggleDirect(); session.reloadCurrent()
        session.minimize()
        XCTAssertTrue(session.isMinimized)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
        XCTAssertEqual(session.sourceTitle, "Bravo")
        session.expand()
        XCTAssertTrue(session.isExpanded)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
        XCTAssertEqual(session.reload, 1)
        XCTAssertTrue(session.direct)
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
        session.minimize(); session.expand()
        XCTAssertEqual(session.item?.id, identity)
        session.close()
        XCTAssertNil(session.item)
        XCTAssertFalse(session.isExpanded)
        XCTAssertFalse(session.isMinimized)
        XCTAssertEqual(session.reload, 0)
        XCTAssertFalse(session.direct)
    }
}
