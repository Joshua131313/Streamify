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
        if name.contains("testProviderElementFullscreen") || name.contains("testSwipeDownSportsPlayer") { app.launchArguments.append("--ui-element-fullscreen-fixture") }
        if name.contains("testSportsFullscreenUsesTheProvidersOwnControl") { app.launchArguments.append("--ui-provider-controls-fullscreen-fixture") }
        if name.contains("testSportsWatchAutoplaysReadyVideoAndPreservesAnExplicitPause") { app.launchArguments += ["--ui-provider-controls-fullscreen-fixture", "--ui-sports-autoplay-fixture"] }
        if name.contains("testSportsBlocksPopupsWithoutInterceptingPlayerControls") { app.launchArguments += ["--ui-provider-controls-fullscreen-fixture", "--ui-provider-popup-fixture"] }
        if name.contains("testProviderNativeVideoFullscreen") { app.launchArguments.append("--ui-native-video-fullscreen-fixture") }
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

    func testGameAndStreamSelectorsSwitchIndependentlyAndKeepOnePlayer() {
        let source = openSportsPlayerOnBravo()
        let game = app.buttons["sports-player-game-picker"]
        XCTAssertTrue(game.exists)
        XCTAssertTrue((game.value as? String ?? "").hasPrefix("NBA,"))
        assertSinglePlaybackSurface()
        game.tap()
        let football = app.buttons["sports-player-game-option-nfl:nfl-fixture"]
        XCTAssertTrue(football.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["sports-player-game-option-nba:nba-final"].exists)
        XCTAssertFalse(app.buttons["sports-player-game-option-nba:nba-pregame"].exists)
        capture("Live game selector separates matchups from current stream choices")
        football.tap()
        XCTAssertTrue(wait { (game.value as? String ?? "").hasPrefix("NFL,") })
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") }, "A new game uses the user's saved server when available.")
        XCTAssertTrue(playbackDocument.waitForExistence(timeout: 10))
        assertSinglePlaybackSurface()

        source.tap()
        app.buttons["sports-player-source-option-0"].tap()
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("alpha") })
        source.tap()
        app.buttons["sports-player-source-option-1"].tap()
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") })
        XCTAssertTrue((game.value as? String ?? "").hasPrefix("NFL,"), "Changing servers cannot change the selected game.")
        let pip = app.buttons["sports-player-pip"]
        XCTAssertTrue(wait { pip.value as? String == "Unavailable" })
        let sharedChannelDocument = playbackDocument.label
        game.tap()
        let basketball = app.buttons["sports-player-game-option-nba:nba-fixture"]
        XCTAssertTrue(basketball.waitForExistence(timeout: 5))
        basketball.tap()
        XCTAssertTrue(wait { (game.value as? String ?? "").hasPrefix("NBA,") })
        XCTAssertTrue((source.value as? String ?? "").contains("bravo"), "Returning to NBA restores its previous server.")
        assertSinglePlaybackSurface()
        XCTAssertEqual(playbackDocument.label, sharedChannelDocument,
            "When game entries share a channel, changing metadata must not reload its document.")
        XCTAssertEqual(pip.value as? String, "Unavailable",
            "The retained no-video fixture must keep its confirmed capability, not lose its bridge and stay Checking.")
        let document = playbackDocument.label
        backgroundAndReturn()
        XCTAssertTrue(wait { source.isHittable && game.isHittable })
        XCTAssertTrue((game.value as? String ?? "").hasPrefix("NBA,"))
        XCTAssertTrue((source.value as? String ?? "").contains("bravo"))
        XCTAssertEqual(playbackDocument.label, document)
        for identifier in ["sports-player-reload", "sports-player-direct", "sports-player-browser"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        capture("Independent game and server selects with visible utility buttons")
        app.buttons["sports-player-reload"].tap()
        XCTAssertTrue(wait { self.playbackDocument.exists && self.playbackDocument.label != document })
        XCTAssertTrue((game.value as? String ?? "").hasPrefix("NBA,"))
        XCTAssertTrue((source.value as? String ?? "").contains("bravo"))
        assertSinglePlaybackSurface()
        closeAndVerifySportsDoesNotReopen(source)
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        reveal(watch)
        XCTAssertTrue(watch.isHittable)
        watch.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") }, "Closing the player and changing tabs must not forget the selected server.")
        assertSinglePlaybackSurface()
        capture("Saved server restored after closing and reopening the sports player")
    }

    func testLandscapeVideoFillsCanvasAndRotationKeepsTheSameStreamDocument() {
        let source = openSportsPlayerOnBravo(viaWatchLink: true)
        let selectedSource = source.value as? String
        let document = playbackDocument.label
        let video = element("sports-video-surface")
        XCTAssertTrue(video.exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height && video.frame.width > video.frame.height })
        XCTAssertGreaterThanOrEqual(video.frame.height, app.frame.height - 3,
            "Landscape must not reserve header/footer space and shrink the actual video viewport.")
        XCTAssertGreaterThanOrEqual(video.frame.width, app.frame.width - 3)
        XCTAssertEqual(playbackDocument.label, document, "Rotation must retain the provider document, not reload playback.")
        let options = app.buttons["sports-landscape-options"]
        XCTAssertTrue(wait { !options.exists }, "Idle landscape options should fade away and leave no invisible hit target.")
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.5)).tap()
        XCTAssertTrue(options.wait(for: \.isHittable, toEqual: true, timeout: 5), "A video touch should reveal options without intercepting the provider.")
        capture("Sports landscape video fills the canvas without portrait bars")
        options.tap()
        XCTAssertTrue(source.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertEqual(source.value as? String, selectedSource)
        XCTAssertGreaterThanOrEqual(video.frame.height, app.frame.height - 3, "Overlay controls must not reduce the video frame.")
        capture("Sports landscape selectors overlay the retained full size video")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait { self.app.frame.height > self.app.frame.width && source.isHittable })
        XCTAssertLessThan(video.frame.height, app.frame.height - 100)
        XCTAssertEqual(playbackDocument.label, document)
        XCTAssertEqual(source.value as? String, selectedSource)
        capture("Sports portrait rotation restores controls and the same stream")
    }

    func testPlayerChatSheetKeepsTheCurrentVideoDocumentMounted() {
        let source = openSportsPlayerOnBravo()
        let document = playbackDocument.label
        let selectedSource = source.value as? String
        let chat = app.buttons["sports-player-chat"]
        XCTAssertTrue(chat.isHittable); chat.tap()
        XCTAssertTrue(element("sports-chat").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What a game!"].waitForExistence(timeout: 5),
            "Chat in the separately hosted player must use the actual window scene's active state.")
        capture("Game chat sheet opens above the retained sports video")
        app.buttons["sports-chat-close"].tap()
        XCTAssertTrue(source.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertEqual(playbackDocument.label, document)
        XCTAssertEqual(source.value as? String, selectedSource)
    }

    func testSportsWatchAutoplaysReadyVideoAndPreservesAnExplicitPause() {
        _ = openSportsPlayerOnBravo()
        let document = playbackDocument.label
        XCTAssertTrue(app.staticTexts["Video playing"].waitForExistence(timeout: 12))
        app.buttons["Pause fixture video"].tap()
        XCTAssertTrue(app.staticTexts["Video paused"].waitForExistence(timeout: 5))
        let unwantedRestart = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.staticTexts["Video playing"].exists }, object: nil)
        unwantedRestart.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unwantedRestart], timeout: 3.2), .completed)
        XCTAssertEqual(playbackDocument.label, document)
        capture("Sports Watch starts the ready video once and respects Pause")
    }

    func testSportsBlocksPopupsWithoutInterceptingPlayerControls() {
        _ = openSportsPlayerOnBravo()
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].waitForExistence(timeout: 12))
        let document = playbackDocument.label
        let popup = app.webViews.buttons["Attempt popup"]
        XCTAssertTrue(popup.isHittable); popup.tap()
        XCTAssertTrue(app.webViews.staticTexts["Popup blocked"].waitForExistence(timeout: 5))
        assertSinglePlaybackSurface()
        XCTAssertEqual(playbackDocument.label, document,
            "Popup, hidden blank-target link and foreign top-frame redirect attempts must keep the selected sports document.")
        let quality = app.webViews.buttons["Provider quality"]
        XCTAssertTrue(quality.isHittable); quality.tap()
        XCTAssertTrue(app.webViews.staticTexts["Provider quality menu visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sports-player-close"].isHittable)
        capture("Blocked provider popup leaves the video and provider controls usable")
    }

    func testSportsFullscreenUsesTheProvidersOwnControlAndKeepsItsDocument() {
        let source = openSportsPlayerOnBravo()
        let selectedDocument = playbackDocument.label
        let selectedSource = source.value as? String
        XCTAssertFalse(app.buttons["sports-player-fullscreen"].exists,
            "Streamify must not add a second fullscreen button above the provider")
        XCTAssertFalse(app.buttons["sports-player-exit-fullscreen"].exists)
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].waitForExistence(timeout: 12))
        let inlineViewport = providerViewport()
        for cycle in 1...2 {
            let enter = app.webViews.buttons["Fullscreen"].firstMatch
            XCTAssertTrue(enter.isHittable)
            // One real tap on the existing JW-style control. Its original
            // handler requests native video fullscreen unless adapted.
            enter.tap()
            XCTAssertTrue(app.webViews.staticTexts["Provider fullscreen active"].waitForExistence(timeout: 10))
            XCTAssertTrue(wait { self.providerFullscreenWindow() != nil })
            guard let window = providerFullscreenWindow() else {
                XCTFail("The provider's real element fullscreen window disappeared")
                return
            }
            XCTAssertTrue(fillsScreen(window.frame))
            let viewport = providerViewport()
            XCTAssertGreaterThan(viewport.width * viewport.height,
                inlineViewport.width * inlineViewport.height * 1.08)
            XCTAssertTrue(app.webViews.staticTexts["Video inline, entries 0, exits 0"].firstMatch.exists,
                "The JW control must retain HTML controls instead of launching native AVKit")
            let quality = window.webViews.buttons["Provider quality"].firstMatch
            XCTAssertTrue(quality.isHittable)
            quality.tap()
            XCTAssertTrue(window.webViews.staticTexts["Provider quality menu visible"].firstMatch.exists,
                "The provider's own HTML controls must remain interactive in fullscreen")
            let exit = window.webViews.buttons["Exit Fullscreen"].firstMatch
            XCTAssertTrue(exit.isHittable)
            XCTAssertEqual(playbackDocument.label, selectedDocument)
            capture("Provider own fullscreen control keeps HTML controls cycle \(cycle)")
            exit.tap()
            XCTAssertTrue(app.webViews.staticTexts["Provider inline"].firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(wait { source.isHittable })
            XCTAssertEqual(source.value as? String, selectedSource)
            XCTAssertEqual(playbackDocument.label, selectedDocument)
            XCTAssertTrue(app.webViews.buttons["Fullscreen"].firstMatch.isHittable)
        }
        capture("Provider own control exits twice without native fullscreen or a reconnect")
        closeAndVerifySportsDoesNotReopen(source)
    }

    func testProviderElementFullscreenKeepsTheSameDocumentAndExitsNormally() {
        let source = openSportsPlayerOnBravo()
        let document = playbackDocument
        let selectedDocument = document.label
        let sourceValue = source.value as? String
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].waitForExistence(timeout: 12),
            "The fullscreen fixture must decode a real H264 video, not only a placeholder element")
        let inlineViewport = providerViewport()
        for cycle in 1...2 {
            let enter = app.webViews.buttons["Enter provider fullscreen"]
            XCTAssertTrue(enter.isHittable)
            enter.tap()
            let active = app.webViews.staticTexts["Provider fullscreen active"]
            XCTAssertTrue(active.waitForExistence(timeout: 10), "A real WebKit fullscreenchange must confirm entry")
            XCTAssertTrue(wait { self.providerFullscreenWindow() != nil },
                "WebKit must present the real fullscreen document in its own window above the sports header")
            guard let fullscreenWindow = providerFullscreenWindow() else {
                XCTFail("WebKit's fullscreen window disappeared before its exit could be exercised")
                return
            }
            let exit = fullscreenWindow.webViews.buttons["Exit provider fullscreen"].firstMatch
            XCTAssertTrue(exit.isHittable, "The presented fullscreen document must receive its own exit tap")
            XCTAssertTrue(fillsScreen(fullscreenWindow.frame))
            XCTAssertFalse(fullscreenWindow.buttons["sports-player-source-picker"].exists,
                "The fullscreen window must contain the video document rather than the app header")
            let fullscreenViewport = providerViewport()
            XCTAssertGreaterThan(fullscreenViewport.width * fullscreenViewport.height,
                inlineViewport.width * inlineViewport.height * 1.08,
                "The fullscreen document must gain viewport space, rather than changing only an icon")
            XCTAssertGreaterThanOrEqual(fullscreenViewport.width, min(app.frame.width, app.frame.height) - 8)
            XCTAssertGreaterThanOrEqual(fullscreenViewport.height, app.frame.height - 64)
            XCTAssertEqual(document.label, selectedDocument)
            capture("Actual provider element fullscreen cycle \(cycle) fills the viewport")
            exit.tap()
            XCTAssertTrue(app.webViews.staticTexts["Provider inline"].waitForExistence(timeout: 8))
            XCTAssertTrue(wait { source.isHittable })
            XCTAssertEqual(source.value as? String, sourceValue)
            XCTAssertEqual(document.label, selectedDocument, "Exiting must retain the selected stream document")
        }
        capture("Provider element fullscreen exits twice without reconnecting")
        closeAndVerifySportsDoesNotReopen(source)
    }

    func testProviderNativeVideoFullscreenPresentsAboveTheSportsWindowAndKeepsItsSource() {
        let source = openSportsPlayerOnBravo()
        let document = playbackDocument
        let selectedDocument = document.label
        let sourceValue = source.value as? String
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].waitForExistence(timeout: 12),
            "The browser must decode the bundled H264 media before its native fullscreen API runs")
        for cycle in 1...2 {
            let enter = app.webViews.buttons["Enter video fullscreen"]
            XCTAssertTrue(enter.isHittable)
            enter.tap()
            let entered = app.webViews.staticTexts["Video fullscreen, entries \(cycle), exits \(cycle - 1)"].firstMatch
            XCTAssertTrue(entered.waitForExistence(timeout: 12),
                "The real webkitbeginfullscreen event must confirm native video entry")
            let fullscreenWindow = nativeVideoFullscreenWindow
            XCTAssertTrue(fullscreenWindow.waitForExistence(timeout: 8),
                "WebKit's real AVKit video window must appear above the sports window")
            XCTAssertTrue(fillsScreen(fullscreenWindow.frame), "Native fullscreen must fill the actual device viewport")
            XCTAssertEqual(fullscreenWindow.buttons.matching(identifier: "sports-player-source-picker").count, 0)
            XCTAssertEqual(fullscreenWindow.webViews.count, 0, "This must be the native video window, not the HTML provider surface")
            let exit = nativeVideoFullscreenExit(in: fullscreenWindow)
            // AVKit hides transport controls automatically. Reveal them before
            // waiting for their accessibility nodes, not after a failed wait.
            if !exit.exists || !exit.isHittable {
                fullscreenWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            XCTAssertTrue(exit.waitForExistence(timeout: 8),
                "The system video fullscreen controller must expose its own exit control")
            XCTAssertTrue(exit.isHittable, "The system fullscreen controller must receive touches")
            capture("Native WebKit H264 fullscreen cycle \(cycle) is visible above the sports player")
            exit.tap()
            let inline = app.webViews.staticTexts["Video inline, entries \(cycle), exits \(cycle)"]
            XCTAssertTrue(inline.waitForExistence(timeout: 10),
                "Both real webkitbeginfullscreen and webkitendfullscreen events must fire")
            XCTAssertTrue(wait { source.isHittable })
            XCTAssertEqual(source.value as? String, sourceValue)
            XCTAssertEqual(document.label, selectedDocument, "Native fullscreen must preserve the actual WKWebView document")
        }
        capture("Native video fullscreen exits twice and retains the selected bravo source")
        closeAndVerifySportsDoesNotReopen(source)
    }

    func testProviderElementFullscreenBackgroundRestoreKeepsTheVideoSurfaceInteractive() {
        let source = openSportsPlayerOnBravo()
        let selectedDocument = playbackDocument.label
        let selectedSource = source.value as? String
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].waitForExistence(timeout: 12))
        app.webViews.buttons["Enter provider fullscreen"].tap()
        XCTAssertTrue(wait { self.providerFullscreenWindow() != nil })
        backgroundAndReturn()

        // On a PiP-capable device the system may retain its floating window
        // when the app icon is opened. Use the app's explicit restore action;
        // a simulator without PiP still exercises the real fullscreen handoff.
        let restore = app.buttons["sports-pip-restore"]
        if restore.exists && restore.isHittable { restore.tap() }
        XCTAssertTrue(wait(timeout: 5) {
            if let window = self.providerFullscreenWindow() {
                return window.webViews.buttons["Exit provider fullscreen"].firstMatch.isHittable
            }
            return source.isHittable && self.app.webViews.buttons["Enter provider fullscreen"].isHittable
        }, "Returning must expose the retained video controls promptly, not the app window's black fullscreen placeholder.")
        XCTAssertEqual(playbackDocument.label, selectedDocument, "Background/PiP restoration must not reconnect the selected stream.")
        if let window = providerFullscreenWindow() {
            XCTAssertTrue(fillsScreen(window.frame))
            window.webViews.buttons["Exit provider fullscreen"].firstMatch.tap()
        }
        XCTAssertTrue(app.webViews.staticTexts["Provider inline"].waitForExistence(timeout: 8))
        XCTAssertTrue(wait { source.isHittable })
        XCTAssertEqual(source.value as? String, selectedSource)
        XCTAssertEqual(playbackDocument.label, selectedDocument)

        // A real second entry/exit catches a stale black window that merely
        // happens to expose accessibility elements behind it on iOS 26.
        app.webViews.buttons["Enter provider fullscreen"].tap()
        XCTAssertTrue(wait { self.providerFullscreenWindow() != nil })
        guard let window = providerFullscreenWindow() else { return }
        let exit = window.webViews.buttons["Exit provider fullscreen"].firstMatch
        XCTAssertTrue(exit.isHittable)
        capture("Provider video remains interactive after fullscreen background restoration")
        exit.tap()
        XCTAssertTrue(app.webViews.staticTexts["Provider inline"].waitForExistence(timeout: 8))
        XCTAssertEqual(playbackDocument.label, selectedDocument)
        closeAndVerifySportsDoesNotReopen(source)
    }

    func testSwipeDownSportsPlayerCancelsWithoutReloadingThenReturnsToItsGameCard() {
        let source = openSportsPlayerOnBravo()
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].waitForExistence(timeout: 12))
        let document = playbackDocument
        let selectedDocument = document.label
        let sourceValue = source.value as? String
        let sourceFrame = source.frame
        let leftStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.32))
        let leftEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.32))
        leftStart.press(forDuration: 0.05, thenDragTo: leftEnd, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(source.isHittable, "A horizontal swipe must leave the sports player open")
        XCTAssertEqual(document.label, selectedDocument)
        let partialStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let partialEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.39))
        partialStart.press(forDuration: 0.05, thenDragTo: partialEnd, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(wait { source.isHittable && abs(source.frame.minY - sourceFrame.minY) < 2 && abs(source.frame.minX - sourceFrame.minX) < 2 },
            "A short pull must spring the existing player back to its full-size position")
        XCTAssertEqual(source.value as? String, sourceValue)
        XCTAssertEqual(document.label, selectedDocument, "Cancelling must keep the selected WebKit video document alive")
        XCTAssertTrue(app.webViews.staticTexts["Bundled H264 video ready"].exists)
        capture("Cancelled sports card pull restores the same bravo video document")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait { !source.exists }, "A committed downward pull must close the sports player")
        let watch = app.buttons["Watch BOS vs TOR"].firstMatch
        XCTAssertTrue(watch.waitForExistence(timeout: 8))
        XCTAssertTrue(watch.isHittable, "Dismissing should return to the originating visible game card")
        capture("Committed sports pull returns to the original game card")
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        let reopened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in source.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 3), .timedOut,
            "A drag-dismissed player must not reopen when returning to Sports")
        XCTAssertEqual(app.buttons["Watch BOS vs TOR"].firstMatch.exists, true)
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

    private var playbackDocument: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '")).firstMatch
    }

    private func assertSinglePlaybackSurface(file: StaticString = #filePath, line: UInt = #line) {
        // iOS 26 exposes a WKWebView as three nested WebView accessibility
        // wrappers. Count its document leaf, not those ancestor wrappers. A
        // second provider surface would have another leaf and fixture marker.
        let documents = app.webViews.allElementsBoundByIndex.filter {
            $0.descendants(matching: .webView).count == 0
        }
        XCTAssertEqual(documents.count, 1, "Only one provider document may be mounted.", file: file, line: line)
        let markers = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Playback session '"))
        XCTAssertEqual(markers.count, 1, "Only one fixture playback session may be mounted.", file: file, line: line)
    }

    /// Switch before fullscreen so a document reconnect cannot pass by silently
    /// returning to the default alpha source.
    private func openSportsPlayerOnBravo(viaWatchLink: Bool = false) -> XCUIElement {
        if viaWatchLink {
            // Exercise the same retained player through the Lock Screen Watch
            // route. Other tests independently exercise the schedule Watch tap.
            app.open(URL(string: "streamify://sports/watch?league=nba&event=401020304")!)
        } else {
            app.buttons["tab-sports"].tap()
            selectNBA()
            let watch = app.buttons["Watch BOS vs TOR"].firstMatch
            reveal(watch)
            XCTAssertTrue(watch.isHittable)
            watch.tap()
        }
        let source = app.buttons["sports-player-source-picker"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        // A fresh simulator may need extra time to launch its first WebContent
        // process. This wait is only initial setup; fullscreen still gets one tap
        // and its normal deadlines, with no app reload or automatic retry.
        XCTAssertTrue(playbackDocument.waitForExistence(timeout: 30))
        let alphaDocument = playbackDocument.label
        source.tap()
        XCTAssertTrue(app.buttons["sports-player-source-option-1"].waitForExistence(timeout: 5))
        app.buttons["sports-player-source-option-1"].tap()
        XCTAssertTrue(wait { (source.value as? String ?? "").contains("bravo") })
        XCTAssertTrue(wait { self.playbackDocument.exists && self.playbackDocument.label != alphaDocument })
        return source
    }

    private func providerViewport() -> CGSize {
        let viewport = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Provider viewport '")).firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let dimensions = viewport.label.replacingOccurrences(of: "Provider viewport ", with: "").components(separatedBy: " by ")
        guard dimensions.count == 2, let width = Double(dimensions[0]), let height = Double(dimensions[1]) else {
            XCTFail("The real WebKit viewport must report numeric dimensions: \(viewport.label)")
            return .zero
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    private func providerFullscreenWindow() -> XCUIElement? {
        // iOS can expose the retained web document under multiple windows.
        // Repeatedly querying absent covered-header controls is slow enough to
        // exhaust the polling deadline. Identify the positive DOM status in one
        // snapshot; callers also verify viewport growth and working HTML controls.
        let window = app.windows.containing(.staticText, identifier: "Provider fullscreen active").firstMatch
        return window.exists ? window : nil
    }

    private var nativeVideoFullscreenWindow: XCUIElement {
        // Query the positive native Media descendant in one snapshot. Scanning
        // every window and waiting for absent app controls can exhaust the
        // polling deadline even while AVKit is visibly presenting its video.
        // The caller separately verifies size and absence of WebView/app chrome.
        app.windows.containing(.other, identifier: "Media").firstMatch
    }

    private func fillsScreen(_ frame: CGRect) -> Bool {
        abs(frame.minX - app.frame.minX) < 8 && abs(frame.minY - app.frame.minY) < 8 &&
            frame.width >= app.frame.width - 8 && frame.height >= app.frame.height - 8
    }

    private func nativeVideoFullscreenExit(in window: XCUIElement) -> XCUIElement {
        // AVKit varies this localized English label across supported iOS versions.
        // These are native controls; the fixture's DOM exit is deliberately excluded.
        window.buttons.matching(NSPredicate(format: "label IN %@",
            ["Done", "Close", "Exit Full Screen", "Exit Fullscreen", "Exit fullscreen", "Minimize", "Collapse Video", "Collapse video"])).firstMatch
    }

    private func closeAndVerifySportsDoesNotReopen(_ source: XCUIElement) {
        app.buttons["Close player"].tap()
        XCTAssertTrue(wait { !source.exists })
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["tab-home"].isSelected)
        app.buttons["tab-sports"].tap()
        XCTAssertTrue(app.buttons["tab-sports"].isSelected)
        let reopened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in source.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 3), .timedOut,
            "A finished fullscreen session must stay closed after switching tabs")
    }

    private func selectNBA() {
        let option = app.buttons["sports-league-option-nba"]
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
        XCTAssertTrue(wait { option.isSelected })
        XCTAssertTrue(app.buttons["sports-quick-live"].isSelected)
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
