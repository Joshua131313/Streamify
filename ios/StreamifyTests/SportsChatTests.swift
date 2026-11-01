import XCTest
import Combine
@testable import Streamify

@MainActor final class SportsChatTests: XCTestCase {
    func testInactiveChatDoesNotSpinAndBecomesConnectedWhenItsActualSceneActivates() {
        let backend = ChatBackendFixture()
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: false)
        XCTAssertFalse(chat.loading)
        XCTAssertEqual(backend.listens, 0)
        chat.listen(room: "BOS-TOR", active: true)
        XCTAssertTrue(chat.loading)
        backend.callbacks[0](.success([sample("connected")]))
        XCTAssertFalse(chat.loading)
        XCTAssertEqual(chat.messages.first?.id, "connected")
    }

    func testSilentChatConnectionTimesOutPreservesDraftAndCanRecoverOrRetry() async {
        let backend = ChatBackendFixture()
        let chat = SportsChatStore(backend: backend, initialResponseTimeout: .milliseconds(20))
        chat.listen(room: "BOS-TOR", active: true)
        chat.draft = "Keep my message"
        let timedOut = expectation(description: "The silent listener stops the spinner")
        let observation = chat.$error.compactMap { $0 }.first().sink { _ in timedOut.fulfill() }
        await fulfillment(of: [timedOut], timeout: 2)
        observation.cancel()
        XCTAssertFalse(chat.loading)
        XCTAssertEqual(chat.error, SportsChatError.connectionTimedOut.localizedDescription)
        XCTAssertEqual(chat.draft, "Keep my message")
        backend.callbacks[0](.success([sample("late-server")]))
        XCTAssertNil(chat.error)
        XCTAssertEqual(chat.messages.first?.id, "late-server")
        chat.listen(room: "BOS-TOR", active: true)
        backend.callbacks[1](.success([sample("retry")]))
        XCTAssertEqual(chat.draft, "Keep my message")
        XCTAssertEqual(chat.messages.first?.id, "retry")
        XCTAssertEqual(backend.sends, 0)
    }
    func testRoomsMatchAndroidAwayHomeAliasesWithoutLeagueOrDatePrefix() {
        XCTAssertEqual(SportsChatContract.room(league: .nba, away: "GSW", home: "NYK"), "GS-NY")
        XCTAssertEqual(SportsChatContract.room(league: .nba, away: "UTA", home: "NOP"), "UTAH-NO")
        XCTAssertEqual(SportsChatContract.room(league: .nhl, away: "LAK", home: "NJD"), "LA-NJ")
        XCTAssertEqual(SportsChatContract.room(league: .nhl, away: "UTAH", home: "TBL"), "UTA-TB")
        XCTAssertEqual(SportsChatContract.room(league: .mlb, away: "CWS", home: "WSN"), "CHW-WSH")
        XCTAssertEqual(SportsChatContract.room(league: .mlb, away: "OAK", home: "NYY"), "ATH-NYY")
        XCTAssertEqual(SportsChatContract.room(league: .ncaaf, away: "ala", home: "LSU"), "ALA-LSU")
        XCTAssertNil(SportsChatContract.room(league: .nba, away: "BOS/TOR", home: "NYK"))
        XCTAssertNil(SportsChatContract.room(league: .nba, away: "", home: "NYK"))
        XCTAssertEqual(SportsChatContract.guestName(uid: "abcdefgh1234"), "Guest 1234")
    }

    func testMessageLimitUsesAndroidUTF16LengthWithoutSplittingEmoji() throws {
        XCTAssertEqual(try SportsChatContract.message("  Good game!\n"), "Good game!")
        XCTAssertNoThrow(try SportsChatContract.message(String(repeating: "🔥", count: 500)))
        XCTAssertThrowsError(try SportsChatContract.message(String(repeating: "🔥", count: 501)))
        XCTAssertThrowsError(try SportsChatContract.message(" \n "))
        let limited = SportsChatContract.limitDraft(String(repeating: "🔥", count: 501))
        XCTAssertEqual(limited, String(repeating: "🔥", count: 500))
        XCTAssertEqual(limited.utf16.count, 1000)
    }

    func testParserKeepsRepliesPendingTimestampsAndOnlySupportedVotes() throws {
        let data: [String: Any] = ["message": "Great defense", "senderName": "Guest 1234", "senderId": "user1234",
            "replyTo": ["id": "previous", "sender": "Viewer", "message": "Close game"],
            "reactionVotes": ["fan1": "🔥", "fan2": "unrecognized", "fan3": "👍"]]
        let parsed = try XCTUnwrap(SportsChatMessage.parse(id: "message", data: data, sentAt: nil, pending: true))
        XCTAssertTrue(parsed.pending)
        XCTAssertNil(parsed.sentAt)
        XCTAssertEqual(parsed.reply, SportsChatReply(id: "previous", sender: "Viewer", message: "Close game"))
        XCTAssertEqual(parsed.votes, ["fan1": "🔥", "fan3": "👍"])
        XCTAssertEqual(parsed.handle, "guest1234_1234")
        XCTAssertNil(SportsChatMessage.parse(id: "bad/path", data: data, sentAt: nil))
        XCTAssertNil(SportsChatMessage.parse(id: "message", data: ["message": String(repeating: "x", count: 1001)], sentAt: nil))
    }

    func testReadingNeverSendsAndRoomOrSceneChangesRemoveListenerAndIgnoreOldCallbacks() {
        let backend = ChatBackendFixture()
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true)
        XCTAssertEqual(backend.listens, 1)
        XCTAssertEqual(backend.sends, 0)
        XCTAssertNil(backend.currentUserID)
        chat.listen(room: "BOS-TOR", active: false)
        XCTAssertEqual(backend.removals, 1)
        chat.listen(room: "GS-NY", active: true)
        backend.callbacks[0](.success([sample("stale")]))
        XCTAssertTrue(chat.messages.isEmpty)
        backend.callbacks[1](.success([sample("current")]))
        XCTAssertEqual(chat.messages.map(\.id), ["current"])
        XCTAssertEqual(backend.sends, 0)
    }

    func testFailedSendKeepsItsMessageAndReplyInTheOutboxUntilRetry() async {
        let backend = ChatBackendFixture()
        let store = SportsChatStore(backend: backend)
        store.listen(room: "BOS-TOR", active: true)
        store.draft = "Go team!"; store.reply = sample("quote").quote
        backend.failure = SportsChatError.signInUnavailable
        await store.send()
        XCTAssertEqual(backend.sends, 1)
        XCTAssertEqual(store.draft, "")
        XCTAssertNil(store.reply)
        XCTAssertEqual(store.messages.first?.text, "Go team!")
        XCTAssertEqual(store.messages.first?.reply?.id, "quote")
        XCTAssertNotNil(store.messages.first?.deliveryError)
        let failedID = store.messages.first?.id
        XCTAssertNotNil(store.actionError)
        XCTAssertFalse(store.sending)
        backend.failure = nil
        await store.retryAction()
        XCTAssertEqual(backend.sends, 2)
        XCTAssertEqual(backend.lastRoom, "BOS-TOR")
        XCTAssertEqual(backend.lastReply?.id, "quote")
        XCTAssertEqual(backend.lastMessageID, failedID)
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.draft, "")
        XCTAssertNil(store.reply)
        XCTAssertNil(store.actionError)
    }

    func testDuplicateSendIsIgnoredAndOldCompletionDoesNotClearNewRoomComposer() async {
        let backend = ChatBackendFixture()
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true); chat.draft = "First room"
        backend.suspend = true
        let first = Task { await chat.send() }
        for _ in 0..<20 { if backend.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(backend.continuation)
        XCTAssertTrue(chat.sending)
        await chat.send()
        XCTAssertEqual(backend.sends, 1)
        chat.listen(room: "GS-NY", active: true); chat.draft = "New room"
        backend.continuation?.resume(); backend.continuation = nil
        await first.value
        XCTAssertEqual(chat.draft, "New room")
        XCTAssertFalse(chat.sending)
    }

    func testPendingSendPreservesANewlySelectedReply() async {
        let backend = ChatBackendFixture()
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true)
        chat.draft = "First reply"; chat.reply = sample("first").quote
        backend.suspend = true
        let send = Task { await chat.send() }
        for _ in 0..<20 { if backend.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(backend.continuation)
        chat.reply = sample("next").quote
        backend.continuation?.resume(); backend.continuation = nil
        await send.value
        XCTAssertEqual(backend.lastReply?.id, "first")
        XCTAssertEqual(chat.draft, "")
        XCTAssertEqual(chat.reply?.id, "next")
    }

    func testPendingSendPreservesANewMentionAndReply() async {
        let backend = ChatBackendFixture()
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true)
        chat.draft = "First message"; chat.reply = sample("first").quote
        backend.suspend = true
        let send = Task { await chat.send() }
        for _ in 0..<20 { if backend.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(backend.continuation)
        chat.draft = "@nextfan "
        chat.reply = sample("next").quote
        backend.continuation?.resume(); backend.continuation = nil
        await send.value
        XCTAssertEqual(chat.draft, "@nextfan ")
        XCTAssertEqual(chat.reply?.id, "next")
    }

    func testRejectedReactionRollsBackVotesAndReportsTheFailure() async {
        let backend = ChatBackendFixture()
        let store = SportsChatStore(backend: backend)
        store.listen(room: "BOS-TOR", active: true)
        backend.callbacks[0](.success([sample("message")]))
        backend.failure = NSError(domain: "FIRFirestoreErrorDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."])
        await store.react(messageID: "message", emoji: "🔥")
        XCTAssertEqual(store.messages.first?.votes, [:])
        XCTAssertEqual(store.actionError, "Missing or insufficient permissions.")
        XCTAssertEqual(backend.sends, 0, "React must never silently create a guest account via Send")
    }

    func testMessageAppearsBeforeDeliveryAndItsServerEchoDoesNotDuplicateIt() async {
        let backend = ChatBackendFixture()
        backend.currentUserID = "guest1234"; backend.suspend = true
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true)
        backend.callbacks[0](.success([]))
        chat.draft = "Instant reply"; chat.reply = sample("quote").quote
        let send = Task { await chat.send() }
        for _ in 0..<100 { if backend.continuation != nil { break }; await Task.yield() }
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages.first?.text, "Instant reply")
        XCTAssertEqual(chat.messages.first?.reply?.id, "quote")
        XCTAssertTrue(chat.messages.first?.pending == true)
        XCTAssertEqual(chat.draft, ""); XCTAssertNil(chat.reply)
        guard let local = chat.messages.first else { backend.continuation?.resume(); await send.value; return }
        // The listener can report a pending write, then its server echo, before send returns.
        backend.callbacks[0](.success([local]))
        XCTAssertEqual(chat.messages.count, 1)
        backend.callbacks[0](.success([local.delivery(pending: false)]))
        backend.continuation?.resume(); backend.continuation = nil
        await send.value
        XCTAssertEqual(chat.messages.map(\.id), [local.id])
        XCTAssertFalse(chat.messages[0].pending)
        backend.callbacks[0](.success([local.delivery(pending: false)]))
        XCTAssertEqual(chat.messages.count, 1)
    }

    func testOptimisticReactionSurvivesOldSnapshotsAndRollsBackOnFailure() async {
        let backend = ChatBackendFixture()
        backend.currentUserID = "guest1234"; backend.suspendReactions = true
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true)
        backend.callbacks[0](.success([sample("message")]))
        let reaction = Task { await chat.react(messageID: "message", emoji: "🔥") }
        for _ in 0..<100 { if backend.reactionContinuation != nil { break }; await Task.yield() }
        XCTAssertEqual(chat.messages[0].votes["guest1234"], "🔥")
        backend.callbacks[0](.success([sample("message")]))
        XCTAssertEqual(chat.messages[0].votes["guest1234"], "🔥")
        backend.failure = SportsChatError.invalidReaction
        backend.reactionContinuation?.resume(); backend.reactionContinuation = nil
        await reaction.value
        XCTAssertNil(chat.messages[0].votes["guest1234"])
        XCTAssertNotNil(chat.actionError)
    }

    func testNewReactionTapWinsOverAnOlderCompletionAndConfirmedRemoval() async {
        let backend = ChatBackendFixture()
        backend.currentUserID = "guest1234"; backend.suspendReactions = true
        let chat = SportsChatStore(backend: backend)
        chat.listen(room: "BOS-TOR", active: true)
        backend.callbacks[0](.success([sample("message")]))
        let first = Task { await chat.react(messageID: "message", emoji: "🔥") }
        for _ in 0..<100 { if backend.reactionContinuation != nil { break }; await Task.yield() }
        await chat.react(messageID: "message", emoji: "❤️")
        XCTAssertEqual(chat.messages[0].votes["guest1234"], "❤️")
        backend.suspendReactions = false
        backend.reactionContinuation?.resume(); backend.reactionContinuation = nil
        await first.value
        XCTAssertEqual(backend.reactionCalls.map(\.emoji), ["🔥", "❤️"])
        XCTAssertEqual(chat.messages[0].votes["guest1234"], "❤️")
        var confirmed = sample("message"); confirmed.votes = ["guest1234": "❤️"]
        backend.callbacks[0](.success([confirmed]))
        await chat.react(messageID: "message", emoji: "❤️")
        XCTAssertNil(backend.reactionCalls.last?.emoji)
        XCTAssertNil(chat.messages[0].votes["guest1234"])
        backend.callbacks[0](.success([confirmed]))
        XCTAssertNil(chat.messages[0].votes["guest1234"], "A stale snapshot cannot restore a removed reaction")
        backend.callbacks[0](.success([sample("message")]))
        XCTAssertNil(chat.messages[0].votes["guest1234"])
    }

    private func sample(_ id: String) -> SportsChatMessage {
        SportsChatMessage(id: id, text: "Good game", sender: "Guest 1234", uid: "guest1234", sentAt: nil, reply: nil, votes: [:], pending: false)
    }
}

@MainActor private final class ChatBackendFixture: SportsChatBackend {
    var currentUserID: String?
    var callbacks: [(Result<[SportsChatMessage], Error>) -> Void] = []
    var listens = 0, removals = 0, sends = 0
    var lastRoom: String?, lastReply: SportsChatReply?, lastMessageID: String?
    var failure: Error?
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    var suspendReactions = false
    var reactionContinuation: CheckedContinuation<Void, Never>?
    var reactionCalls: [(id: String, emoji: String?)] = []
    func listen(room: String, receive: @escaping (Result<[SportsChatMessage], Error>) -> Void) throws -> SportsChatSubscription {
        listens += 1; callbacks.append(receive)
        return SportsChatSubscription { [weak self] in self?.removals += 1 }
    }
    func send(room: String, messageID: String, text: String, reply: SportsChatReply?) async throws {
        sends += 1; lastRoom = room; lastReply = reply; lastMessageID = messageID
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        currentUserID = "guest1234"
    }
    func react(room: String, messageID: String, emoji: String?) async throws {
        reactionCalls.append((messageID, emoji))
        if suspendReactions { await withCheckedContinuation { reactionContinuation = $0 } }
        if let failure { throw failure }
    }
}
