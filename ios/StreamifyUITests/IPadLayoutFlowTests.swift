import XCTest
import UIKit

final class IPadLayoutFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(); app.launchArguments = ["--ui-fixtures", "--ui-movie-pick"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("FAILURE iPad layout")
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate(); XCUIDevice.shared.orientation = .portrait
    }

    func testIPadProHomeAndSportsUseTheCanvasInBothOrientations() {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(wait { orientation == .portrait ? self.app.frame.height > self.app.frame.width : self.app.frame.width > self.app.frame.height })
            app.buttons["tab-home"].tap()
            XCTAssertTrue(element("hero-carousel").waitForExistence(timeout: 8))
            XCTAssertLessThan(element("hero-carousel").frame.height, 650)
            let bar = element("floating-navigation")
            if bar.exists { XCTAssertLessThanOrEqual(bar.frame.width, 550) }
            capture("iPad Pro Home \(orientation == .portrait ? "portrait" : "landscape")")
            app.buttons["tab-sports"].tap()
            let games = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sports-game-"))
            XCTAssertTrue(games.firstMatch.waitForExistence(timeout: 12))
            XCTAssertGreaterThanOrEqual(games.count, 2)
            let first = games.element(boundBy: 0), second = games.element(boundBy: 1)
            XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
            XCTAssertGreaterThan(first.frame.width, 400)
            XCTAssertLessThan(first.frame.width, app.frame.width * 0.7)
            capture("iPad Pro Sports \(orientation == .portrait ? "portrait" : "landscape")")
        }
    }

    func testIPadProMovieDetailRotatesWithoutLosingActions() {
        app.buttons["tab-library"].tap()
        let movie = app.buttons["media-link-movie:42"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 8)); movie.tap()
        let watch = app.buttons["detail-watch-movie:42"]
        XCTAssertTrue(watch.waitForExistence(timeout: 8))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(wait { orientation == .portrait ? self.app.frame.height > self.app.frame.width : self.app.frame.width > self.app.frame.height })
            let hero = element("trailer-preview")
            XCTAssertTrue(hero.exists); XCTAssertTrue(watch.isHittable)
            XCTAssertGreaterThan(watch.frame.minX, hero.frame.midX)
            XCTAssertLessThanOrEqual(watch.frame.maxX, app.frame.maxX)
            XCTAssertTrue(app.buttons["download-movie:42"].isHittable)
            capture("iPad Pro movie details \(orientation == .portrait ? "portrait" : "landscape")")
        }
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(movie.waitForExistence(timeout: 8))
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10) == .completed
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
