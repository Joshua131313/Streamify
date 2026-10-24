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
        let beforeSeek = progress.value as? String
        app.buttons["offline-forward-10"].tap()
        XCTAssertTrue(wait { (progress.value as? String) != beforeSeek }, "Skip must move the real local video's timestamp.")
        capture("44 Full-canvas offline controls and real seek")
        XCTAssertGreaterThanOrEqual(progress.frame.height, 44)
        dragProgressThumb(progress, to: 0.3)
        XCTAssertTrue(wait {
            let value = progress.value as? String ?? ""
            return value.contains(" of 10:00") && (170...190).contains(self.seconds(value))
        }, "The native adjustable slider must commit a real seek near three minutes in the ten-minute local fixture; actual value: \(progress.value as? String ?? "missing").")
        XCTAssertEqual(play.label, "Play", "Seeking while paused must preserve the paused playback state.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "offline-seek-preview").firstMatch.exists,
            "A completed accessibility seek must not leave a held-thumb preview visible.")
        capture("44a Native seek slider commits actual local playback position")
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
        XCTAssertTrue(wait { self.seconds(progress.value as? String ?? "") >= 9 }, "Reopening the same downloaded file must resume its saved timestamp.")
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
        // A locked-canvas gesture may reveal the unlock affordance; it must never
        // adjust brightness or bypass the same hold interaction used on Android.
        if !unlock.exists { app.otherElements["Offline video"].firstMatch.tap() }
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
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

    private func dragProgressThumb(_ progress: XCUIElement, to fraction: Double) {
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
        func drag(from nativeThumb: [Double], to targetX: Double) {
            let origin = progress.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: nativeThumb[0], dy: nativeThumb[1]))
            let end = origin.withOffset(CGVector(dx: targetX, dy: nativeThumb[1]))
            start.press(forDuration: 0.15, thenDragTo: end)
        }
        let initialValue = progress.value as? String ?? ""
        let initialSeconds = Double(seconds(initialValue))
        let duration = Double(seconds(initialValue.components(separatedBy: " of ").last ?? ""))
        let targetSeconds = duration * fraction
        // Calibrate well away from the target, so the second physical movement
        // clears the native expanded thumb's drag threshold instead of being a
        // tiny, ignored correction within its press area.
        let calibrationFraction = fraction <= 0.5 ? 0.7 : 0.2
        let firstTargetX = range[0] + (range[1] - range[0]) * calibrationFraction
        XCTContext.runActivity(named: "First real native seek calibration toward \(calibrationFraction); desired=\(targetSeconds); value=\(initialValue); frame=\(progress.frame); \(label)") { _ in
            drag(from: thumb, to: firstTargetX)
        }
        XCTAssertTrue(wait { (progress.value as? String) != initialValue }, "The first physical drag must commit a real timestamp change.")
        let firstValue = progress.value as? String ?? ""
        let committedSeconds = Double(seconds(firstValue))
        let firstDelta = committedSeconds - initialSeconds
        let physicalDelta = firstTargetX - thumb[0]
        // iOS26 expands its native thumb while tracking. Its collapsed public
        // thumbRect endpoints do not predict that held movement precisely.
        // Calibrate once from the actual committed timestamp, then regrab the
        // real presented thumb; never assign player state or weaken the result.
        if abs(committedSeconds - targetSeconds) > 10, abs(firstDelta) > 1, abs(physicalDelta) > 1 {
            let currentLabel = progress.label
            let currentThumb = geometry("fixture-thumb:", label: currentLabel)
            guard currentThumb.count == 2 else { XCTFail("Missing presented thumb after seek: \(currentLabel)"); return }
            let correction = (targetSeconds - committedSeconds) * physicalDelta / firstDelta
            let correctedTargetX = min(range[1], max(range[0], currentThumb[0] + correction))
            XCTContext.runActivity(named: "One calibrated real drag; committed=\(firstValue); physicalDelta=\(physicalDelta); secondsDelta=\(firstDelta); targetX=\(correctedTargetX); \(currentLabel)") { _ in
                drag(from: currentThumb, to: correctedTargetX)
            }
            XCTAssertTrue(wait { (progress.value as? String) != firstValue }, "The one correction drag must commit another actual timestamp change.")
        }
        XCTContext.runActivity(named: "Real native seek result: \(progress.value as? String ?? "missing"); \(progress.label)") { _ in }
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
