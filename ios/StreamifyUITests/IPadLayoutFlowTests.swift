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
        let pause = app.buttons["hero-carousel-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8))
        if pause.label == "Pause carousel" { pause.tap() }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(wait { orientation == .portrait ? self.app.frame.height > self.app.frame.width : self.app.frame.width > self.app.frame.height })
            app.buttons["tab-home"].tap()
            XCTAssertTrue(element("hero-carousel").waitForExistence(timeout: 8))
            XCTAssertLessThan(element("hero-carousel").frame.height, 650)
            let artwork = app.buttons["media-link-movie:42"].firstMatch
            XCTAssertTrue(artwork.waitForExistence(timeout: 8))
            XCTAssertGreaterThanOrEqual(artwork.frame.width, app.frame.width - 40,
                "The actual featured artwork must fill the tablet width with only the standard side insets.")
            XCTAssertGreaterThanOrEqual(artwork.frame.minX, app.frame.minX + 12)
            XCTAssertLessThanOrEqual(artwork.frame.maxX, app.frame.maxX - 12)
            let watch = app.buttons["Watch The Last Horizon"].firstMatch
            XCTAssertTrue(watch.isHittable)
            XCTAssertLessThan(watch.frame.width, 300,
                "The banner artwork should grow without stretching its actions across the entire iPad.")
            let bar = element("floating-navigation")
            if bar.exists {
                XCTAssertLessThanOrEqual(bar.frame.width, 550)
                XCTAssertGreaterThanOrEqual(bar.frame.height, 54, "The floating tablet bar must retain stacked, readable icon/caption slots.")
            }
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
        capture("iPad Pro library remains selected after returning in landscape")
    }

    func testIPadProSearchLibraryAndDownloadsInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 8))
        capture("iPad Pro landscape browse grid and filters")
        app.buttons["open-catalog-search-dialog"].tap()
        let input = app.textFields["browse-search"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        let tip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed up your typing")).firstMatch
        if tip.waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        XCTAssertTrue(input.isHittable)
        input.typeText("Midnight\n")
        XCTAssertTrue(app.buttons["media-link-tv:43"].firstMatch.waitForExistence(timeout: 10))
        capture("iPad Pro landscape dedicated search results")
        app.buttons["cancel-catalog-search"].tap()
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["media-link-movie:42"].firstMatch.waitForExistence(timeout: 8))
        capture("iPad Pro landscape saved titles")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "History")).firstMatch.tap()
        XCTAssertTrue(app.buttons["history-resume-tv:43"].waitForExistence(timeout: 8))
        capture("iPad Pro landscape history rows")
        app.buttons["open-downloads"].tap()
        XCTAssertTrue(app.buttons["Add link"].waitForExistence(timeout: 8))
        capture("iPad Pro landscape downloads page")
        app.buttons["Add link"].tap()
        XCTAssertTrue(app.navigationBars["Add video"].waitForExistence(timeout: 5))
        capture("iPad Pro landscape add video form")
        app.navigationBars["Add video"].buttons["Cancel"].tap()
        app.navigationBars["Downloads"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["tab-library"].isSelected)
    }

    func testIPadProSettingsAccountAndGenresInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        capture("iPad Pro landscape settings page")
        let save = app.buttons["save-settings"]; reveal(save)
        XCTAssertTrue(save.isHittable)
        capture("iPad Pro landscape settings save and about")
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["More options"].tap(); app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["account-profile-name"].waitForExistence(timeout: 8))
        capture("iPad Pro landscape account")
        let genres = app.buttons["Your favorite genres"]; reveal(genres); genres.tap()
        XCTAssertTrue(app.buttons["favorite-genre-28"].waitForExistence(timeout: 8))
        capture("iPad Pro landscape favorite genre tiles")
        app.navigationBars["Favorite genres"].buttons.firstMatch.tap()
        let email = app.textFields["account-email"]; reveal(email); email.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(email.isHittable)
        capture("iPad Pro landscape account with keyboard")
        app.navigationBars["Account"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 8))
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<14 {
            if target.exists && target.isHittable { return }
            let surface = app.reviewScrollSurface
            let up = !(target.exists && target.frame.maxY < surface.frame.midY)
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: up ? 0.8 : 0.25))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: up ? 0.25 : 0.8))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable)
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10) == .completed
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
