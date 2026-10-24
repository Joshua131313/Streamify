import XCTest
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
}
