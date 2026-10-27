import XCTest

/// Exercises real card holds and their existing actions using only local fixtures.
final class CardInteractionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let downloadID = "00000000-0000-0000-0000-000000000042"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-stable-offline-controls"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE card interaction")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE card interaction hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    func testPosterHoldCancelsWithoutChangingSavedTitleThenSameArtworkOpensExactDetails() {
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["Saved · 3"].waitForExistence(timeout: 5))
        // My list has one copy of this media; hold its artwork, never a label or
        // the overflow control belonging to a different card.
        let poster = element("poster-artwork-movie:42")
        reveal(poster)
        let sourceFrame = poster.frame
        let artworkPoint = poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        artworkPoint.press(forDuration: 1.2)

        let remove = app.buttons["Remove from My list"]
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Share")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(remove.isHittable)
        XCTAssertTrue(share.isHittable, "The poster hold must expose its native context actions.")
        XCTAssertFalse(app.buttons["close-media-details"].exists, "Holding a poster must not also activate its normal tap.")
        capture("Held movie poster native context menu")

        // The system dismissal surface consumes this tap without invoking an
        // action or the source artwork underneath its lifted preview.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.1)).tap()
        XCTAssertTrue(wait { !remove.exists && !share.exists })
        XCTAssertTrue(app.buttons["tab-library"].isSelected)
        XCTAssertTrue(app.buttons["Saved · 3"].exists, "Cancelling the hold must preserve the exact saved list.")
        XCTAssertFalse(app.buttons["close-media-details"].exists)
        XCTAssertTrue(poster.isHittable)
        XCTAssertEqual(poster.frame.minY, sourceFrame.minY, accuracy: 2)

        artworkPoint.tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["download-movie:42"].waitForExistence(timeout: 8), "The same poster must still open movie:42 after its hold is cancelled.")
        XCTAssertTrue(app.staticTexts["The Last Horizon"].firstMatch.exists)
        capture("Same held poster opens its exact movie details")
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(wait { poster.exists && poster.isHittable })
        XCTAssertTrue(app.buttons["Saved · 3"].exists)
    }

    func testCompletedDownloadHoldPlaysItsActualLocalFileAndReturnsToSameCard() {
        app.buttons["open-downloads"].tap()
        let card = element("download-card-\(downloadID)")
        let playFile = app.buttons["download-play-\(downloadID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        reveal(playFile)
        // Hold the thumbnail area of the completed file's existing play button.
        // The card context menu must receive this without launching playback.
        playFile.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 1.2)
        let playAction = menuButton("Play offline")
        XCTAssertTrue(playAction.waitForExistence(timeout: 5))
        XCTAssertTrue(playAction.isHittable)
        XCTAssertTrue(app.buttons["Delete"].isHittable)
        XCTAssertFalse(element("offline-player").exists, "A held touch must open actions without presenting the player, including when its controls would be hidden.")
        XCTAssertFalse(app.buttons["offline-play-pause"].exists)
        capture("Held completed download native context menu")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertTrue(wait { !self.menuButton("Play offline").exists })
        XCTAssertTrue(app.buttons["download-play-\(downloadID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["download-play-\(downloadID)"].isHittable)
        XCTAssertFalse(app.buttons["offline-play-pause"].exists, "Canceling the hold must preserve the file without launching its primary tap.")
        XCTAssertFalse(element("offline-player").exists)
        XCTAssertTrue(card.exists)
        XCTAssertEqual(card.value as? String, "Artwork saved offline")
        playFile.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 1.2)
        let reopenedPlayAction = menuButton("Play offline")
        XCTAssertTrue(reopenedPlayAction.waitForExistence(timeout: 5))
        XCTAssertTrue(reopenedPlayAction.isHittable)
        XCTAssertTrue(app.buttons["Delete"].isHittable)
        XCTAssertFalse(element("offline-player").exists)
        XCTAssertFalse(app.buttons["offline-play-pause"].exists)
        capture("Same completed download holds again after menu cancellation")

        reopenedPlayAction.tap()
        let play = app.buttons["offline-play-pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" }, "The menu must start the actual bundled H264 file through the existing offline player.")
        revealOfflineControls(play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        XCTAssertTrue(wait { (self.app.sliders["offline-progress"].value as? String ?? "").contains(" of 10:00") }, "Playback must report the real fixture's ten-minute duration.")
        XCTAssertFalse(element("offline-video-error").exists)
        capture("Download context action starts real local playback")
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(card.exists)
        XCTAssertTrue(playFile.isHittable, "Playing from the hold menu must preserve the same completed download.")
        XCTAssertFalse(app.buttons["Delete video"].exists)

        // The same control must retain immediate playback on a normal tap after
        // both cancelling its menu and playing through a menu action.
        playFile.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" })
        XCTAssertFalse(menuButton("Play offline").exists, "A normal tap must play the file instead of opening its actions.")
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(card.exists)
    }

    func testSportsTeamHoldsKeepIndependentFollowActionsAndTapOpensExactTeam() {
        app.buttons["tab-sports"].tap()
        let nba = app.buttons["sports-league-option-nba"]
        XCTAssertTrue(nba.waitForExistence(timeout: 8))
        nba.tap()
        let away = app.buttons["sports-card-team-nba:nba-fixture-100"]
        let home = app.buttons["sports-card-team-nba:nba-fixture-200"]
        XCTAssertTrue(away.waitForExistence(timeout: 8))
        XCTAssertTrue(home.exists)
        XCTAssertFalse(app.staticTexts["NBA League Pass"].exists, "NBA cards keep the watch actions clear of broadcast branding.")
        XCTAssertGreaterThanOrEqual(away.frame.height, 44)
        XCTAssertGreaterThanOrEqual(home.frame.height, 44)
        let homeFrame = home.frame

        away.press(forDuration: 1.2)
        let followAway = app.buttons["Follow Boston Harbor"]
        XCTAssertTrue(followAway.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Follow Toronto Towers"].exists, "The held team owns its actions.")
        XCTAssertFalse(app.buttons["sports-team-roster-tab"].exists, "Holding must not also open a team page.")
        capture("Only the held away team lifts into its own rounded preview")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.1)).tap()
        XCTAssertTrue(wait { !followAway.exists && away.isHittable && home.isHittable })
        XCTAssertEqual(home.frame.minY, homeFrame.minY, accuracy: 2)
        XCTAssertEqual(home.value as? String, "Not followed")
        XCTAssertFalse(app.buttons["sports-team-roster-tab"].exists)

        home.press(forDuration: 1.2)
        let followHome = app.buttons["Follow Toronto Towers"]
        XCTAssertTrue(followHome.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Follow Boston Harbor"].exists)
        XCTAssertFalse(app.buttons["sports-team-roster-tab"].exists)
        capture("Home team hold exposes only home team follow and view actions")
        followHome.tap()
        XCTAssertTrue(wait { home.value as? String == "Following" })
        XCTAssertEqual(away.value as? String, "Not followed", "Following the home team must not follow its opponent.")

        away.tap()
        XCTAssertTrue(app.navigationBars["Game center"].waitForExistence(timeout: 8),
            "A normal team/card tap opens the matchup's Game Center.")
        XCTAssertTrue(element("sports-game-scoreboard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sports-team-100"].exists)
        XCTAssertTrue(app.buttons["sports-team-200"].exists)
        XCTAssertFalse(app.buttons["sports-team-roster-tab"].exists,
            "A normal card tap must not accidentally open the held-team destination.")
        capture("Normal team-card tap opens the exact matchup Game Center")
        app.navigationBars["Game center"].buttons["Close"].tap()
        XCTAssertTrue(wait { away.isHittable && home.isHittable && !self.app.navigationBars["Game center"].exists })
        away.press(forDuration: 1.2)
        let viewAway = menuButton("View team")
        XCTAssertTrue(viewAway.waitForExistence(timeout: 5))
        XCTAssertEqual(viewAway.label, "View team")
        XCTAssertTrue(viewAway.wait(for: \.isHittable, toEqual: true, timeout: 5))
        // The native menu's AX activation point can lag its lifted preview.
        // Use the current visible row center for one physical tap; the strict
        // dismissal and exact-team assertions below still verify the action.
        viewAway.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(viewAway.waitForNonExistence(timeout: 5), "View team must actually activate and dismiss its native menu.")
        XCTAssertFalse(app.navigationBars["Game center"].exists, "The held-team action must not trigger the card's primary navigation.")
        XCTAssertTrue(app.navigationBars["NBA · Team"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sports-team-roster-tab"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Boston Harbor"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Follow team"].exists)
        capture("The held away team's View team action opens only Boston Harbor")
        app.navigationBars["NBA · Team"].buttons["Close"].tap()
        XCTAssertTrue(wait { home.isHittable && !self.app.buttons["sports-team-roster-tab"].exists })
        app.buttons["sports-followed-teams"].tap()
        XCTAssertTrue(app.buttons["sports-followed-teams"].isSelected)
        XCTAssertTrue(home.waitForExistence(timeout: 8), "The newly followed team's game belongs in Followed teams.")
        home.press(forDuration: 1.2)
        let unfollow = app.buttons["Unfollow Toronto Towers"]
        XCTAssertTrue(unfollow.waitForExistence(timeout: 5))
        unfollow.tap()
        XCTAssertTrue(app.staticTexts["No followed teams playing"].waitForExistence(timeout: 8))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func menuButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<15 {
            if target.exists && target.isHittable { return }
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.78 : 0.28))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable, "The exact source card must be reachable.")
    }

    private func revealOfflineControls(_ target: XCUIElement) {
        for _ in 0..<3 {
            if target.exists && target.isHittable { return }
            let canvas = app.otherElements["Offline video"].firstMatch
            XCTAssertTrue(canvas.waitForExistence(timeout: 5))
            canvas.tap()
            if wait({ target.exists && target.isHittable }) { return }
        }
        XCTFail("The actual video canvas must reveal its playback control before pausing.")
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
