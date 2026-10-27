import XCTest

/// Local scoreboard fixtures exercise historical selection through the real
/// calendar, filters and cards; they never contact a scores or stream service.
final class PastSportsResultsFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-past-sports-results"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
        app.buttons["tab-sports"].tap()
        let nba = app.buttons["sports-league-option-nba"]
        let rail = app.scrollViews["sports-league-rail"].firstMatch
        for _ in 0..<4 { if nba.isHittable { break }; rail.swipeLeft() }
        XCTAssertTrue(nba.isHittable)
        nba.tap()
        XCTAssertTrue(wait { nba.isSelected })
        XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { capture("FAILURE recent sports results") }
        app?.terminate()
    }

    func testCalendarShowsBothRecentFinalDaysAndLiveReturnsToTodayWithoutChangingLeague() {
        let live = app.buttons["sports-quick-live"]
        let originalDate = app.buttons["sports-date-picker"].value as? String
        for offset in [-1, -2] {
            chooseDay(offset)
            XCTAssertTrue(app.buttons["sports-filter-Final"].isSelected)
            XCTAssertTrue(app.buttons["sports-game-nba:nba-past-final-\(-offset)"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sports-watch-")).firstMatch.exists,
                "Finished games must not offer Watch.")
            XCTAssertTrue(live.isEnabled)
            XCTAssertEqual(app.buttons["sports-league-picker"].value as? String, "NBA")
            capture("NBA final results day \(offset)")
        }
        live.tap()
        XCTAssertTrue(wait { live.isSelected && self.app.buttons["sports-date-picker"].value as? String == originalDate })
        XCTAssertTrue(app.buttons["sports-game-nba:nba-fixture"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["sports-league-picker"].value as? String, "NBA")
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
    }

    func testHistorySwipesStopAfterTwoDaysAndLivePreservesFollowedTeams() {
        chooseDay(-1)
        let heading = app.descendants(matching: .any).matching(identifier: "sports-schedule-heading").firstMatch
        swipe(heading, towardNextDay: false)
        XCTAssertTrue(app.buttons["sports-game-nba:nba-past-final-2"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Game center"].exists, "Changing a day must never activate the card beneath the gesture's release.")
        let oldestDate = app.buttons["sports-date-picker"].value as? String
        swipe(heading, towardNextDay: false)
        XCTAssertFalse(app.navigationBars["Game center"].exists, "A boundary swipe must cancel, without opening a game.")
        XCTAssertEqual(app.buttons["sports-date-picker"].value as? String, oldestDate)
        XCTAssertTrue(app.buttons["sports-filter-Final"].isSelected)
        swipe(heading, towardNextDay: true)
        XCTAssertTrue(app.buttons["sports-game-nba:nba-past-final-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Game center"].exists)
        let followed = app.buttons["sports-followed-teams"]
        followed.tap()
        XCTAssertTrue(wait { followed.isSelected })
        app.buttons["sports-quick-live"].tap()
        XCTAssertTrue(wait { self.app.buttons["sports-quick-live"].isSelected })
        XCTAssertTrue(followed.isSelected)
        capture("Live returns to today and retains followed teams")
    }

    private func chooseDay(_ offset: Int) {
        app.buttons["sports-date-picker"].tap()
        let target = app.buttons["sports-date-offset-\(offset)"]
        if !target.exists { app.buttons["sports-calendar-previous-month"].tap() }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.isEnabled)
        target.tap()
        app.buttons["sports-calendar-done"].tap()
    }

    private func swipe(_ heading: XCUIElement, towardNextDay: Bool) {
        let start = heading.coordinate(withNormalizedOffset: CGVector(dx: towardNextDay ? 0.75 : 0.1, dy: 0.5))
        let end = heading.coordinate(withNormalizedOffset: CGVector(dx: towardNextDay ? 0.1 : 0.75, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
