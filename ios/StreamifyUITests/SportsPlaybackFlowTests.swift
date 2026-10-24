import XCTest

/// Local WebKit fixtures verify session ownership and app navigation. They do
/// not claim that an external provider supports system Picture in Picture.
final class SportsPlaybackFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        if name.contains("testNativeSystemPictureInPicture") { app.launchArguments.append("--ui-native-pip-fixture") }
        if name.contains("testProviderElementFullscreen") { app.launchArguments.append("--ui-element-fullscreen-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app {
            capture("FAILURE sports playback session")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "FAILURE sports playback accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testFullscreenExpandsTheSameSelectedSportsDocumentAndReturnsToControls() {
        app.buttons["tab-sports"].tap()
        selectNBA()
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        XCTAssertTrue(watch.isHittable)
        watch.tap()
        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let document = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        let originalDocument = document.label
        source.tap()
        XCTAssertTrue(app.buttons["sports-player-source-option-1"].waitForExistence(timeout: 5))
        app.buttons["sports-player-source-option-1"].tap()
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") })
        XCTAssertTrue(wait { document.exists && document.label != originalDocument })
        let selectedDocument = document.label
        let fullscreen = app.buttons["sports-player-fullscreen"]
        XCTAssertTrue(fullscreen.isHittable)
        fullscreen.tap()
        let exit = app.buttons["sports-player-exit-fullscreen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 8))
        XCTAssertTrue(wait { app.frame.width > app.frame.height }, "Fullscreen should request the supported landscape scene")
        XCTAssertTrue(wait { !source.exists }, "Fullscreen must release the header's video space and hide its controls")
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertEqual(document.label, selectedDocument, "Fullscreen must retain the same WKWebView document instead of reconnecting")
        capture("Sports fullscreen keeps the same bravo document in landscape")
        exit.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(wait { app.frame.height > app.frame.width }, "Exit should restore the prior portrait scene")
        XCTAssertTrue((source.value as? String ?? "").contains("bravo"))
        XCTAssertEqual(document.label, selectedDocument)
        XCTAssertTrue(fullscreen.isHittable)
        XCTAssertFalse(exit.exists)
        capture("Sports fullscreen exit restores controls without reconnecting the stream")
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
    }

    func testProviderElementFullscreenKeepsTheSameDocumentAndExitsNormally() {
        app.buttons["tab-sports"].tap()
        selectNBA()
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        XCTAssertTrue(watch.isHittable)
        watch.tap()
        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let document = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        let selectedDocument = document.label
        let sourceValue = source.value as? String
        let enter = app.webViews.buttons["Enter provider fullscreen"]
        XCTAssertTrue(enter.waitForExistence(timeout: 8))
        enter.tap()
        let active = app.webViews.staticTexts["Provider fullscreen active"]
        XCTAssertTrue(active.waitForExistence(timeout: 10), "The actual WebKit fullscreenchange event must confirm element fullscreen")
        XCTAssertEqual(document.label, selectedDocument)
        capture("Actual provider element fullscreen keeps the same document")
        let exit = app.webViews.buttons["Exit provider fullscreen"]
        XCTAssertTrue(exit.isHittable)
        exit.tap()
        XCTAssertTrue(app.webViews.staticTexts["Provider inline"].waitForExistence(timeout: 8))
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(source.isHittable)
        XCTAssertEqual(source.value as? String, sourceValue)
        XCTAssertEqual(document.label, selectedDocument)
        capture("Provider element fullscreen exits without losing its document or source")
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
    }

    func testSelectedSportsSourceAndDocumentSurviveBackgroundRoundTrip() {
        app.buttons["tab-sports"].tap()
        selectNBA()
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        XCTAssertTrue(watch.waitForExistence(timeout: 10))
        XCTAssertTrue(watch.isHittable)
        watch.tap()

        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let document = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        let alphaDocument = document.label
        source.tap()
        let bravo = app.buttons["sports-player-source-option-1"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))
        bravo.tap()
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") })
        XCTAssertTrue(wait { document.exists && document.label != alphaDocument }, "Choosing a different source must load that source's document.")
        let selectedDocument = document.label
        XCTAssertTrue((source.value as? String ?? "").contains("BOS vs TOR"))
        capture("Sports session uses selected bravo source")

        backgroundAndReturn()
        XCTAssertTrue(source.waitForExistence(timeout: 8), "Returning from the Home screen must retain the expanded player.")
        XCTAssertTrue((source.value as? String ?? "").contains("bravo"))
        XCTAssertTrue(document.waitForExistence(timeout: 8))
        XCTAssertEqual(document.label, selectedDocument, "Backgrounding must keep the actual selected WebKit document alive.")
        let unavailablePiP = app.buttons["sports-player-pip"]
        XCTAssertTrue(unavailablePiP.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { unavailablePiP.value as? String == "Unavailable" }, "The HTML fixture contains no playable video and must not claim PiP capability.")
        unavailablePiP.tap()
        XCTAssertTrue(app.alerts["Picture in Picture"].waitForExistence(timeout: 5))
        app.alerts["Picture in Picture"].buttons["OK"].tap()
        XCTAssertTrue(source.exists)
        XCTAssertEqual(document.label, selectedDocument)
        XCTAssertFalse(app.buttons["sports-pip-restore"].exists, "An unsupported request must not create an active PiP state.")

        capture("Returning to the app retains the actual game document and selected source")
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
    }

    func testClosedSportsPlayerStaysClosedAfterSwitchingTabs() {
        app.buttons["tab-sports"].tap()
        selectNBA()
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        XCTAssertTrue(watch.isHittable)
        watch.tap()
        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        let reopened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in source.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 3), .timedOut,
            "Returning to Sports must not replay a consumed Watch action.")
        XCTAssertFalse(app.buttons["sports-pip-restore"].exists)
        capture("Closed sports player stays closed after Home round trip")
        // A new explicit Watch press must still work after the old request is consumed.
        reveal(watch)
        watch.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
    }

    func testNativeSystemPictureInPictureKeepsTheSelectedGameWhileBrowsing() throws {
        app.buttons["tab-sports"].tap()
        selectNBA()
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        XCTAssertTrue(watch.isHittable)
        watch.tap()
        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        XCTAssertTrue(app.buttons["sports-player-source-option-1"].waitForExistence(timeout: 5))
        app.buttons["sports-player-source-option-1"].tap()
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") })
        let nativePlay = app.buttons["sports-native-play-pause"]
        XCTAssertTrue(nativePlay.waitForExistence(timeout: 12))
        XCTAssertTrue(wait(timeout: 15) { nativePlay.isEnabled && nativePlay.label == "Pause" }, "The actual bundled H264 video must be playing before evaluating PiP support.")
        let pip = app.buttons["sports-player-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(timeout: 15) { ["Available", "Unavailable"].contains(pip.value as? String ?? "") }, "The real native PiP driver must finish checking capability.")
        if pip.value as? String == "Unavailable" {
            _ = wait(timeout: 5) { pip.value as? String == "Available" }
        }
        if pip.value as? String == "Unavailable" {
            capture("Actual native video plays but this runtime reports PiP unavailable")
            throw XCTSkip("The bundled H264 video is playing, but native Picture in Picture is unavailable on this runtime. Session and WebKit lifecycle checks run separately.")
        }
        XCTAssertTrue(pip.isEnabled)
        pip.tap()
        let restore = app.buttons["sports-pip-restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 12), "The restore action appears only after the real system PiP didStart callback.")
        XCTAssertTrue(wait { !source.exists })
        XCTAssertFalse(element("sports-mini-player").exists, "Browsing must use the operating system's video window.")
        capture("Native system PiP started from the real video fixture")
        app.buttons["tab-search"].tap()
        XCTAssertTrue(app.buttons["tab-search"].isSelected)
        XCTAssertTrue(app.buttons["open-catalog-search-dialog"].waitForExistence(timeout: 5))
        XCTAssertTrue(restore.isHittable)
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        XCTAssertTrue(restore.isHittable)
        backgroundAndReturn()
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        capture("Native system PiP survives app browsing and backgrounding")
        restore.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue((source.value as? String ?? "").contains("BOS vs TOR"))
        XCTAssertTrue((source.value as? String ?? "").contains("bravo"))
        XCTAssertTrue(wait { nativePlay.exists && nativePlay.isEnabled && nativePlay.label == "Pause" })
        XCTAssertTrue(wait { !restore.exists })
        capture("System PiP restores the same selected sports stream")
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
    }

    private func selectNBA() {
        let picker = app.buttons["sports-league-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        app.buttons["sports-clear-leagues"].tap()
        app.buttons["sports-league-option-nba"].tap()
        let apply = app.buttons["sports-apply-leagues"]
        reveal(apply)
        apply.tap()
        XCTAssertTrue(wait { picker.value as? String == "NBA" })
    }

    private func backgroundAndReturn() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(wait(timeout: 8) { self.app.state != .runningForeground })
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<16 {
            if target.exists && target.isHittable { return }
            let up = !(target.exists && target.frame.maxY < app.frame.midY)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.78 : 0.28))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: up ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(timeout: TimeInterval = 8, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
