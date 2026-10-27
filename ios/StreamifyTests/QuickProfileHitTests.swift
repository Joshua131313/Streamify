import CoreGraphics
import Foundation
import XCTest
@testable import Streamify

final class QuickProfileHitTests: XCTestCase {
    private let first = UUID(), second = UUID()
    private var rows: [UUID: CGRect] {
        [first: CGRect(x: 0, y: 0, width: 244, height: 60),
         second: CGRect(x: 0, y: 64, width: 244, height: 60)]
    }
    private let bounds = CGRect(x: 0, y: 0, width: 244, height: 124)

    func testReleasePointSelectsTheRowUnderTheFingerInsteadOfTheOriginatingRow() {
        XCTAssertEqual(LiquidGlassProfileHitPolicy.target(at: CGPoint(x: 122, y: 30), rows: rows, visibleBounds: bounds), first)
        XCTAssertEqual(LiquidGlassProfileHitPolicy.target(at: CGPoint(x: 122, y: 94), rows: rows, visibleBounds: bounds), second)
    }

    func testSpacingOutsideAndNonfinitePointsNeverSelectAProfile() {
        for point in [CGPoint(x: 122, y: 62), CGPoint(x: -1, y: 30), CGPoint(x: 122, y: 125),
                      CGPoint(x: CGFloat.nan, y: 30), CGPoint(x: 122, y: CGFloat.infinity)] {
            XCTAssertNil(LiquidGlassProfileHitPolicy.target(at: point, rows: rows, visibleBounds: bounds))
        }
    }

    func testClippedScrollViewportRejectsInvisibleRowsWhileKeepingVisibleRowCoordinates() {
        let scrolledViewport = CGRect(x: 0, y: 64, width: 244, height: 60)
        XCTAssertNil(LiquidGlassProfileHitPolicy.target(at: CGPoint(x: 122, y: 30), rows: rows, visibleBounds: scrolledViewport))
        XCTAssertEqual(LiquidGlassProfileHitPolicy.target(at: CGPoint(x: 122, y: 94), rows: rows, visibleBounds: scrolledViewport), second)
    }
}
