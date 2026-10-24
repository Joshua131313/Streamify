import Foundation
import XCTest
@testable import Streamify

final class SportsWatchQueueTests: XCTestCase {
    @MainActor func testChoosingResolvedSourceOnlyUpdatesTargetTileAndRetainsIdentity() throws {
        let primary = SportsStream(title: "Source one", url: try XCTUnwrap(URL(string: "https://example.com/one")))
        let alternate = SportsStream(title: "Source two", url: try XCTUnwrap(URL(string: "https://example.com/two")))
        let other = SportsStream(title: "Other game", url: try XCTUnwrap(URL(string: "https://example.com/other")))
        let tile = SportsStream(title: "Fixture matchup", url: primary.url, alternatives: [primary, alternate])
        let queue = SportsWatchQueue()
        queue.add(tile); queue.add(other)
        let identities = queue.streams.map(\.id)
        queue.selectSource(streamID: tile.id, url: alternate.url)
        XCTAssertEqual(queue.streams.map(\.id), identities, "Changing source must keep tile and audible-selection identities stable")
        XCTAssertEqual(queue.streams[0].url, alternate.url)
        XCTAssertEqual(queue.streams[0].title, tile.title)
        XCTAssertEqual(queue.streams[1], other, "Other tile values must remain identical so their WKWebViews do not reload")
        XCTAssertEqual(queue.streams[0].availableSources.map(\.url), [primary.url, alternate.url])
    }

    @MainActor func testInvalidAndUnresolvedChoicesDoNotChangeTheQueue() throws {
        let current = SportsStream(title: "Fixture", url: try XCTUnwrap(URL(string: "https://example.com/current")))
        let queue = SportsWatchQueue(); queue.add(current)
        queue.selectSource(streamID: current.id, url: try XCTUnwrap(URL(string: "https://example.com/unresolved")))
        queue.selectSource(streamID: "missing-tile", url: current.url)
        XCTAssertEqual(queue.streams, [current])
        XCTAssertEqual(current.availableSources.map(\.url), [current.url], "A tile with no alternatives must offer only its current resolved source")
    }
}
