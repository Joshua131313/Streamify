import XCTest

final class NavigationTests: XCTestCase {
    func testGuestCanSwitchTabsAndReachSettings() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Home"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The custom floating navigation must not have a second system tab bar beneath it.")
        capture(app, "Home")
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone"].waitForExistence(timeout: 5))
        capture(app, "My list")
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.textFields["browse-search"].waitForExistence(timeout: 5))
        capture(app, "Search")
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        capture(app, "Sports")
        app.buttons["More options"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["save-settings"].waitForExistence(timeout: 5))
        capture(app, "Settings")
        let save = app.buttons["save-settings"]
        for _ in 0..<5 {
            if save.isHittable { break }
            app.swipeUp()
        }
        save.tap()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 5), "Saving empty settings must succeed with the simulator's signed Keychain configuration.")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
