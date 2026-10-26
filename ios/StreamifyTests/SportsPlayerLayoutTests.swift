import XCTest
import UIKit
@testable import Streamify

final class SportsPlayerLayoutTests: XCTestCase {
    func testLandscapeUsesEntireCanvasEvenWithNotchAndHomeIndicatorInsets() {
        for size in [CGSize(width: 852, height: 393), CGSize(width: 932, height: 430)] {
            for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)] {
                let layout = SportsPlayerVideoLayout(size: size, safeArea: insets)
                XCTAssertTrue(layout.isLandscape)
                XCTAssertEqual(layout.videoFrame, CGRect(origin: .zero, size: size))
            }
        }
    }
    func testPortraitKeepsSelectorsAndUtilityButtonsOutsideVideo() {
        let layout = SportsPlayerVideoLayout(size: CGSize(width: 393, height: 852),
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
        XCTAssertFalse(layout.isLandscape)
        XCTAssertEqual(layout.videoFrame.minY, 167)
        XCTAssertEqual(layout.videoFrame.maxY, 764)
        XCTAssertEqual(layout.videoFrame.width, 393)
    }
}
