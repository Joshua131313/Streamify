import XCTest

final class TennisFlowTests: XCTestCase {
    func testTennisShowsAllToursThenFiltersAndOpensSetScoring() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-tennis-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
        app.buttons["tab-sports"].tap()
        let tennis = app.buttons["sports-league-option-tennis"]
        let rail = app.scrollViews["sports-league-rail"]
        for _ in 0..<6 where !tennis.isHittable { rail.swipeLeft() }
        XCTAssertTrue(tennis.isHittable); tennis.tap()
        XCTAssertTrue(app.buttons["tennis-tour-challenger"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Jannik Sinner"].waitForExistence(timeout: 15))
        app.buttons["tennis-tour-wta"].tap()
        XCTAssertTrue(app.staticTexts["Iga Swiatek"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Jannik Sinner"].exists)
        app.buttons["tennis-tour-challenger"].tap()
        XCTAssertTrue(app.staticTexts["Jasika O."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Iga Swiatek"].exists)
        app.buttons["tennis-tour-atp"].tap()
        let card = app.buttons["sports-game-tennis:espn-atp-185682"]
        XCTAssertTrue(card.waitForExistence(timeout: 8)); card.tap()
        let sets = app.buttons["sports-game-tab-Sets"]
        XCTAssertTrue(sets.waitForExistence(timeout: 8)); sets.tap()
        XCTAssertTrue(app.scrollViews["sports-scoring-periods"].waitForExistence(timeout: 8) || app.otherElements["sports-scoring-periods"].exists)
        XCTAssertFalse(app.buttons["sports-game-tab-Team stats"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Tennis set scoring"; screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
    }
}
