import XCTest

/// Exercises real WebKit play/pause and the same passive downward pan as Sports.
/// Every provider document uses the bundled H264 fixture, with autoplay removed
/// from HTML so the production Watch-start script must actually start the video.
final class MediaAutoplayDismissFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        if !name.contains("testDownwardPull") {
            app.launchArguments += ["--ui-provider-controls-fullscreen-fixture", "--ui-sports-autoplay-fixture"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE media autoplay and dismissal")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE media autoplay hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testMovieWatchAutoplaysOnceAndDoesNotUndoPause() {
        openPlayer("movie:42")
        XCTAssertTrue(app.webViews.staticTexts["Video playing"].waitForExistence(timeout: 12))
        let document = playbackDocument.label
        app.webViews.buttons["Pause fixture video"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Video paused"].waitForExistence(timeout: 5))
        assertStaysPaused()
        XCTAssertEqual(playbackDocument.label, document)
        capture("Movie Watch starts video once and preserves explicit Pause")
        app.buttons["Close player"].tap()
        XCTAssertTrue(app.buttons["detail-watch-movie:42"].wait(for: \.isHittable, toEqual: true, timeout: 8))
    }

    func testShowEpisodeChoiceAutoplaysOnlyTheNewEpisodeAndKeepsSelection() {
        openPlayer("tv:43")
        XCTAssertTrue(app.webViews.staticTexts["Video playing"].waitForExistence(timeout: 12))
        let oldDocument = playbackDocument.label
        app.webViews.buttons["Pause fixture video"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Video paused"].waitForExistence(timeout: 5))
        app.buttons["Episodes"].tap()
        let picker = app.buttons["player-episode-season-picker"]
        XCTAssertTrue(picker.wait(for: \.isHittable, toEqual: true, timeout: 8)); picker.tap()
        let season = app.buttons["Season 2"]
        XCTAssertTrue(season.wait(for: \.isHittable, toEqual: true, timeout: 5)); season.tap()
        let episode = app.buttons["player-episode-choice-2-3"]
        XCTAssertTrue(episode.wait(for: \.isHittable, toEqual: true, timeout: 8)); episode.tap()
        XCTAssertTrue(app.staticTexts["Season 2 · Episode 3"].waitForExistence(timeout: 8))
        XCTAssertTrue(wait { self.playbackDocument.exists && self.playbackDocument.label != oldDocument })
        XCTAssertTrue(app.webViews.staticTexts["Video playing"].waitForExistence(timeout: 12))
        app.webViews.buttons["Pause fixture video"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Video paused"].waitForExistence(timeout: 5))
        assertStaysPaused()
        XCTAssertTrue(app.staticTexts["Season 2 · Episode 3"].exists)
        capture("Chosen show episode starts once without losing season and episode")
    }

    func testDownwardPullCancelsWithoutReloadingThenReturnsToTheWatchCard() {
        openPlayer("movie:42")
        XCTAssertTrue(app.webViews.staticTexts["Streamify preview player"].waitForExistence(timeout: 8))
        let document = playbackDocument.label
        let close = app.buttons["Close player"]
        let frame = close.frame
        // Horizontal drags no longer dismiss movie/show playback.
        drag(from: CGVector(dx: 0.78, dy: 0.32), to: CGVector(dx: 0.22, dy: 0.32))
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(playbackDocument.label, document)
        drag(from: CGVector(dx: 0.5, dy: 0.32), to: CGVector(dx: 0.5, dy: 0.39))
        XCTAssertTrue(wait { close.isHittable && abs(close.frame.minY - frame.minY) < 2 && abs(close.frame.minX - frame.minX) < 2 })
        XCTAssertEqual(playbackDocument.label, document, "A cancelled pull must retain the live provider document")
        capture("Cancelled media pull springs the same player back")
        drag(from: CGVector(dx: 0.5, dy: 0.32), to: CGVector(dx: 0.5, dy: 0.76))
        XCTAssertTrue(wait { !close.exists }, "A committed downward drag must close playback")
        let watch = app.buttons["detail-watch-movie:42"]
        XCTAssertTrue(watch.wait(for: \.isHittable, toEqual: true, timeout: 8))
        XCTAssertTrue(app.buttons["close-media-details"].isHittable)
        XCTAssertFalse(playbackDocument.exists, "A dismissed player must release its provider document")
        capture("Media player returns to its original visible Watch card")
    }

    private var playbackDocument: XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).firstMatch
    }

    private func openPlayer(_ key: String) {
        app.buttons["tab-library"].tap()
        let card = app.buttons.matching(identifier: "media-link-\(key)").firstMatch
        reveal(card); card.tap()
        let watch = app.buttons["detail-watch-\(key)"]
        XCTAssertTrue(watch.waitForExistence(timeout: 8)); reveal(watch); watch.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 8))
        XCTAssertTrue(playbackDocument.waitForExistence(timeout: 8))
    }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<12 {
            if target.exists && target.isHittable && target.frame.minY > app.frame.minY + 90 && target.frame.maxY < app.frame.maxY - 95 { return }
            let up = !(target.exists && target.frame.minY < app.frame.midY)
            drag(from: CGVector(dx: 0.985, dy: up ? 0.78 : 0.28), to: CGVector(dx: 0.985, dy: up ? 0.28 : 0.78))
        }
        XCTAssertTrue(target.exists && target.isHittable)
    }
    private func drag(from: CGVector, to: CGVector) {
        app.coordinate(withNormalizedOffset: from).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: to), withVelocity: .slow, thenHoldForDuration: 0.3)
    }
    private func assertStaysPaused() {
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.webViews.staticTexts["Video playing"].exists }, object: nil)
        restarted.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 3.2), .completed)
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
