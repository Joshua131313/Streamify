import XCTest

/// Physical taps exercise the complete visible Watch surface, not accessibility
/// activation of its centered text. All catalogs and player HTML are local.
final class MediaWatchFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE media Watch flow")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE media Watch hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    func testMovieWatchRespondsAtBothVisibleEdgesWhileTrailerIsPresent() {
        openDetail("movie:42")
        let watch = app.buttons["detail-watch-movie:42"]
        reveal(watch)
        XCTAssertTrue(watch.isHittable)
        XCTAssertGreaterThan(watch.frame.width, 250)
        XCTAssertGreaterThanOrEqual(watch.frame.height, 50)
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "Media details must keep the header removed.")
        let trailer = element("trailer-preview")
        XCTAssertTrue(trailer.exists)
        XCTAssertLessThanOrEqual(trailer.frame.maxY, watch.frame.minY, "The preview must not extend over the action's hit region.")
        capture("Movie details full-width Watch target")

        watch.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        assertRealPlayer()
        capture("Movie Watch left padding opens the real player")
        closePlayer()
        XCTAssertTrue(app.buttons["close-media-details"].exists)

        let restored = app.buttons["detail-watch-movie:42"]
        reveal(restored)
        restored.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        assertRealPlayer()
        capture("Movie Watch right padding opens the real player again")
        closePlayer()
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
    }

    func testShowWatchOpensPlayerAndItsSeasonEpisodeSelectionStillWorks() {
        openDetail("tv:43")
        let watch = app.buttons["detail-watch-tv:43"]
        reveal(watch)
        watch.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        assertRealPlayer()
        XCTAssertTrue(app.staticTexts["Season 1 · Episode 1"].waitForExistence(timeout: 5))
        app.buttons["Episodes"].tap()
        XCTAssertTrue(app.navigationBars["Episodes"].waitForExistence(timeout: 5))
        // Details remain mounted below this sheet. These IDs belong only to
        // the player's visible sheet, never its covered detail-page controls.
        let season = app.buttons["player-episode-season-picker"]
        XCTAssertTrue(season.waitForExistence(timeout: 5))
        XCTAssertTrue(season.isHittable, "The Episodes sheet's visible season picker must receive the tap.")
        XCTAssertTrue(app.buttons["player-episode-choice-1-1"].waitForExistence(timeout: 8))
        capture("Player episode picker shows season 1 artwork and selected episode")
        season.tap()
        let secondSeason = app.buttons["Season 2"]
        XCTAssertTrue(secondSeason.waitForExistence(timeout: 5))
        XCTAssertTrue(secondSeason.isHittable)
        secondSeason.tap()
        let episode = app.buttons["player-episode-choice-2-3"]
        XCTAssertTrue(episode.waitForExistence(timeout: 8))
        XCTAssertTrue(episode.isHittable, "The selected season's visible episode row must receive the tap.")
        XCTAssertTrue(episode.label.contains("3. A New Horizon"))
        capture("Player episode picker shows season 2 before choosing an episode")
        episode.tap()
        XCTAssertTrue(app.navigationBars["Episodes"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Season 2 · Episode 3"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Close player"].isHittable)
        XCTAssertTrue(app.webViews.staticTexts["Streamify preview player"].waitForExistence(timeout: 8))
        capture("Show Watch retains the player after season and episode selection")
        closePlayer()
        XCTAssertTrue(app.buttons["detail-watch-tv:43"].exists)
        XCTAssertTrue(app.buttons["close-media-details"].isHittable)
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
    }

    func testShowDetailSeasonRowOpensTheExactSelectedEpisode() {
        openDetail("tv:43")
        let selector = app.buttons["detail-season-picker-tv:43"]
        reveal(selector)
        selector.tap()
        XCTAssertTrue(app.buttons["Season 2"].waitForExistence(timeout: 5))
        app.buttons["Season 2"].tap()
        let row = app.buttons["detail-play-tv:43:2:2"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        reveal(row)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        assertRealPlayer()
        XCTAssertTrue(app.staticTexts["Season 2 · Episode 2"].waitForExistence(timeout: 5))
        capture("Detail episode row opens season 2 episode 2")
        closePlayer()
        XCTAssertTrue(app.buttons["detail-season-picker-tv:43"].exists)
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-library"].isSelected)
    }

    private func openDetail(_ key: String) {
        app.buttons["tab-library"].tap()
        let card = app.buttons.matching(identifier: "media-link-\(key)").firstMatch
        reveal(card)
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["detail-watch-\(key)"].waitForExistence(timeout: 8))
    }

    private func assertRealPlayer() {
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8), "A physical Watch tap must present MediaPlayerView.")
        XCTAssertTrue(app.buttons["Reload player"].exists)
        XCTAssertTrue(app.webViews.staticTexts["Streamify preview player"].waitForExistence(timeout: 8), "The player must load its provider document, not just set a navigation flag.")
    }

    private func closePlayer() {
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !self.app.buttons["Close player"].exists })
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 5))
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<12 {
            if target.exists && target.isHittable && target.frame.minY > app.frame.minY + 90 && target.frame.maxY < app.frame.maxY - 95 { return }
            let up = !(target.exists && target.frame.minY < app.frame.midY)
            let start = app.reviewScrollSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.78 : 0.28))
            let end = app.reviewScrollSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.exists && target.isHittable, "Expected control must be reachable.")
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
