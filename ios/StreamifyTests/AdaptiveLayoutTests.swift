import XCTest
@testable import Streamify

final class AdaptiveLayoutTests: XCTestCase {
    func testIPadProUsesMultipleCardsWithoutAffectingNarrowWindows() {
        XCTAssertEqual(AdaptiveLayout.columns(width: 1008, minimum: 420), 2)
        XCTAssertEqual(AdaptiveLayout.columns(width: 1350, minimum: 420), 3)
        XCTAssertEqual(AdaptiveLayout.columns(width: 390, minimum: 420), 1)
        XCTAssertEqual(AdaptiveLayout.columns(width: 507, minimum: 420), 1)
    }
    func testDetailColumnsFollowWindowWidthAndAccessibilityRatherThanDeviceModel() {
        XCTAssertTrue(AdaptiveLayout.usesDetailColumns(width: 1024, accessibility: false))
        XCTAssertTrue(AdaptiveLayout.usesDetailColumns(width: 1366, accessibility: false))
        XCTAssertFalse(AdaptiveLayout.usesDetailColumns(width: 680, accessibility: false))
        XCTAssertFalse(AdaptiveLayout.usesDetailColumns(width: 1024, accessibility: true))
    }
}
