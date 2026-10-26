import XCTest

final class AccountCacheFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE account cache")
            let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; add(tree)
        }
        app?.terminate()
    }
    func testExplicitGoogleAndEmailSignInOpenHomeWithAccountViewerWithoutChooser() {
        for google in [true, false] {
            launch(["--ui-account-success"])
            openAccount()
            if google {
                let button = app.buttons["account-google-sign-in"]
                reveal(button); button.tap()
            } else {
                let email = app.textFields["account-email"]; reveal(email); email.tap()
                for character in "review@example.invalid" { email.typeText(String(character)) }
                email.typeText("\n")
                let password = app.secureTextFields["account-password"]; reveal(password); password.tap(); password.typeText("local-password")
                let submit = app.buttons["account-submit"]; reveal(submit); submit.tap()
            }
            XCTAssertTrue(wait { self.app.buttons["tab-home"].isHittable && self.app.buttons["tab-home"].isSelected && (self.app.buttons["tab-library"].value as? String ?? "").contains("Account viewer") })
            XCTAssertFalse(app.buttons["account-submit"].exists)
            XCTAssertFalse(app.buttons["profile-manage"].isHittable)
            capture(google ? "Google local success opens account Home" : "Email local success opens account Home")
            app.terminate()
        }
    }
    func testGoogleCancelKeepsGuestAndFavoriteGenresHaveUniformTilesAndPersist() {
        launch(["--ui-account-success", "--ui-google-cancel"])
        openAccount()
        let google = app.buttons["account-google-sign-in"]; reveal(google); google.tap()
        XCTAssertTrue(google.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        XCTAssertFalse(app.staticTexts["account-auth-error"].exists)
        XCTAssertFalse(app.buttons["account-sign-out"].exists)
        app.swipeDown()
        let genres = app.buttons["Your favorite genres"]; reveal(genres); genres.tap()
        let action = app.buttons["favorite-genre-28"], adventure = app.buttons["favorite-genre-12"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.frame.width, adventure.frame.width, accuracy: 1)
        XCTAssertEqual(action.frame.height, adventure.frame.height, accuracy: 1)
        XCTAssertEqual(action.frame.minY, adventure.frame.minY, accuracy: 1)
        XCTAssertLessThan(action.frame.minX, adventure.frame.minX)
        action.tap(); XCTAssertTrue(action.isSelected)
        capture("Favorite genres uniform left aligned tiles")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let again = app.buttons["Your favorite genres"]; reveal(again); again.tap()
        XCTAssertTrue(app.buttons["favorite-genre-28"].isSelected)
    }
    func testLeagueRoundTripsReuseNetworkResultsAndNeverEnterLoadingAgain() {
        launch(["--ui-cache-review"])
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["sports-game-nfl:nfl-fixture"].waitForExistence(timeout: 10))
        let original = metric("requests"), loading = metric("loading")
        XCTAssertGreaterThan(original, 0)
        for league in ["nba", "nfl", "nfl", "college-football", "nba", "nfl"] {
            let button = app.buttons["sports-league-option-\(league)"]
            XCTAssertTrue(button.isHittable); button.tap()
            XCTAssertTrue(app.buttons["sports-game-\(league):\(league)-fixture"].waitForExistence(timeout: 3))
            XCTAssertFalse(element("sports-empty-state").exists)
            XCTAssertFalse(element("sports-schedule-loading").exists)
            XCTAssertEqual(metric("requests"), original, "Recent league changes must not refetch scoreboards.")
            XCTAssertEqual(metric("loading"), loading, "A warm league switch must never clear its cards or flash loading.")
        }
        capture("League round trips keep warm games and network count")
    }
    func testContinueWatchingRepairsMissingMetadataAndRetriesFailedBackdrop() {
        launch(["--ui-cache-review", "--ui-artwork-repair"])
        for _ in 0..<4 {
            if metric("failedImages") > 0 && metric("metadata") > 0 { break }
            app.swipeUp()
        }
        XCTAssertTrue(wait { self.metric("failedImages") > 0 && self.metric("metadata") > 0 && self.metric("fallback") > 0 })
        capture("Continue Watching poster fallback and metadata repair")
        app.buttons["tab-library"].tap()
        app.buttons["History · 2"].tap()
        XCTAssertTrue(app.buttons["history-resume-tv:43"].waitForExistence(timeout: 5))
        XCTAssertEqual(element("history-progress-tv:43").value as? String, "11 percent")
        XCTAssertTrue(app.staticTexts["history-status-tv:43"].label.contains("40 min left"))
        capture("History preserves titles and playback after artwork repair")
    }
    private func launch(_ extra: [String]) {
        app = XCUIApplication(); app.launchArguments = ["--ui-fixtures"] + extra; app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
        let pause = app.buttons["hero-carousel-pause"]
        if pause.waitForExistence(timeout: 5), pause.label == "Pause carousel" { pause.tap() }
    }
    private func openAccount() {
        app.buttons["tab-library"].tap(); app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5)); app.buttons["Account"].tap()
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func metric(_ key: String) -> Int {
        let report = app.staticTexts["fixture-network-report"].label
        return report.split(separator: ";").first { $0.hasPrefix("\(key)=") }.flatMap { Int($0.split(separator: "=").last ?? "") } ?? -1
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10) == .completed
    }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<12 {
            if target.exists && target.isHittable { return }
            let origin = app.coordinate(withNormalizedOffset: .zero), frame = app.frame
            let keyboard = app.keyboards.firstMatch
            // Autofill's 44pt accessory is outside XCUI's Keyboard frame.
            let bottom = keyboard.exists ? keyboard.frame.minY - 80 : frame.height * 0.82
            let top = frame.height * 0.22
            let up = !(target.exists && target.frame.maxY < (top + bottom) / 2)
            origin.withOffset(CGVector(dx: frame.width * 0.88, dy: up ? bottom : top)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: frame.width * 0.88, dy: up ? top : bottom)))
        }
        XCTAssertTrue(target.isHittable)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
