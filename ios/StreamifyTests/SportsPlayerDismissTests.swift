import XCTest
@testable import Streamify

final class SportsPlayerDismissTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)

    func testOnlyDownwardDominantMotionBegins() {
        XCTAssertTrue(SportsPlayerDismissPolicy.isDownward(CGPoint(x: 20, y: 100)))
        XCTAssertFalse(SportsPlayerDismissPolicy.isDownward(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(SportsPlayerDismissPolicy.isDownward(CGPoint(x: 0, y: -100)))
        XCTAssertFalse(SportsPlayerDismissPolicy.isDownward(.zero))
        XCTAssertFalse(SportsPlayerDismissPolicy.isDownward(CGPoint(x: CGFloat.nan, y: 100)))
    }

    func testControlsNearTheBottomAndOutsideTheCanvasAreExcluded() {
        let bounds = CGRect(origin: .zero, size: size)
        XCTAssertTrue(SportsPlayerDismissPolicy.canStart(at: CGPoint(x: 190, y: 350), in: bounds))
        XCTAssertFalse(SportsPlayerDismissPolicy.canStart(at: CGPoint(x: 190, y: 780), in: bounds))
        XCTAssertFalse(SportsPlayerDismissPolicy.canStart(at: CGPoint(x: 400, y: 350), in: bounds))
        XCTAssertFalse(SportsPlayerDismissPolicy.canStart(at: CGPoint(x: 10, y: 10), in: .zero))
        XCTAssertFalse(SportsPlayerDismissPolicy.canStart(at: CGPoint(x: 190, y: CGFloat.infinity), in: bounds))
    }

    func testShortSlowAndUpwardDragsReturnToTheSamePlayer() {
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 2, height: 64), velocity: .zero, size: size))
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 0, height: -240), velocity: CGPoint(x: 0, y: -1000), size: size))
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 220, height: 240), velocity: .zero, size: size))
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 0, height: 20), velocity: CGPoint(x: 0, y: 1400), size: size))
    }

    func testDeliberatePullAndDownwardFlickDismiss() {
        XCTAssertTrue(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 10, height: 180), velocity: .zero, size: size))
        XCTAssertTrue(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 5, height: 50), velocity: CGPoint(x: 40, y: 900), size: size))
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 0, height: 50), velocity: CGPoint(x: 900, y: 900), size: size))
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 0, height: 50), velocity: CGPoint(x: 0, y: -900), size: size))
        XCTAssertFalse(SportsPlayerDismissPolicy.shouldDismiss(translation: CGSize(width: 0, height: 180), velocity: .zero, size: .zero))
    }

    func testProgressClampsAndIgnoresInvalidGeometry() {
        XCTAssertEqual(SportsPlayerDismissPolicy.progress(translation: .zero, size: size), 0)
        XCTAssertEqual(SportsPlayerDismissPolicy.progress(translation: CGSize(width: 20, height: -10), size: size), 0)
        XCTAssertEqual(SportsPlayerDismissPolicy.progress(translation: CGSize(width: 0, height: size.height * 0.3), size: size), 0.5, accuracy: 0.001)
        XCTAssertEqual(SportsPlayerDismissPolicy.progress(translation: CGSize(width: 0, height: 900), size: size), 1)
        XCTAssertEqual(SportsPlayerDismissPolicy.progress(translation: CGSize(width: 0, height: CGFloat.nan), size: size), 0)
        XCTAssertEqual(SportsPlayerDismissPolicy.progress(translation: CGSize(width: 0, height: 20), size: .zero), 0)
    }
}
