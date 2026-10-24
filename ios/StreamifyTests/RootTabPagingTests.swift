import XCTest
@testable import Streamify

final class RootTabPagingTests: XCTestCase {
    func testDistanceAndVelocityCommitOnlyAnAdjacentPage() {
        XCTAssertEqual(RootTabPaging.destination(index: 0, count: 4, width: 400, translation: -140, velocity: -100), 1)
        XCTAssertEqual(RootTabPaging.destination(index: 1, count: 4, width: 400, translation: 30, velocity: 900), 0)
        XCTAssertEqual(RootTabPaging.destination(index: 2, count: 4, width: 400, translation: -40, velocity: -100), 2)
        XCTAssertEqual(RootTabPaging.destination(index: 1, count: 4, width: 400, translation: -150, velocity: 2_000), 1)
    }
    func testEndsResistAndCannotNavigateOutsideAvailablePages() {
        XCTAssertEqual(RootTabPaging.offset(100, index: 0, count: 4, width: 400), 28, accuracy: 0.001)
        XCTAssertEqual(RootTabPaging.offset(-100, index: 3, count: 4, width: 400), -28, accuracy: 0.001)
        XCTAssertEqual(RootTabPaging.offset(-100, index: 1, count: 4, width: 400), -100)
        XCTAssertEqual(RootTabPaging.destination(index: 0, count: 4, width: 400, translation: 150, velocity: 1_000), 0)
        XCTAssertEqual(RootTabPaging.destination(index: 3, count: 4, width: 400, translation: -150, velocity: -1_000), 3)
    }
}
