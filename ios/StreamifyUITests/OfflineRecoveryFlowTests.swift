import XCTest

/// A genuinely malformed local file exercises legacy-download recovery. No
/// transfer, metadata-only fake player, or remote video is used by this test.
final class OfflineRecoveryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let fixtureID = "00000000-0000-0000-0000-000000000042"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-damaged-download-fixture"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { capture("FAILURE offline recovery") }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDamagedLocalVideoOffersRecoveryAndKeepsExitReachableInLandscape() {
        let open = app.buttons["open-downloads"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let saved = app.buttons["download-play-\(fixtureID)"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        saved.tap()
        XCTAssertTrue(app.staticTexts["Video unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["offline-play-pause"].exists)
        XCTAssertTrue(app.buttons["offline-share-video"].exists)
        let recovery = app.buttons["offline-recover-download"]
        XCTAssertTrue(recovery.isHittable)
        capture("Offline damaged-file recovery preserves the original file")
        recovery.tap()
        XCTAssertTrue(app.navigationBars["Download"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["720p download quality"].exists)
        XCTAssertTrue(app.buttons["start-media-download"].exists)
        // Merely inspecting replacement choices must not discard the old file
        // or start another transfer. Start download remains an explicit action.
        app.navigationBars["Download"].buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Video unavailable"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(app.buttons["offline-close"].isHittable)
        let close = app.buttons["Close video"]
        let panel = app.descendants(matching: .any).matching(identifier: "offline-video-error").firstMatch
        for _ in 0..<5 {
            if close.exists && close.isHittable { break }
            panel.swipeUp()
        }
        XCTAssertTrue(close.isHittable, "Recovery actions must remain reachable in landscape rather than clipping below the player.")
        capture("Landscape offline recovery scrolls while Exit stays available")
        close.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(saved.exists, "A failed playback attempt must not silently delete an existing download.")
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
