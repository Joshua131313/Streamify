import XCTest

final class MoviePickFlowTests: XCTestCase {
    func testGenreChoiceRerollAndOpenExactDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-movie-pick"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
        if app.buttons["hero-carousel-pause"].label == "Pause carousel" { app.buttons["hero-carousel-pause"].tap() }
        let shortcut = app.buttons["home-pick-for-me"]
        let scroll = app.scrollViews["home-catalog"].firstMatch
        for _ in 0..<18 {
            if shortcut.exists && shortcut.isHittable && shortcut.frame.minY > app.frame.minY + 100 && shortcut.frame.maxY < app.frame.maxY - 120 { break }
            let up = !(shortcut.exists && shortcut.frame.minY < app.frame.minY + 100)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: up ? 0.75 : 0.35))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: up ? 0.35 : 0.75))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture(app, "Pick for me source after revealing actual Home scroll content")
        XCTAssertTrue(shortcut.isHittable)
        capture(app, "Home Pick for me immediately after For you")
        shortcut.tap()
        let draw = app.buttons["movie-pick-draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5)); XCTAssertFalse(draw.isEnabled)
        app.buttons["movie-pick-genre-18"].tap()
        XCTAssertTrue(draw.isEnabled)
        capture(app, "Choose a genre equal sized selectable tiles")
        draw.tap()
        let result = app.staticTexts["movie-pick-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let first = result.label
        capture(app, "Personalized recent movie result")
        reveal(app.buttons["movie-pick-another"], in: app)
        app.buttons["movie-pick-another"].tap()
        let changed = NSPredicate { _, _ in result.exists && result.label != first }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 8)
        capture(app, "Reroll without repeating the previous movie")
        let selectedTitle = result.label
        reveal(app.buttons["movie-pick-open"], in: app)
        app.buttons["movie-pick-open"].tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[selectedTitle].firstMatch.exists)
        capture(app, "Selected movie opens its standard detail screen")
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(app.buttons["movie-pick-another"].waitForExistence(timeout: 8))
        reveal(app.buttons["movie-pick-watch"], in: app)
        XCTAssertLessThan(app.buttons["movie-pick-watch"].frame.minY, app.buttons["movie-pick-open"].frame.minY)
        app.buttons["movie-pick-watch"].tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        capture(app, "Primary Watch opens the selected movie directly")
        app.buttons["Close player"].tap()
        XCTAssertTrue(app.buttons["movie-pick-open"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
    }
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if target.exists && target.isHittable { return }
            app.reviewScrollSurface.swipeUp()
        }
        XCTAssertTrue(target.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
