import XCTest

/// Every launch uses local fixtures. These tests never configure Firebase,
/// create anonymous accounts, or publish messages to a real chat room.
final class SportsChatFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        if name.contains("testChatConnectionTimeout") { app.launchArguments.append("--ui-chat-stalled-fixture") }
        if name.contains("testSendingKeepsKeyboard") { app.launchArguments.append("--ui-chat-delayed-send-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["tab-sports"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("FAILURE local guest chat")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "FAILURE guest chat hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        app?.terminate()
    }

    func testSendingKeepsKeyboardFocusedWhileTheServerAcknowledges() {
        openChat()
        let composer = element("sports-chat-composer")
        reveal(composer); composer.tap(); composer.typeText("First update")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["sports-chat-send"].tap()
        for _ in 0..<6 {
            XCTAssertTrue(composer.isEnabled, "The editor must remain enabled while sending")
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Sending must not dismiss and reopen the keyboard")
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", ": First update")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { (composer.value as? String ?? "") != "First update" })
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        composer.typeText("Next update")
        XCTAssertEqual(composer.value as? String, "Next update")
        capture("Keyboard remains visible and ready for the next message after sending")
    }

    func testGuestCanReadReplyAndSendLocallyWhileReactionPermissionFailureIsVisible() {
        openChat()
        let firstReply = element("sports-chat-body-fixture-chat-1")
        reveal(firstReply)
        XCTAssertTrue(firstReply.isHittable)
        XCTAssertTrue(app.staticTexts["sports-chat-body-fixture-chat-1"].exists)
        capture("Guest chat reads the shared matchup without a sign-in gate")
        messageAction("Reply")
        let composer = element("sports-chat-composer")
        reveal(composer)
        XCTAssertTrue(app.staticTexts["Replying to Guest 2048"].exists)
        composer.tap(); composer.typeText("Great defense!")
        let send = app.buttons["sports-chat-send"]
        reveal(send)
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", ": Great defense!")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { (composer.value as? String ?? "") != "Great defense!" })
        XCTAssertFalse(app.staticTexts["Replying to Guest 2048"].exists)
        capture("Local guest reply keeps its quoted message and receives a guest identity")
        // Dismiss the keyboard without sending another message.
        dismissKeyboard()
        openMessageOptions()
        let fire = app.buttons["🔥"].firstMatch
        XCTAssertTrue(fire.waitForExistence(timeout: 5)); fire.tap()
        let error = element("sports-chat-action-error")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        reveal(error)
        XCTAssertTrue(app.staticTexts["Missing or insufficient permissions."].exists,
            "The local rule fixture must surface rejected updates rather than invent reaction success")
        XCTAssertTrue(app.buttons["Retry"].exists)
        capture("Guest chat shows the real reaction permission failure and Retry")
    }

    func testChatConnectionTimeoutOffersRetryAndAnIconCloseButton() {
        openChat()
        let close = app.buttons["sports-chat-close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.label, "Close chat")
        let failure = app.staticTexts["Chat isn’t responding. Check your connection and try again."]
        XCTAssertTrue(failure.waitForExistence(timeout: 18))
        XCTAssertFalse(app.staticTexts["Connecting to chat…"].exists)
        capture("Chat timeout has a clear close icon and an actionable retry")
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.isHittable); retry.tap()
        XCTAssertTrue(app.staticTexts["sports-chat-body-fixture-chat-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(failure.exists)
        capture("Chat retry recovers without signing in or changing the game")
        close.tap()
        XCTAssertTrue(app.navigationBars["Game center"].waitForExistence(timeout: 5))
    }

    func testGuestComposerEnforcesTheThousandCharacterLimitBeforeSend() {
        openChat()
        let composer = element("sports-chat-composer")
        reveal(composer); composer.tap()
        composer.typeText(String(repeating: "a", count: 1001))
        // UIKit abbreviates the accessibility value of long multi-line fields.
        // Check the bound draft counter and that the actual send contract accepts it.
        XCTAssertTrue(app.staticTexts["1,000/1,000"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sports-chat-send"].isEnabled)
        app.buttons["sports-chat-send"].tap()
        XCTAssertTrue(wait { (composer.value as? String ?? "") == "Say something…" || (composer.value as? String ?? "").isEmpty })
        XCTAssertFalse(element("sports-chat-action-error").exists)
        capture("Guest composer caps the bound draft and sends within the thousand character contract")
    }

    func testReplyPreviewCancelAndQuotedMessageNavigationKeepDraft() {
        openChat()
        messageAction("Reply")
        let composer = element("sports-chat-composer")
        XCTAssertTrue(element("sports-chat-reply-preview").exists)
        composer.tap(); composer.typeText("Nice play!")
        app.buttons["Cancel reply"].tap()
        XCTAssertFalse(element("sports-chat-reply-preview").exists)
        XCTAssertEqual(composer.value as? String, "Nice play!")
        dismissKeyboard()
        messageAction("Reply")
        capture("Compact reply composer preserves the draft")
        app.buttons["sports-chat-send"].tap()
        let quote = app.buttons["View reply to Guest 2048"]
        XCTAssertTrue(quote.waitForExistence(timeout: 5))
        XCTAssertFalse(element("sports-chat-reply-preview").exists)
        quote.tap()
        XCTAssertTrue(wait { self.element("sports-chat-message-fixture-chat-1").isHittable })
        capture("Sent quote returns to its original message")
    }

    func testStatusCountsRespectTheSelectedLeagueWithoutChangingStatus() {
        app.buttons["tab-sports"].tap()
        let live = app.buttons["sports-quick-live"]
        XCTAssertTrue(wait { (live.value as? String ?? "").hasPrefix("6 games") })
        app.buttons["sports-league-option-nhl"].tap()
        XCTAssertTrue(wait { (live.value as? String ?? "").hasPrefix("1 games") })
        XCTAssertTrue((app.buttons["sports-filter-Pregame"].value as? String ?? "").hasPrefix("0 games"))
        XCTAssertTrue((app.buttons["sports-filter-Upcoming"].value as? String ?? "").hasPrefix("0 games"))
        app.scrollViews["sports-status-tabs"].swipeLeft()
        app.buttons["sports-filter-Final"].tap()
        XCTAssertTrue((live.value as? String ?? "").hasPrefix("1 games"), "Choosing a status must not recount only its visible cards")
        capture("Live Pregame and Final counts remain scoped to the selected league")
    }
    private var options: XCUIElement { app.descendants(matching: .popover).firstMatch }
    private func openMessageOptions() {
        let row = element("sports-chat-body-fixture-chat-1")
        reveal(row); row.press(forDuration: 0.6)
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertTrue(options.buttons.matching(NSPredicate(format: "label == %@", "Copy text")).firstMatch.waitForExistence(timeout: 5))
    }
    private func messageAction(_ action: String) {
        openMessageOptions()
        // SwiftUI propagates the popover container identifier to its buttons.
        // Scope by the visible action label inside the actual popover.
        options.buttons.matching(NSPredicate(format: "label == %@", action)).firstMatch.tap()
    }

    private func openChat() {
        app.buttons["tab-sports"].tap()
        app.buttons["sports-league-option-nhl"].tap()
        let center = app.buttons["sports-game-nhl:nhl-fixture"]
        XCTAssertTrue(center.waitForExistence(timeout: 8))
        center.tap()
        XCTAssertTrue(app.navigationBars["Game center"].waitForExistence(timeout: 8))
        let overview = app.buttons["sports-game-tab-Overview"]
        reveal(overview)
        let chat = app.buttons["sports-game-tab-Chat"]
        for _ in 0..<4 where !chat.isHittable {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let y = overview.frame.midY - app.frame.minY
            origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.15, dy: y)))
        }
        XCTAssertTrue(chat.isHittable); chat.tap()
        XCTAssertTrue(element("sports-chat").waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Game chat"].exists)
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
    }
    private func reveal(_ target: XCUIElement) {
        if target.exists {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in target.isHittable }, object: nil)
            if XCTWaiter.wait(for: [ready], timeout: 2) == .completed { return }
        }
        for _ in 0..<8 {
            if target.exists && target.isHittable { return }
            let thread = app.scrollViews["sports-chat-thread"]
            let surface = thread.exists ? thread : app.reviewScrollSurface
            let up = !target.exists || target.frame.midY > surface.frame.midY
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.65 : 0.35))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.35 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    private func dismissKeyboard() {
        let keyboardTip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Speed up your typing'")).firstMatch
        if keyboardTip.exists { app.buttons["Continue"].tap() }
        guard app.keyboards.firstMatch.exists else { return }
        // Pulling down at the top is the sheet's deliberate close gesture.
        // Opening and dismissing message options resigns the composer without closing chat.
        openMessageOptions()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        XCTAssertTrue(options.waitForNonExistence(timeout: 5))
        XCTAssertTrue(wait { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(element("sports-chat").exists)
    }
}
