import XCTest

/// Uses a synthetic 10-minute H264 local file: no download server or remote video.
final class OfflinePlayerFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let fixtureID = "00000000-0000-0000-0000-000000000042"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        if name.contains("testCachedPosterAndActualLocalPlaybackControls") {
            app.launchArguments.append("--ui-stable-offline-controls")
        }
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
        let duration = seconds(progressTimestamp(progress).components(separatedBy: " of ").last ?? "")
        XCTAssertEqual(duration, 600, "The seek must use the actual ten-minute local video.")
        let remaining = app.staticTexts["offline-remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 3))
        let beforeSeek = progressTimestamp(progress)
        let beforeSkipPosition = duration - remainingSeconds(remaining)
        app.buttons["offline-forward-10"].tap()
        XCTAssertTrue(wait(timeout: 30) {
            let actualPosition = duration - self.remainingSeconds(remaining)
            return !self.app.activityIndicators["Loading offline video"].exists
                && self.progressTimestamp(progress) != beforeSeek
                && (8...12).contains(actualPosition - beforeSkipPosition)
                && abs(actualPosition - self.seconds(self.progressTimestamp(progress))) <= 2
        }, "Skip must complete a real ten-second seek; slider=\(progressTimestamp(progress)); remaining=\(remaining.label); loading=\(app.activityIndicators["Loading offline video"].exists).")
        XCTAssertEqual(play.label, "Play", "Forward10 while paused must preserve the paused playback state.")
        XCTContext.runActivity(named: "Forward10 completed in actual player: before=\(beforeSkipPosition)s; after=\(duration - remainingSeconds(remaining))s; slider=\(progressTimestamp(progress)); remaining=\(remaining.label)") { _ in }
        capture("44 Full-canvas offline controls and real seek")
        XCTAssertGreaterThanOrEqual(progress.frame.height, 44)
        let beforeThumbSeek = seconds(progressTimestamp(progress))
        dragProgressThumbForPreview(progress, to: 0.7)
        XCTAssertTrue(wait(timeout: 30) {
            let committed = duration - self.remainingSeconds(remaining)
            return !self.app.activityIndicators["Loading offline video"].exists
                && committed > beforeThumbSeek + 30
                && abs(committed - self.seconds(self.progressTimestamp(progress))) <= 2
        }, "Releasing the native thumb must commit a substantial real forward seek, confirmed by the player's remaining time and slider timestamp.")
        let committedPosition = duration - remainingSeconds(remaining)
        XCTContext.runActivity(named: "Physical seek committed in actual player: \(committedPosition)s; slider=\(progressTimestamp(progress)); remaining=\(remaining.label)") { _ in }
        XCTAssertEqual(play.label, "Play", "Seeking while paused must preserve the paused playback state.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "offline-seek-preview").firstMatch.exists,
            "Releasing the native thumb must not leave its preview visible.")
        capture("44a Native thumb seek commits actual local playback position")
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
        unlock.press(forDuration: 0.75)
        XCTAssertTrue(unlock.exists, "Releasing before the one-second hold completes must keep the screen locked.")
        XCTAssertFalse(play.exists, "A canceled hold must not expose playback controls.")
        capture("45a Short unlock hold cancels without exposing controls")
        if !unlock.exists { app.otherElements["Offline video"].firstMatch.tap() }
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        unlock.press(forDuration: 1.15)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        app.buttons["download-play-\(fixtureID)"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" })
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        XCTAssertTrue(wait(timeout: 30) {
            !self.app.activityIndicators["Loading offline video"].exists
                && abs(duration - self.remainingSeconds(remaining) - committedPosition) <= 5
        },
            "Reopening the same downloaded file must resume within five seconds of its observed committed seek, confirmed by the actual player time.")
        XCTContext.runActivity(named: "Reopened player position: \(duration - remainingSeconds(remaining))s; saved seek=\(committedPosition)s; remaining=\(remaining.label)") { _ in }
        capture("46 Reopened offline video resumes its saved progress")
        app.buttons["offline-close"].tap()
    }

    func testHiddenEdgeBrightnessSwipeAndLockedGestureProtection() {
        XCTAssertTrue(app.buttons["open-downloads"].waitForExistence(timeout: 15))
        app.buttons["open-downloads"].tap()
        let download = app.buttons["download-play-\(fixtureID)"]
        XCTAssertTrue(download.waitForExistence(timeout: 8))
        download.tap()
        let play = app.buttons["offline-play-pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { play.isEnabled && play.label == "Pause" }, "The test must use the playing local video, not a placeholder canvas.")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })

        let brightness = app.sliders["offline-brightness"]
        XCTAssertTrue(wait { !play.exists }, "Normal playback must hide controls after rotation before the fixture reads brightness.")
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        XCTAssertTrue(brightness.waitForExistence(timeout: 3))
        XCTAssertTrue(brightness.isHittable)
        let initialBrightness = brightnessPercent(brightness)
        XCTAssertTrue((2...100).contains(initialBrightness), "Read an actual screen brightness percentage before testing its edge gesture.")
        let increaseBrightness = initialBrightness <= 50
        play.tap()
        XCTAssertTrue(wait { play.label == "Pause" })
        XCTAssertTrue(wait { !play.exists }, "Playing video must hide its controls through the normal inactivity timer.")
        capture("46a Offline video with playback controls hidden")

        // Move away from the current limit without depending on a simulator's
        // initial brightness or on XCTest dragging a rotated native slider.
        swipeBrightness(up: increaseBrightness)
        XCTAssertFalse(play.exists, "An edge brightness swipe should show its feedback without reopening playback controls.")
        capture("46b Hidden-control brightness gesture feedback")
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        let adjustedBrightness = brightnessPercent(brightness)
        let brightnessChange = increaseBrightness ? adjustedBrightness - initialBrightness : initialBrightness - adjustedBrightness
        XCTAssertGreaterThanOrEqual(brightnessChange, 15, "Swiping vertically near the hidden left slider must change the real player brightness in the swipe direction.")
        capture("46c Real brightness changed by the hidden edge gesture")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait { self.app.frame.height > self.app.frame.width })
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Pause" })
        XCTAssertTrue(wait { !play.exists })
        let portraitIncrease = adjustedBrightness <= 50
        swipeBrightness(up: portraitIncrease)
        XCTAssertFalse(play.exists, "The hidden edge gesture must also work in portrait without reopening playback controls.")
        capture("46d Portrait hidden-control brightness feedback")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        revealControls(for: play)
        play.tap()
        XCTAssertTrue(wait { play.label == "Play" })
        let portraitBrightness = brightnessPercent(brightness)
        let portraitChange = portraitIncrease ? portraitBrightness - adjustedBrightness : adjustedBrightness - portraitBrightness
        XCTAssertGreaterThanOrEqual(portraitChange, 15, "The portrait gesture must change actual screen brightness, verified through the landscape slider.")

        app.buttons["offline-lock"].tap()
        let unlock = app.buttons["offline-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        XCTAssertFalse(play.exists)
        swipeBrightness(up: !portraitIncrease)
        XCTAssertFalse(play.exists, "A locked player's edge swipe must not expose playback controls.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "offline-edge-feedback").firstMatch.exists,
            "Brightness and volume feedback must not be activated while playback controls are locked.")
        // The unlock affordance has its own three-second inactivity timer. Let
        // that real timer finish before re-revealing it; an existence snapshot
        // just before its deadline cannot guarantee a subsequent hold is safe.
        XCTAssertTrue(wait { !unlock.exists }, "The locked player must hide its temporary unlock affordance through the normal timer.")
        app.otherElements["Offline video"].firstMatch.tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 2))
        unlock.press(forDuration: 1.15)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(brightnessPercent(brightness), portraitBrightness, "A locked edge swipe must leave the actual brightness unchanged.")
        capture("46e Unlock restores controls with brightness unchanged")
        app.buttons["offline-close"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
    }

    private func swipeBrightness(up: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: up ? 0.72 : 0.37))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: up ? 0.37 : 0.72))
        start.press(forDuration: 0.05, thenDragTo: finish)
    }

    private func dragProgressThumbForPreview(_ progress: XCUIElement, to fraction: Double) {
        func geometry(_ prefix: String, label: String) -> [Double] {
            guard let field = label.components(separatedBy: "; ").first(where: { $0.hasPrefix(prefix) }) else { return [] }
            return field.dropFirst(prefix.count).split(separator: ",").compactMap { Double($0) }
        }
        let label = progress.label
        let thumb = geometry("fixture-thumb:", label: label)
        let range = geometry("fixture-range:", label: label)
        guard thumb.count == 2, range.count == 2, range[1] > range[0] else {
            XCTFail("The fixture must expose the presented native slider's actual thumb and track geometry: \(label)")
            return
        }
        let initialValue = progressTimestamp(progress)
        let origin = progress.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: thumb[0], dy: thumb[1]))
        let targetX = range[0] + (range[1] - range[0]) * fraction
        let end = origin.withOffset(CGVector(dx: targetX, dy: thumb[1]))
        // Exercise the presented native thumb and record its preview movement.
        // Assert the actual committed player time below; UIKit's expanded
        // tracking thumb need not land at an estimated percentage of its frame.
        XCTContext.runActivity(named: "Physical native thumb drag for decoded preview; value=\(initialValue); frame=\(progress.frame); \(label)") { _ in
            start.press(forDuration: 0.15, thenDragTo: end)
        }
        XCTAssertTrue(wait(timeout: 30) { self.progressTimestamp(progress) != initialValue }, "The physical drag must commit a real timestamp change.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "offline-seek-preview").firstMatch.exists,
            "Releasing the real thumb must dismiss its decoded preview.")
        XCTContext.runActivity(named: "Physical native thumb result: \(progressTimestamp(progress)); \(progress.label)") { _ in }
    }

    private func progressTimestamp(_ progress: XCUIElement) -> String {
        progress.value as? String ?? ""
    }

    private func remainingSeconds(_ remaining: XCUIElement) -> Int {
        seconds(remaining.label.components(separatedBy: " remaining").first ?? "")
    }

    private func brightnessPercent(_ slider: XCUIElement) -> Int {
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        let value = slider.value as? String ?? ""
        guard let percent = Int(value.filter(\.isNumber)) else {
            XCTFail("Expected the real brightness slider to expose an integer percentage; received '\(value)'.")
            return -1
        }
        return percent
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

    private func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
