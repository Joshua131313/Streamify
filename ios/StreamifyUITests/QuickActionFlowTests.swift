import XCTest

/// Launch arguments test queued cold routing. The warm flow selects the real
/// SpringBoard quick action; physical iPhone menu behavior is checked separately.
final class QuickActionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "FAILURE quick action routing"; image.lifetime = .keepAlways; add(image)
            if let app {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "FAILURE quick action hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
        }
        app?.terminate()
    }

    func testQueuedColdActionsOpenDownloadsFavoritesAndSports() {
        for destination in ["downloads", "favorites", "sports"] {
            app?.terminate()
            app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "--ui-quick-action", destination]
            app.launch()
            if destination == "downloads" {
                XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].waitForExistence(timeout: 8))
                capture("Queued My Downloads opens the preserved offline collection")
                app.navigationBars["Downloads"].buttons["Close"].tap()
                XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 8))
                XCTAssertTrue(app.buttons["tab-library"].isSelected)
            } else if destination == "favorites" {
                let saved = app.buttons["Saved · 3"]
                XCTAssertTrue(saved.waitForExistence(timeout: 15))
                XCTAssertTrue(saved.isSelected)
                XCTAssertTrue(app.buttons["tab-library"].isSelected)
                capture("Queued My Favorites opens saved titles")
            } else {
                XCTAssertTrue(app.buttons["sports-league-picker"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["tab-sports"].isSelected)
                capture("Queued Sports opens the schedule")
            }
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            if destination == "downloads" {
                XCTAssertFalse(app.navigationBars["Downloads"].exists, "A consumed launch shortcut must not reopen after foregrounding.")
                XCTAssertTrue(app.buttons["tab-library"].isSelected)
            }
        }
    }

    func testActualWarmHomeScreenFavoritesActionLeavesHistoryAndPreservesSavedTitles() {
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 15))
        app.buttons["tab-library"].tap()
        let history = app.buttons["History · 2"]
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        history.tap()
        XCTAssertTrue(history.isSelected)
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = home.icons["Streamify"].firstMatch
        for _ in 0..<4 {
            if icon.exists && icon.isHittable { break }
            home.swipeLeft()
        }
        if !icon.exists || !icon.isHittable {
            for _ in 0..<4 {
                if icon.exists && icon.isHittable { break }
                home.swipeRight()
            }
        }
        XCTAssertTrue(icon.waitForExistence(timeout: 8))
        XCTAssertTrue(icon.isHittable)
        icon.press(forDuration: 1.1)
        let favoriteAction = home.buttons["My Favorites"].firstMatch
        XCTAssertTrue(favoriteAction.waitForExistence(timeout: 8), "The installed static action must appear in the actual Home Screen menu.")
        XCTAssertTrue(home.buttons["My Downloads"].exists)
        XCTAssertTrue(home.buttons["Sports"].exists)
        capture("Native Home Screen menu contains all three Streamify quick actions")
        favoriteAction.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        let saved = app.buttons["Saved · 3"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.isSelected)
        XCTAssertFalse(app.buttons["History · 2"].isSelected)
        XCTAssertTrue(app.buttons["tab-library"].isSelected)
        capture("Actual warm My Favorites quick action returns to saved titles")
    }

    func testWidgetSportsAndWatchURLsRouteWarmAndColdWithoutReplayingClosedPlayer() throws {
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["open-catalog-search"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["open-catalog-search"].firstMatch.tap()
        XCTAssertTrue(app.textFields["browse-search"].waitForExistence(timeout: 8))
        app.open(try XCTUnwrap(URL(string: "streamify://sports")))
        XCTAssertTrue(app.buttons["sports-league-picker"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        XCTAssertFalse(app.textFields["browse-search"].exists)
        capture("Widget Sports link dismisses an existing search and opens the schedule")

        app.buttons["focus-sports-search"].tap()
        XCTAssertTrue(app.textFields["sports-dialog-search"].waitForExistence(timeout: 8))
        app.buttons["close-sports-search"].tap()
        XCTAssertTrue(app.buttons["sports-league-picker"].waitForExistence(timeout: 8))
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        app.open(try XCTUnwrap(URL(string: "streamify://sports")))
        XCTAssertTrue(app.buttons["sports-league-picker"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["sports-league-picker"].isHittable)
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        let replayedSearch = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.textFields["sports-dialog-search"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [replayedSearch], timeout: 2), .timedOut,
            "A widget route must not replay an earlier, cancelled sports search request after rebuilding navigation.")
        capture("Widget Sports link does not replay a previously cancelled sports search")

        let watchURL = try XCTUnwrap(URL(string: "streamify://sports/watch?league=nba&event=401020304"))
        app.open(watchURL)
        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 15), "A widget Watch link must fetch its ESPN identity and a real fixture source before opening playback.")
        XCTAssertTrue((source.value as? String ?? "").contains("BOS vs TOR"))
        XCTAssertTrue(app.webViews.staticTexts["Streamify preview player"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts["Stream unavailable"].exists)
        capture("Warm widget Watch resolves the requested game and opens its source")
        app.buttons["sports-player-close"].tap()
        XCTAssertTrue(app.buttons["sports-league-picker"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertFalse(source.exists, "Returning to the app must not replay a consumed widget Watch action.")

        app.terminate()
        app.open(watchURL)
        XCTAssertTrue(source.waitForExistence(timeout: 20), "Cold widget Watch must be queued until the SwiftUI scene is ready.")
        XCTAssertTrue((source.value as? String ?? "").contains("BOS vs TOR"))
        XCTAssertTrue(app.webViews.staticTexts["Streamify preview player"].waitForExistence(timeout: 10))
        capture("Cold widget Watch opens the requested game after scene connection")
        app.buttons["sports-player-close"].tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
