import XCTest
import UIKit

final class MoviePickFlowTests: XCTestCase {
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { capture(XCUIApplication(), "FAILURE cinematic picker") }
    }
    func testGenreChoiceRerollAndOpenExactDetails() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-movie-pick", "--ui-cinematic-pick"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
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
        let isTablet = app.frame.width >= 700
        if isTablet { assertCompactTabletResult(app) }
        let viewport = app.descendants(matching: .any).matching(identifier: "movie-pick-viewport").firstMatch
        let initialBounds = viewport.frame
        let watchBounds = app.buttons["movie-pick-watch"].frame
        let titleHeight = result.frame.height
        let synopsis = app.staticTexts["movie-pick-synopsis"]
        let synopsisHeight = synopsis.frame.height
        XCTAssertTrue(app.buttons["movie-pick-watch"].isHittable)
        app.buttons["movie-pick-save"].tap()
        XCTAssertEqual(app.buttons["movie-pick-save"].label, "Saved for later")
        capture(app, "Personalized recent movie result")
        reveal(app.buttons["movie-pick-another"], in: app)
        app.buttons["movie-pick-another"].tap()
        XCTAssertTrue(app.staticTexts["Finding your movie…"].waitForExistence(timeout: 1))
        XCTAssertEqual(result.label, first, "Keep the old pick visible during loading")
        XCTAssertEqual(viewport.frame.height, initialBounds.height, accuracy: 1)
        XCTAssertEqual(app.buttons["movie-pick-watch"].frame.minY, watchBounds.minY, accuracy: 1)
        let changed = NSPredicate { _, _ in result.exists && result.label != first }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 8)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(viewport.frame.height, initialBounds.height, accuracy: 1)
        XCTAssertEqual(app.buttons["movie-pick-watch"].frame.minY, watchBounds.minY, accuracy: 1)
        XCTAssertEqual(result.frame.height, titleHeight, accuracy: 1)
        XCTAssertEqual(synopsis.frame.height, synopsisHeight, accuracy: 1)
        capture(app, "Reroll without repeating the previous movie")
        if isTablet {
            for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
                XCUIDevice.shared.orientation = orientation
                XCTAssertTrue(wait {
                    orientation == .portrait ? app.frame.height > app.frame.width : app.frame.width > app.frame.height
                })
                assertCompactTabletResult(app)
                capture(app, "iPad Pick for me long title and synopsis \(orientation == .portrait ? "portrait" : "landscape")")
            }
        }
        let selectedTitle = result.label
        reveal(app.buttons["movie-pick-open"], in: app)
        app.buttons["movie-pick-open"].tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[selectedTitle].firstMatch.exists)
        capture(app, "Selected movie opens its standard detail screen")
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(app.buttons["movie-pick-another"].waitForExistence(timeout: 8))
        app.buttons["movie-pick-watch"].tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[selectedTitle].firstMatch.exists)
        capture(app, "Pick for me primary Watch opens the selected movie")
        app.buttons["Close player"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertEqual(result.label, selectedTitle)
        app.buttons["movie-pick-change"].tap()
        XCTAssertTrue(app.buttons["movie-pick-genre-18"].waitForExistence(timeout: 8))
        XCTAssertFalse(result.exists)
        XCTAssertTrue(app.buttons["movie-pick-draw"].isHittable)
        capture(app, "Change genre returns to the chooser with its action visible")
        app.buttons["Done"].tap()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
    }
    private func assertCompactTabletResult(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let viewport = app.descendants(matching: .any).matching(identifier: "movie-pick-viewport").firstMatch
        let title = app.staticTexts["movie-pick-result"]
        let synopsis = app.staticTexts["movie-pick-synopsis"]
        let watch = app.buttons["movie-pick-watch"]
        XCTAssertTrue(wait { watch.isHittable && synopsis.exists }, file: file, line: line)
        XCTAssertTrue(viewport.frame.contains(title.frame), file: file, line: line)
        XCTAssertTrue(viewport.frame.contains(synopsis.frame), file: file, line: line)
        XCTAssertTrue(viewport.frame.contains(watch.frame), file: file, line: line)
        XCTAssertGreaterThanOrEqual(watch.frame.minY, synopsis.frame.maxY, file: file, line: line)
        XCTAssertLessThanOrEqual(watch.frame.minY - synopsis.frame.maxY, 100,
            "The Watch action should sit with the recommendation, not at the far end of an empty page.", file: file, line: line)
        for id in ["movie-pick-save", "movie-pick-another", "movie-pick-open", "movie-pick-change"] {
            let action = app.buttons[id]
            XCTAssertTrue(action.isHittable, "\(id) must remain visible without scrolling the tablet sheet.", file: file, line: line)
            XCTAssertTrue(viewport.frame.contains(action.frame), file: file, line: line)
        }
        XCTAssertGreaterThan(app.buttons["movie-pick-open"].frame.minY, watch.frame.maxY,
            "View movie remains secondary beneath Watch.", file: file, line: line)
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
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
