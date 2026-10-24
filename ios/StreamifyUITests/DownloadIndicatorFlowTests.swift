import XCTest

/// Deterministic transfer states only; these fixtures never start a network
/// download. The production buttons still perform their normal navigation/cancel.
final class DownloadIndicatorFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let knownID = "00000000-0000-0000-0000-000000000143"
    private let unknownID = "00000000-0000-0000-0000-000000000144"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--ui-download-status-fixture"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE download indicators")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE download indicator hierarchy"
            hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testRealFractionsUnknownTotalsAndCancellationUpdateHeader() {
        let toolbar = app.buttons["open-downloads"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        XCTAssertTrue(wait { self.value(toolbar) == "2 downloads in progress, total size unknown" },
            "A transfer with an unknown total must keep the aggregate indeterminate.")
        capture("Download activity header with an unknown aggregate")

        // Open the actual movie hero. Its active download action must keep its
        // navigation behavior rather than silently becoming a stop button.
        let firstSlide = app.buttons["Show The Last Horizon"].firstMatch
        XCTAssertTrue(firstSlide.waitForExistence(timeout: 10))
        let carouselPause = app.buttons["hero-carousel-pause"]
        if carouselPause.label == "Pause carousel" { carouselPause.tap() }
        firstSlide.tap()
        let details = app.buttons["Details for The Last Horizon"].firstMatch
        XCTAssertTrue(wait { details.exists && details.isHittable })
        details.tap()
        let movieDownload = app.buttons["download-movie:42"]
        XCTAssertTrue(movieDownload.waitForExistence(timeout: 8))
        reveal(movieDownload)
        XCTAssertEqual(value(movieDownload), "25 percent")
        XCTAssertTrue(movieDownload.label.contains("Downloading"))
        capture("Movie download action displays the actual 25 percent ring")
        movieDownload.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5),
            "Tapping the movie's progress ring must still open Downloads.")

        let known = app.buttons["download-activity-\(knownID)"]
        let unknown = app.buttons["download-activity-\(unknownID)"]
        XCTAssertTrue(known.waitForExistence(timeout: 5))
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        XCTAssertEqual(value(known), "25 percent")
        XCTAssertEqual(value(unknown), "Downloading. Total size unknown")
        XCTAssertFalse(value(unknown).contains("percent"), "Unknown totals must never display invented percentages.")
        XCTAssertTrue(known.label.contains("Cancel download"))
        XCTAssertGreaterThanOrEqual(known.frame.width, 44)
        XCTAssertGreaterThanOrEqual(known.frame.height, 44)
        capture("Downloads uses matching determinate and indeterminate rings")

        unknown.tap()
        XCTAssertTrue(wait { !unknown.exists }, "The ring's stop control must cancel its own transfer.")
        XCTAssertTrue(known.exists, "Canceling another episode must preserve the movie's active transfer.")
        XCTAssertEqual(value(known), "25 percent")
        app.navigationBars["Downloads"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["close-media-details"].waitForExistence(timeout: 5))
        app.buttons["close-media-details"].tap()
        XCTAssertTrue(wait { toolbar.isHittable && self.value(toolbar) == "1 download in progress, 25 percent" },
            "With only the known transfer left, the header must expose its real byte fraction.")
        capture("Download activity header reflects the remaining known transfer")

        toolbar.tap()
        XCTAssertTrue(known.waitForExistence(timeout: 5))
        known.tap()
        XCTAssertTrue(wait { !known.exists })
        XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].exists,
            "Canceling active transfers must preserve the completed offline video.")
        app.navigationBars["Downloads"].buttons["Close"].tap()
        XCTAssertTrue(wait { toolbar.isHittable && self.value(toolbar) == "No active downloads" })
        capture("Download activity clears after the last transfer is canceled")
    }

    func testSwipeLeftRevealsActionsAndCancelOnlyStopsItsTransfer() {
        let toolbar = app.buttons["open-downloads"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        let knownCard = element("download-card-\(knownID)")
        let known = app.buttons["download-activity-\(knownID)"]
        let unknown = app.buttons["download-activity-\(unknownID)"]
        XCTAssertTrue(knownCard.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { self.value(knownCard) == "Artwork saved offline" })
        XCTAssertTrue(known.waitForExistence(timeout: 5))
        XCTAssertEqual(value(known), "25 percent")
        XCTAssertEqual(value(unknown), "Downloading. Total size unknown")
        XCTAssertFalse(app.staticTexts["download-progress-\(knownID)"].exists,
            "The circle carries progress without repeating visible Downloading/percentage text")
        XCTAssertFalse(app.staticTexts["download-progress-\(unknownID)"].exists)
        knownCard.swipeLeft()
        let cancel = app.buttons["download-swipe-cancel-\(knownID)"]
        let delete = app.buttons["download-swipe-delete-\(knownID)"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(delete.isHittable)
        XCTAssertTrue(known.exists, "A swipe must reveal actions, never execute one by itself")
        XCTAssertFalse(app.buttons["Delete video"].exists)
        capture("Swipe left reveals download actions without repeating transfer text")
        cancel.tap()
        XCTAssertTrue(wait { !known.exists })
        XCTAssertTrue(unknown.exists, "Cancel must leave the other transfer running")
        let actions = app.buttons["download-actions-\(knownID)"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertEqual(value(actions), "Cancelled")
        XCTAssertEqual(value(knownCard), "Artwork saved offline", "Cancelling a transfer must keep the row's cached poster for Retry.")
        XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].exists)
        capture("Swipe cancel stops only the selected download")
    }

    func testCompletedSwipeDeleteRequiresConfirmationAndCancelPreservesPlayableFile() {
        let toolbar = app.buttons["open-downloads"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15))
        toolbar.tap()
        let completedID = "00000000-0000-0000-0000-000000000042"
        let card = element("download-card-\(completedID)")
        let playFile = app.buttons["download-play-\(completedID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { self.value(card) == "Artwork saved offline" })
        reveal(playFile)
        card.swipeLeft()
        let delete = app.buttons["download-swipe-delete-\(completedID)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(delete.isHittable)
        XCTAssertFalse(app.buttons["Delete video"].exists, "Swiping alone must never confirm or delete a local file")
        delete.tap()
        let confirmDelete = app.buttons["Delete video"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        capture("Download swipe deletion requires its existing file confirmation")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            // iOS 26 presents this confirmation as a popover. Its cancel
            // affordance is the actual surrounding dismissal region.
            let dismiss = element("PopoverDismissRegion")
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            XCTAssertTrue(dismiss.isHittable)
            dismiss.tap()
        }
        XCTAssertTrue(wait { !confirmDelete.exists && playFile.isHittable })
        playFile.tap()
        let play = app.buttons["offline-play-pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" },
            "Cancelling deletion must preserve the actual local H264 file and its playback")
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        XCTAssertTrue(wait { (self.app.sliders["offline-progress"].value as? String ?? "").contains(" of 10:00") })
        XCTAssertFalse(element("offline-video-error").exists)
        capture("Cancelled swipe deletion leaves the saved video playable")
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(card.exists)
        XCTAssertTrue(playFile.isHittable)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<10 {
            if target.exists && target.isHittable { return }
            // Scroll the content gutter, away from media buttons and the detail
            // card's downward-dismiss gesture, until this action is visible.
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.75 : 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.35 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
