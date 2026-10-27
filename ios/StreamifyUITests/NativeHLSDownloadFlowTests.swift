import XCTest

/// Downloads only our immutable, five-second synthetic control through the
/// actual background HLS owner/store. No completed-file fixture, provider API,
/// full TV episode or remote account is involved in this flow.
final class NativeHLSDownloadFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let title = "Offline HLS Control"
    private let arguments = ["--ui-fixtures", "--ui-hls-download-control", "--ui-stable-offline-controls"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = arguments + ["--ui-hls-reset-control"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE real offline HLS flow")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE real offline HLS hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testReal1080EnglishHLSDownloadPlaysPersistsRelaunchAndDeletesThroughEpisodeUI() throws {
        openDownloadsAndSeries()
        capture("Real HLS store transfer entered its episode page")
        let play = episodePlayButton()
        XCTAssertTrue(wait(timeout: 90) { play.exists && play.isEnabled && play.isHittable && play.label.hasPrefix("Play offline") },
            "A real complete package and production offline validation must enable Play; pending/failed metadata cannot stand in for completion.")
        let downloadID = String(play.identifier.dropFirst("download-play-".count))
        XCTAssertNotNil(UUID(uuidString: downloadID), "The real store must supply the retained download UUID.")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == %@", play.identifier)).count, 1)
        let episodePage = element("download-series-page-900043")
        XCTAssertFalse(episodePage.staticTexts["Download unavailable"].exists)
        XCTAssertFalse(episodePage.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*\\b0 (B|bytes)\\b.*")).firstMatch.exists,
            "A completed native package must not display the old misleading zero-byte file summary.")
        if app.staticTexts["1080p"].exists { XCTAssertTrue(app.staticTexts["1080p"].isHittable) }
        capture("Real background HLS transfer completed and enabled this exact episode")
        playAndVerifyCachedEnglish(play, stage: "First actual local package playback")

        app.terminate()
        app.launchArguments = arguments // No reset, fake file installation or second transfer.
        app.launch()
        openDownloadsAndSeries()
        let restored = app.buttons["download-play-\(downloadID)"]
        XCTAssertTrue(wait(timeout: 15) { restored.exists && restored.isEnabled && restored.isHittable && restored.label.hasPrefix("Play offline") },
            "The second process must retain the same completed UUID and native package through real metadata restoration.")
        XCTAssertFalse(element("download-series-page-900043").descendants(matching: .button).matching(NSPredicate(format: "identifier BEGINSWITH %@", "download-activity-")).firstMatch.exists,
            "A persisted completed episode must not restart its download on relaunch.")
        capture("Relaunch restored the original completed HLS download UUID")
        playAndVerifyCachedEnglish(restored, stage: "Restored local HLS package playback")

        let row = element("download-card-\(downloadID)")
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
        row.swipeLeft()
        let delete = app.buttons["download-swipe-delete-\(downloadID)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
        delete.tap()
        let confirmation = app.buttons["Delete video"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); XCTAssertTrue(confirmation.isHittable)
        XCTAssertTrue(app.staticTexts["Delete \(title) · S1 E1 · Synthetic five-second English control?"].exists,
            "Deletion must target only this synthetic episode.")
        capture("Actual episode swipe requires confirmation before deleting its package")
        confirmation.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["download-series-900043"].exists)
        XCTAssertFalse(app.buttons["download-play-\(downloadID)"].exists)
        capture("Native package deletion removes only the tested episode from Downloads")
    }

    private func openDownloadsAndSeries() {
        let toolbar = app.buttons["open-downloads"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 20)); XCTAssertTrue(toolbar.isHittable)
        toolbar.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        let series = app.buttons["download-series-900043"]
        XCTAssertTrue(series.waitForExistence(timeout: 10)); XCTAssertTrue(series.isHittable)
        series.tap()
        XCTAssertTrue(element("download-series-page-900043").waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    private func episodePlayButton() -> XCUIElement {
        let page = element("download-series-page-900043")
        return page.descendants(matching: .button).matching(NSPredicate(format: "identifier BEGINSWITH %@", "download-play-")).firstMatch
    }

    private func playAndVerifyCachedEnglish(_ button: XCUIElement, stage: String) {
        button.tap()
        XCTAssertTrue(element("offline-player").waitForExistence(timeout: 15))
        let transport = app.buttons["offline-play-pause"]
        XCTAssertTrue(wait(timeout: 15) { transport.exists && transport.isEnabled && (transport.label == "Pause" || self.app.buttons["Watch again"].exists) },
            "The real saved HLS package must become ready and play rather than show an error or indefinite spinner.")
        pauseReadyPlayer(transport)
        let progress = app.sliders["offline-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5)); XCTAssertTrue(progress.isEnabled)
        let start = progress.value as? String ?? ""
        XCTAssertTrue(start.contains(" of 0:05"), "The saved native package must expose the real five-second media duration: \(start)")
        transport.tap()
        XCTAssertTrue(wait(timeout: 5) { transport.label == "Pause" })
        XCTAssertTrue(wait(timeout: 4) { (progress.value as? String ?? "") != start },
            "Actual offline playback time must advance.")
        pauseReadyPlayer(transport)
        XCTAssertFalse(element("offline-video-error").exists)
        capture(stage)
        let tracks = app.buttons["offline-audio-subtitles"]
        XCTAssertTrue(tracks.isHittable); tracks.tap()
        let sheet = app.navigationBars["Audio & Subtitles"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let english = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "English")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5)); XCTAssertTrue(english.isHittable)
        XCTAssertTrue(english.isSelected, "The real local package must retain its selected playable, cached English audio option.")
        capture("\(stage) cached English selection")
        sheet.buttons["Done"].tap()
        let close = app.buttons["offline-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(element("download-series-page-900043").waitForExistence(timeout: 5))
        XCTAssertFalse(element("offline-player").exists)
    }

    private func pauseReadyPlayer(_ transport: XCUIElement) {
        if transport.label == "Pause" { transport.tap() }
        // The intentionally tiny control may finish while XCTest captures a
        // hierarchy. Replay through the real UI before inspecting its tracks;
        // a finished overlay must not cover the controls being asserted.
        if app.buttons["Watch again"].exists {
            app.buttons["Watch again"].tap()
            XCTAssertTrue(wait(timeout: 5) { transport.isEnabled && transport.label == "Pause" })
            transport.tap()
        }
        XCTAssertTrue(wait(timeout: 5) { transport.isEnabled && transport.label == "Play" })
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func wait(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
