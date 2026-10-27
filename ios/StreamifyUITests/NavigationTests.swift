import XCTest

final class NavigationTests: XCTestCase {
    func testGuestCanSwitchTabsAndReachSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let profile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile-tile-")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        capture(app, "Production launch profile chooser")
        profile.tap()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Home"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The custom floating navigation must not have a second system tab bar beneath it.")
        capture(app, "Home")
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone"].waitForExistence(timeout: 5))
        capture(app, "My list")
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
        capture(app, "Search")
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        capture(app, "Sports")
        app.buttons["More options"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(app, "Settings before scrolling the native Form")
        let save = app.buttons["save-settings"]
        revealSettingsSave(save, in: app)
        XCTAssertTrue(save.exists && save.isHittable && save.isEnabled,
            "The actual Save settings row must be reachable and enabled after scrolling.")
        capture(app, "Settings Save row reached through the native Form")
        save.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-sports"].wait(for: \.isHittable, toEqual: true, timeout: 5), "Saving empty settings must succeed with the simulator's signed Keychain configuration.")
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
    }

    private func revealSettingsSave(_ save: XCUIElement, in app: XCUIApplication) {
        // A native Form virtualizes offscreen rows. Scroll before requiring
        // Save's accessibility node to exist, using the actual form viewport.
        let collection = app.collectionViews.firstMatch
        let table = app.tables.firstMatch
        let scroll = collection.exists ? collection : table.exists ? table : app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Settings must expose its native scrollable form.")
        for _ in 0..<10 {
            if save.exists && save.isHittable { return }
            let viewport = scroll.frame.intersection(app.frame)
            let top = max(viewport.minY + 18, app.navigationBars["Settings"].frame.maxY + 12)
            let bottom = viewport.maxY - 24
            XCTAssertGreaterThan(bottom - top, 60, "The real Settings form must leave a scrollable viewport.")
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX, dy: top + (bottom - top) * 0.85 - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX, dy: top + (bottom - top) * 0.2 - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(save.exists && save.isHittable, "Scrolling Settings must reveal its actual Save action.")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
