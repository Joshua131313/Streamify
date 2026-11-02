import Foundation
import SwiftUI
import XCTest
@testable import Streamify

final class SportsPaginationTests: XCTestCase {
    func testLargeScheduleRevealsBoundedPagesAndStaleFootersCannotRepeatARequest() {
        var window = SportsPageWindow()
        XCTAssertEqual(window.count(total: 1000, scope: "men-live"), 24)
        XCTAssertTrue(window.advance(total: 1000, scope: "men-live", expectedCount: 24))
        XCTAssertEqual(window.count(total: 1000, scope: "men-live"), 48)
        XCTAssertFalse(window.advance(total: 1000, scope: "men-live", expectedCount: 24))
        XCTAssertEqual(window.count(total: 1000, scope: "men-live"), 48)
        XCTAssertTrue(window.advance(total: 50, scope: "men-live", expectedCount: 48))
        XCTAssertEqual(window.count(total: 50, scope: "men-live"), 50)
        XCTAssertFalse(window.advance(total: 50, scope: "men-live", expectedCount: 50))
    }
    func testFiltersDatesAndSearchScopesKeepIndependentProgressWithoutLosingRefreshState() {
        var window = SportsPageWindow()
        window.advance(total: 182, scope: "men-live-today", expectedCount: 24)
        XCTAssertEqual(window.count(total: 164, scope: "women-live-today"), 24)
        XCTAssertEqual(window.count(total: 182, scope: "men-final-yesterday"), 24)
        XCTAssertEqual(window.count(total: 182, scope: "men-live-today"), 48)
        XCTAssertEqual(window.count(total: 10, scope: "men-live-today"), 10)
        XCTAssertEqual(window.count(total: 190, scope: "men-live-today"), 48)
        XCTAssertEqual(window.count(total: 0, scope: "empty-filter"), 0)
    }
    func testOnlyVisibleOrApproachingFootersCanAutomaticallyExpand() {
        let viewport = CGRect(x: 0, y: 60, width: 390, height: 700)
        XCTAssertFalse(SportsPageWindow.nearViewport(CGRect(x: 0, y: 6000, width: 390, height: 44), viewport: viewport))
        XCTAssertFalse(SportsPageWindow.nearViewport(CGRect(x: 0, y: -100, width: 390, height: 44), viewport: viewport))
        XCTAssertFalse(SportsPageWindow.nearViewport(CGRect(x: 0, y: 700, width: 390, height: 44), viewport: .zero))
        XCTAssertTrue(SportsPageWindow.nearViewport(CGRect(x: 0, y: 800, width: 390, height: 44), viewport: viewport))
        XCTAssertFalse(SportsPageWindow.nearViewport(CGRect(x: 2000, y: 80, width: 190, height: 180), viewport: viewport, axis: .horizontal))
        XCTAssertTrue(SportsPageWindow.nearViewport(CGRect(x: 400, y: 80, width: 190, height: 180), viewport: viewport, axis: .horizontal))
    }
    func testCalendarDecodesIdentityDateAndStateWithoutNeedingTeamOrPlayerTrees() throws {
        let raw: [String: Any] = ["events": [["id": "401900001", "date": "2026-11-02T23:00Z",
            "competitions": [["status": ["type": ["state": "pre"]]]]]]]
        let markers = try SportsCalendarEventMarker.parse(JSONSerialization.data(withJSONObject: raw), league: .ncaam)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.id, "mens-college-basketball:401900001")
        XCTAssertEqual(markers.first?.state, "pre")
        XCTAssertNotNil(markers.first?.date)
    }
    func testCompactCalendarKeepsFinalOverAStaleOvernightLiveCopy() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        let yesterday = today.addingTimeInterval(-86_400)
        func marker(_ state: String) throws -> SportsCalendarEventMarker {
            let raw: [String: Any] = ["events": [["id": "401900001", "date": "2026-11-01T23:00:00Z", "status": ["type": ["state": state]]]]]
            return try XCTUnwrap(SportsCalendarEventMarker.parse(JSONSerialization.data(withJSONObject: raw), league: .ncaam).first)
        }
        let live = try marker("in"), final = try marker("post")
        let current = SportsCalendarEventMarker.days([live], now: today.addingTimeInterval(3600), calendar: calendar, first: yesterday, last: today)
        XCTAssertEqual(current[today], [.ncaam])
        let canonical = SportsCalendarEventMarker.days([final, live], now: today.addingTimeInterval(3600), calendar: calendar, first: yesterday, last: today)
        XCTAssertNil(canonical[today]); XCTAssertEqual(canonical[yesterday], [.ncaam])
    }
}
