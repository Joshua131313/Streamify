import XCTest

final class NavigationTests: XCTestCase {
    func testGuestCanSwitchTabsAndReachSettings() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 10))
        capture(app, "Home")
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone"].waitForExistence(timeout: 5))
        capture(app, "My list")
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.textFields["Movies, shows, and more"].waitForExistence(timeout: 5))
        capture(app, "Search")
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        capture(app, "Sports")
        app.buttons["More options"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["save-settings"].waitForExistence(timeout: 5))
        capture(app, "Settings")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
