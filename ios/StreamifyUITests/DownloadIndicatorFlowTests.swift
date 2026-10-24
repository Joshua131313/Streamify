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
        XCTAssertEqual(value(known), "25 percent")
        let series = app.buttons["download-series-43"]
        XCTAssertTrue(series.waitForExistence(timeout: 5))
        XCTAssertTrue(series.label.contains("1 episode"), "A single saved episode must still use its show's drill-in.")
        XCTAssertEqual(value(series), "Downloading. Total size unknown")
        capture("Downloads groups its TV episode beneath the show")
        openSeries()
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        XCTAssertEqual(value(unknown), "Downloading. Total size unknown")
        XCTAssertFalse(value(unknown).contains("percent"), "Unknown totals must never display invented percentages.")
        XCTAssertTrue(known.label.contains("Cancel download"))
        XCTAssertGreaterThanOrEqual(known.frame.width, 44)
        XCTAssertGreaterThanOrEqual(known.frame.height, 44)
        capture("Downloads uses matching determinate and indeterminate rings")

        unknown.tap()
        XCTAssertTrue(wait { !unknown.exists }, "The ring's stop control must cancel its own transfer.")
        returnFromSeries()
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
        let series = app.buttons["download-series-43"]
        XCTAssertTrue(knownCard.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { self.value(knownCard) == "Artwork saved offline" })
        XCTAssertTrue(known.waitForExistence(timeout: 5))
        XCTAssertEqual(value(known), "25 percent")
        XCTAssertEqual(value(series), "Downloading. Total size unknown")
        XCTAssertFalse(app.staticTexts["download-progress-\(knownID)"].exists,
            "The circle carries progress without repeating visible Downloading/percentage text")
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
        XCTAssertEqual(value(series), "Downloading. Total size unknown", "Cancel must leave the show's other transfer running")
        let actions = app.buttons["download-actions-\(knownID)"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertEqual(value(actions), "Cancelled")
        XCTAssertEqual(value(knownCard), "Artwork saved offline", "Cancelling a transfer must keep the row's cached poster for Retry.")
        XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].exists)
        capture("Swipe cancel stops only the selected download")
        openSeries()
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        XCTAssertEqual(value(unknown), "Downloading. Total size unknown")
        XCTAssertFalse(app.staticTexts["download-progress-\(unknownID)"].exists)
        returnFromSeries()
    }

    func testSingleEpisodeShowPagePreservesExactSwipeActionsAndReturnsAfterLastRemoval() {
        XCTAssertTrue(app.buttons["open-downloads"].waitForExistence(timeout: 15))
        app.buttons["open-downloads"].tap()
        let series = app.buttons["download-series-43"]
        XCTAssertTrue(series.waitForExistence(timeout: 5))
        let beforeHold = value(series)
        series.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 1.2)
        let viewEpisodes = app.buttons["View episodes"]
        XCTAssertTrue(viewEpisodes.waitForExistence(timeout: 5))
        XCTAssertTrue(viewEpisodes.isHittable)
        XCTAssertTrue(app.buttons["Delete downloads"].isHittable)
        XCTAssertFalse(element("download-series-page-43").exists, "Holding the grouped show must open its native menu without activating navigation.")
        XCTAssertFalse(app.buttons["offline-play-pause"].exists)
        capture("Grouped show native hold menu preserves its episode downloads")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertTrue(wait { !viewEpisodes.exists && series.isHittable })
        XCTAssertEqual(value(series), beforeHold)
        XCTAssertTrue(app.buttons["download-activity-\(knownID)"].exists)
        XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].exists)
        openSeries()
        XCTAssertTrue(element("download-card-\(unknownID)").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["S1 E1 · A Call After Midnight"].exists)
        capture("The same held show opens its exact episode page after menu cancellation")
        returnFromSeries()
        series.swipeLeft()
        let deleteShow = app.buttons["download-series-swipe-delete-43"]
        XCTAssertTrue(deleteShow.waitForExistence(timeout: 5))
        deleteShow.tap()
        let confirmShow = app.buttons["download-series-confirm-delete-43"]
        XCTAssertTrue(confirmShow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Delete 1 episode download for Midnight Dispatch?"].exists)
        capture("Show deletion confirmation names only its own episode downloads")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            let dismiss = element("PopoverDismissRegion")
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            dismiss.tap()
        }
        XCTAssertTrue(wait { !confirmShow.exists && series.isHittable })
        openSeries()
        let episode = element("download-card-\(unknownID)")
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["S1 E1 · A Call After Midnight"].exists)
        XCTAssertTrue(app.buttons["download-series-more-43"].exists)
        episode.swipeLeft()
        let delete = app.buttons["download-swipe-delete-\(unknownID)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.buttons["Delete video"].waitForExistence(timeout: 5))
        capture("Show episode keeps its exact confirmed swipe deletion")
        app.buttons["Delete video"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["download-series-43"].exists)
        XCTAssertTrue(app.buttons["download-activity-\(knownID)"].exists)
        XCTAssertTrue(app.buttons["download-play-00000000-0000-0000-0000-000000000042"].exists,
            "Deleting the last episode must return to Downloads and preserve the movie and its other transfer.")
        capture("Removing the final episode returns to the unchanged movie downloads")
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
        app.buttons["download-actions-\(completedID)"].tap()
        let quality = app.buttons["download-choose-quality-\(completedID)"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        quality.tap()
        XCTAssertTrue(app.navigationBars["Download"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["1080p download quality"].exists)
        XCTAssertTrue(app.buttons["480p download quality"].exists)
        capture("Download quality can be chosen explicitly while the original file stays intact")
        app.navigationBars["Download"].buttons["Close"].tap()
        XCTAssertTrue(playFile.waitForExistence(timeout: 5))
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

    private func openSeries() {
        let series = app.buttons["download-series-43"]
        XCTAssertTrue(series.waitForExistence(timeout: 5))
        series.tap()
        XCTAssertTrue(element("download-series-page-43").waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Midnight Dispatch"].waitForExistence(timeout: 5))
    }

    private func returnFromSeries() {
        app.navigationBars["Midnight Dispatch"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
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
