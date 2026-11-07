import XCTest
@testable import Streamify

final class AdaptiveLayoutTests: XCTestCase {
    func testTabletHeroAdaptsToRotationAndKeepsRoomForReadableControls() {
        let portrait = AdaptiveLayout.tabletHeroHeight(width: 992, accessibility: false)
        let landscape = AdaptiveLayout.tabletHeroHeight(width: 1334, accessibility: false)
        XCTAssertEqual(portrait, 420)
        XCTAssertEqual(landscape, 520)
        XCTAssertGreaterThan(landscape, portrait)
        XCTAssertEqual(AdaptiveLayout.tabletHeroHeight(width: 680, accessibility: false), 420)
        XCTAssertEqual(AdaptiveLayout.tabletHeroHeight(width: 1334, accessibility: true), 620)
    }
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
