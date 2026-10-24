import XCTest
@testable import Streamify

final class PlayerDismissGateTests: XCTestCase {
    func testOnlyPlayerHeaderAndRightEdgeCanStart() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        XCTAssertTrue(PlayerDismissGate.canStart(at: CGPoint(x: 200, y: 90), in: bounds))
        XCTAssertTrue(PlayerDismissGate.canStart(at: CGPoint(x: 380, y: 500), in: bounds))
        XCTAssertFalse(PlayerDismissGate.canStart(at: CGPoint(x: 200, y: 500), in: bounds), "Interior video scrubbing must not arm dismissal.")
        XCTAssertFalse(PlayerDismissGate.canStart(at: CGPoint(x: 20, y: 500), in: bounds))
        XCTAssertFalse(PlayerDismissGate.canStart(at: CGPoint(x: 420, y: 80), in: bounds))
        XCTAssertFalse(PlayerDismissGate.canStart(at: .zero, in: .zero))
    }
    func testOnlySufficientlyLongDominantLeftwardPanDismisses() {
        XCTAssertTrue(PlayerDismissGate.shouldDismiss(CGPoint(x: -120, y: 20)))
        XCTAssertFalse(PlayerDismissGate.shouldDismiss(CGPoint(x: -80, y: 0)))
        XCTAssertFalse(PlayerDismissGate.shouldDismiss(CGPoint(x: 140, y: 0)))
        XCTAssertFalse(PlayerDismissGate.shouldDismiss(CGPoint(x: -120, y: 100)))
        XCTAssertFalse(PlayerDismissGate.isLeftward(CGPoint(x: -40, y: 90)))
    }
}
