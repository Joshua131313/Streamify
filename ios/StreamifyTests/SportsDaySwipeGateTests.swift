import XCTest
@testable import Streamify

final class SportsDaySwipeGateTests: XCTestCase {
    @MainActor
    func testProtectedHorizontalDragSuppressesReleaseButTheNextTapIsEnabled() {
        let scope = SportsDaySwipeScope()
        XCTAssertTrue(scope.permitsProtectedAction)
        scope.beginTouch()
        scope.beginProtectedDrag()
        XCTAssertFalse(scope.permitsProtectedAction)
        scope.endProtectedDrag()
        XCTAssertFalse(scope.permitsProtectedAction, "A delayed SwiftUI release action still belongs to the drag.")
        scope.beginTouch()
        XCTAssertTrue(scope.permitsProtectedAction, "A fresh physical tap must not inherit the preceding cancellation.")
    }

    func testDeliberateLeftAndRightSwipesChooseAdjacentDay() {
        XCTAssertEqual(SportsDaySwipeGate.direction(translation: CGPoint(x: -120, y: 12)), 1)
        XCTAssertEqual(SportsDaySwipeGate.direction(translation: CGPoint(x: 120, y: -12)), -1)
        XCTAssertEqual(SportsDaySwipeGate.direction(translation: CGPoint(x: -72, y: 0)), 1)
    }

    func testTapsShortDragsAndVerticalScrollingDoNotChooseDay() {
        XCTAssertNil(SportsDaySwipeGate.direction(translation: .zero))
        XCTAssertNil(SportsDaySwipeGate.direction(translation: CGPoint(x: -50, y: 0)))
        XCTAssertNil(SportsDaySwipeGate.direction(translation: CGPoint(x: -100, y: 90)))
        XCTAssertNil(SportsDaySwipeGate.direction(translation: CGPoint(x: 20, y: 140)))
        XCTAssertFalse(SportsDaySwipeGate.horizontal(CGPoint(x: CGFloat.infinity, y: 0)))
        XCTAssertFalse(SportsDaySwipeGate.horizontal(CGPoint(x: CGFloat.nan, y: 0)))
    }
}
