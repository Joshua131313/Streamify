import XCTest

/// Uses a synthetic 10-minute H264 local file: no download server or remote video.
final class OfflinePlayerFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let fixtureID = "00000000-0000-0000-0000-000000000042"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE offline player")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE offline hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    func testCachedPosterAndActualLocalPlaybackControls() {
        XCTAssertTrue(app.buttons["open-downloads"].waitForExistence(timeout: 15))
        app.buttons["open-downloads"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "download-card-\(fixtureID)").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(wait { (card.value as? String) == "Artwork saved offline" })
        capture("43 Downloads retains cached poster")
        app.buttons["download-play-\(fixtureID)"].tap()
        let play = app.buttons["offline-play-pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" }, "The local H264 fixture must actually start playing.")
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        XCTAssertFalse(app.navigationBars["Downloads"].isHittable, "The offline player must cover the Downloads navigation header; covered controllers may remain in the accessibility tree.")
        let progress = app.sliders["offline-progress"]
        let beforeSeek = progress.value as? String
        app.buttons["offline-forward-10"].tap()
        XCTAssertTrue(wait { (progress.value as? String) != beforeSeek }, "Skip must move the real local video's timestamp.")
        capture("44 Full-canvas offline controls and real seek")
        app.buttons["offline-speed"].tap()
        XCTAssertTrue(app.buttons["offline-rate-1.25"].waitForExistence(timeout: 5))
        app.buttons["offline-rate-1.25"].tap()
        XCTAssertTrue(wait { self.app.buttons["offline-speed"].label.contains("1.25") })
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        capture("45 Landscape offline player")
        app.buttons["offline-lock"].tap()
        XCTAssertFalse(app.buttons["offline-play-pause"].exists)
        let unlock = app.buttons["offline-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        unlock.press(forDuration: 0.8)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        app.buttons["download-play-\(fixtureID)"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" })
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        XCTAssertTrue(wait { self.seconds(progress.value as? String ?? "") >= 9 }, "Reopening the same downloaded file must resume its saved timestamp.")
        capture("46 Reopened offline video resumes its saved progress")
        app.buttons["offline-close"].tap()
    }

    private func revealControls(for target: XCUIElement) {
        // Playback intentionally hides controls after four seconds. Reveal them
        // with the shipped canvas gesture when XCTest's earlier checks outlast it.
        if !target.exists || !target.isHittable {
            let canvas = app.otherElements["Offline video"].firstMatch
            XCTAssertTrue(canvas.waitForExistence(timeout: 5))
            canvas.tap()
            XCTAssertTrue(target.waitForExistence(timeout: 3))
        }
        XCTAssertTrue(target.isHittable)
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
    private func seconds(_ value: String) -> Int {
        let first = value.components(separatedBy: " of ").first ?? ""
        return first.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
