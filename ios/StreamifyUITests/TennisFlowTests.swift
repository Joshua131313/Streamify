import XCTest

final class TennisFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-tennis-fixture"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "FAILURE tennis flow"; screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE tennis hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
    }

    func testTennisShowsAllToursThenFiltersAndOpensSetScoring() {
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
        app.buttons["tab-sports"].tap()
        let tennis = app.buttons["sports-league-option-tennis"]
        let rail = app.scrollViews["sports-league-rail"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        for _ in 0..<6 where !tennis.isHittable { rail.swipeLeft() }
        XCTAssertTrue(tennis.isHittable); tennis.tap()
        XCTAssertTrue(app.buttons["tennis-tour-challenger"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Jannik Sinner (8)"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["sports-filter-All"].exists)
        XCTAssertFalse(app.staticTexts["Doubles Player One / Partner"].exists)
        XCTAssertTrue(app.images["Jannik Sinner serving"].exists)
        app.buttons["sports-menu"].tap()
        app.buttons["sports-filter-picker"].tap()
        let doublesToggle = app.switches["tennis-show-doubles"]
        XCTAssertTrue(doublesToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(doublesToggle.value as? String, "0")
        // The switch accessibility frame includes its noninteractive row label.
        let nativeSwitch = doublesToggle.switches.firstMatch
        let control = nativeSwitch.exists ? nativeSwitch : doublesToggle
        // Operate the real native thumb; iPadOS 26 exposes the whole List row
        // and its inner switch as separate activation targets.
        let from = control.coordinate(withNormalizedOffset: CGVector(dx: nativeSwitch.exists ? 0.25 : 0.87, dy: 0.5))
        let to = control.coordinate(withNormalizedOffset: CGVector(dx: nativeSwitch.exists ? 0.8 : 0.96, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in doublesToggle.value as? String == "1" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        app.buttons["sports-filter-done"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Doubles Player One / Partner"].waitForExistence(timeout: 5))
        app.swipeDown()
        app.buttons["tennis-tour-wta"].tap()
        app.buttons["sports-filter-Pregame"].tap()
        XCTAssertTrue(app.staticTexts["Iga Swiatek (8)"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Jannik Sinner (8)"].exists)
        app.buttons["tennis-tour-challenger"].tap()
        app.buttons["sports-filter-Final"].tap()
        XCTAssertTrue(app.staticTexts["Jasika O."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Iga Swiatek (8)"].exists)
        app.buttons["tennis-tour-atp"].tap()
        app.buttons["sports-quick-live"].tap()
        let card = app.buttons["sports-game-tennis:espn-atp-185682"]
        XCTAssertTrue(card.waitForExistence(timeout: 8)); card.tap()
        let sets = app.buttons["sports-game-tab-Sets"]
        let setOne = app.buttons["Set 1"]
        XCTAssertTrue(setOne.waitForExistence(timeout: 10)); setOne.tap()
        let firstGame = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Game 1")).firstMatch
        XCTAssertTrue(firstGame.waitForExistence(timeout: 5)); firstGame.tap()
        XCTAssertTrue(app.staticTexts["Point 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Break"].exists)
        XCTAssertTrue(sets.waitForExistence(timeout: 8)); sets.tap()
        XCTAssertTrue(app.scrollViews["sports-scoring-periods"].waitForExistence(timeout: 8) || app.otherElements["sports-scoring-periods"].exists)
        XCTAssertFalse(app.buttons["sports-game-tab-Team stats"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "Tennis set scoring"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDoubleTapActiveHomeTabReturnsToTopWithoutChangingTab() {
        let home = app.buttons["tab-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        app.swipeUp(); app.swipeUp()
        home.doubleTap()
        XCTAssertTrue(app.staticTexts["The game is on."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
    }
}
