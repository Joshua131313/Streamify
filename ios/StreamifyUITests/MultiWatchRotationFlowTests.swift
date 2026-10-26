import XCTest

final class MultiWatchRotationFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-multiwatch-two"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
        app.buttons["tab-sports"].tap()
        app.buttons["sports-menu"].tap()
        app.buttons["sports-multi-watch"].tap()
        XCTAssertTrue(app.buttons["Options for Game one"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Options for Game two"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("FAILURE two-game multi-watch")
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "FAILURE multi-watch hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testTwoGamesRotateSideBySideKeepDocumentsAndSwitchOneAudibleStream() {
        executionTimeAllowance = 240
        XCTAssertTrue(wait { self.tiles.count == 2 && self.documentMarkers.count == 2 })
        let documents = documentMarkers
        assertStacked()
        assertBothPlayingWithOneAudible()
        capture("Two-game multi-watch stacked in portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait {
            let tiles = self.tiles
            return tiles.count == 2 && abs(tiles[0].frame.midY - tiles[1].frame.midY) < 3 && tiles[0].frame.maxX <= tiles[1].frame.minX + 4
        }, "Two games must use a single side-by-side row in landscape.")
        XCTAssertEqual(documentMarkers, documents, "Rotation cannot recreate either WebKit document.")
        assertBothPlayingWithOneAudible()
        capture("Two-game multi-watch side by side in landscape")

        app.buttons["Listen to Game two"].tap()
        XCTAssertTrue(app.buttons["Mute Game two"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Listen to Game one"].exists)
        assertBothPlayingWithOneAudible()
        let times = timeMarkers
        XCTAssertTrue(wait { self.timeMarkers != times }, "Muted and audible video clocks must continue advancing after the handoff.")
        XCTAssertEqual(documentMarkers, documents)
        XCTAssertFalse(app.descendants(matching: .any)["sports-multiwatch-audio-error"].exists)
        capture("Audio handoff keeps both videos playing")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait {
            let tiles = self.tiles
            return tiles.count == 2 && abs(tiles[0].frame.midX - tiles[1].frame.midX) < 3 && tiles[0].frame.maxY <= tiles[1].frame.minY + 4
        })
        assertStacked()
        XCTAssertEqual(documentMarkers, documents)
        XCTAssertTrue(app.buttons["Mute Game two"].waitForExistence(timeout: 8))
        assertBothPlayingWithOneAudible()
        capture("Returning to portrait preserves both streams and chosen audio")
    }

    private var tiles: [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: "sports-watch-tile").allElementsBoundByIndex
    }
    private var documentMarkers: Set<String> {
        Set(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Multi-watch document '")).allElementsBoundByIndex.map(\.label))
    }
    private var timeMarkers: [String] {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Multi-watch time '")).allElementsBoundByIndex.map(\.label)
    }
    private func assertStacked() {
        let current = tiles
        XCTAssertEqual(current.count, 2)
        guard current.count == 2 else { return }
        XCTAssertEqual(current[0].frame.midX, current[1].frame.midX, accuracy: 3)
        XCTAssertLessThanOrEqual(current[0].frame.maxY, current[1].frame.minY + 4)
    }
    private func assertBothPlayingWithOneAudible() {
        XCTAssertTrue(wait {
            self.app.staticTexts["Multi-watch media playing audible"].exists &&
            self.app.staticTexts["Multi-watch media playing muted"].exists &&
            self.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Multi-watch media paused'")).count == 0
        }, "Audio changes must mute one real video without pausing either video.")
    }
    private func wait(_ condition: () -> Bool, _ message: String = "", timeout: TimeInterval = 10) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
