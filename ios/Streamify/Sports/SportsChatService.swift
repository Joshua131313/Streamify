import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

enum SportsChatBootstrap {
    @MainActor static func configure() {
        #if DEBUG
        if PreviewFixtures.enabled || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil { return }
        #endif
        guard FirebaseApp.app() == nil,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else { return }
        FirebaseApp.configure(options: options)
    }
}

enum SportsChatContract {
    static let reactions = ["👍", "❤️", "😂", "🔥", "👏"]
    static func abbreviation(_ value: String, league: SportsLeague) -> String {
        let value = value.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let aliases: [String: String]
        switch league {
        case .nhl: aliases = ["LAK": "LA", "NJD": "NJ", "SJS": "SJ", "TBL": "TB", "UTAH": "UTA"]
        case .mlb: aliases = ["CWS": "CHW", "WSN": "WSH", "OAK": "ATH"]
        case .nba: aliases = ["NYK": "NY", "GSW": "GS", "SAS": "SA", "NOP": "NO", "UTA": "UTAH"]
        default: aliases = [:]
        }
        return aliases[value] ?? value
    }
    static func room(league: SportsLeague, away: String, home: String) -> String? {
        let away = abbreviation(away, league: league), home = abbreviation(home, league: league)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard [away, home].allSatisfy({ !$0.isEmpty && $0.utf16.count <= 24 && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return "\(away)-\(home)"
    }
    static func validRoom(_ room: String) -> Bool { !room.isEmpty && room.utf16.count <= 100 && !room.contains("/") }
    static func message(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf16.count <= 1000 else { throw SportsChatError.invalidMessage }
        return value
    }
    static func limitDraft(_ text: String) -> String {
        limit(text, utf16Count: 1000)
    }
    static func limit(_ text: String, utf16Count: Int) -> String {
        var value = String(text.prefix(utf16Count))
        while value.utf16.count > utf16Count { value.removeLast() }
        return value
    }
    // Stable FNV-1a over UTF-8, shared with Android username colors.
    static func identityHash(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
    }
    static func guestName(uid: String) -> String { "Guest \(uid.suffix(4))" }
    static func nameColorHex(_ name: String, light: Bool = false) -> String {
        let colors = light
            ? ["#a62743","#925014","#796100","#416817","#14694e","#096979","#315ca8","#7045a0","#934394","#a33e70"]
            : ["#ff929b","#f3b278","#f3d87a","#b5dc83","#7ed5b0","#78d3de","#9ebcff","#c2a6ff","#e5a0ef","#f2a9cc"]
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
        return colors[Int(identityHash("color:" + normalized)) % colors.count]
    }
}

struct SportsChatReply: Equatable, Sendable {
    let id: String
    let sender: String
    let message: String
}

struct SportsChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let sender: String
    let uid: String
    let sentAt: Date?
    let reply: SportsChatReply?
    var votes: [String: String]
    let pending: Bool
    var deliveryError: String? = nil

    func delivery(pending: Bool, error: String? = nil) -> Self {
        var value = Self(id: id, text: text, sender: sender, uid: uid, sentAt: sentAt, reply: reply, votes: votes, pending: pending)
        value.deliveryError = error
        return value
    }

    var quote: SportsChatReply { SportsChatReply(id: id, sender: sender, message: text) }
    var handle: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        let name = sender.lowercased().unicodeScalars.filter(allowed.contains).prefix(24).map { String($0) }.joined()
        return "\(name.isEmpty ? "fan" : name)_\(uid.suffix(4))"
    }
    static func parse(id: String, data: [String: Any], sentAt: Date?, pending: Bool = false) -> Self? {
        guard !id.isEmpty, !id.contains("/"), id.utf16.count <= 150,
              let text = data["message"] as? String, text.utf16.count <= 1000,
              (try? SportsChatContract.message(text)) != nil else { return nil }
        let rawName = (data["senderName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = rawName.isEmpty ? "Viewer" : SportsChatContract.limit(rawName, utf16Count: 160)
        let uid = String((data["senderId"] as? String ?? "").prefix(256))
        var reply: SportsChatReply?
        if let value = data["replyTo"] as? [String: Any], let id = value["id"] as? String,
           !id.isEmpty, !id.contains("/"), id.utf16.count <= 150,
           let sender = value["sender"] as? String, let message = value["message"] as? String,
           sender.utf16.count <= 160, message.utf16.count <= 1000 {
            reply = SportsChatReply(id: id, sender: sender, message: message)
        }
        let votes = (data["reactionVotes"] as? [String: String] ?? [:]).filter {
            !$0.key.isEmpty && $0.key.count <= 256 && SportsChatContract.reactions.contains($0.value)
        }
        return Self(id: id, text: text, sender: sender, uid: uid, sentAt: sentAt, reply: reply, votes: votes, pending: pending)
    }
}

enum SportsChatError: LocalizedError {
    case invalidMessage, unavailable, invalidRoom, signInUnavailable, accountChanged, reactionNeedsGuest, invalidReaction, connectionTimedOut
    var errorDescription: String? {
        switch self {
        case .invalidMessage: return "Use between 1 and 1,000 characters."
        case .unavailable: return "Chat is unavailable in this build. Please try again after updating Streamify."
        case .invalidRoom: return "Chat is unavailable for this matchup."
        case .signInUnavailable: return "Guest chat is unavailable. Please try again."
        case .accountChanged: return "Your chat session changed. Please try again."
        case .reactionNeedsGuest: return "Send a message to join guest chat before adding a reaction."
        case .invalidReaction: return "This reaction could not be added."
        case .connectionTimedOut: return "Chat isn’t responding. Check your connection and try again."
        }
    }
}

/// Owns only a listener cancellation closure, so deinit cleanup needs no actor hop.
final class SportsChatSubscription {
    private var cancellation: (() -> Void)?
    init(_ cancellation: @escaping () -> Void) { self.cancellation = cancellation }
    func remove() { cancellation?(); cancellation = nil }
    deinit { cancellation?() }
}

@MainActor protocol SportsChatBackend: AnyObject {
    var currentUserID: String? { get }
    func listen(room: String, receive: @escaping (Result<[SportsChatMessage], Error>) -> Void) throws -> SportsChatSubscription
    var currentSenderName: String { get }
    func send(room: String, messageID: String, text: String, reply: SportsChatReply?) async throws
    func react(room: String, messageID: String, emoji: String?) async throws
}

extension SportsChatBackend {
    var currentSenderName: String { currentUserID.map { SportsChatContract.guestName(uid: $0) } ?? "Guest" }
}

@MainActor final class FirebaseSportsChatBackend: SportsChatBackend {
    // Do not touch either SDK until app bootstrap has configured Firebase.
    private func database() throws -> Firestore {
        guard FirebaseApp.app() != nil else { throw SportsChatError.unavailable }
        return Firestore.firestore()
    }
    var currentUserID: String? { FirebaseApp.app() == nil ? nil : Auth.auth().currentUser?.uid }
    var currentSenderName: String {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { return "Guest" }
        let name = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (user.isAnonymous ? SportsChatContract.guestName(uid: user.uid) : "Streamify viewer") : name
    }

    func listen(room: String, receive: @escaping (Result<[SportsChatMessage], Error>) -> Void) throws -> SportsChatSubscription {
        guard SportsChatContract.validRoom(room) else { throw SportsChatError.invalidRoom }
        let registration = try database().collection("live-chats").document(room).collection("messages")
            .order(by: "sentAt", descending: false).limit(toLast: 100).addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                let result: Result<[SportsChatMessage], Error>
                if let error { result = .failure(error) }
                else if let snapshot {
                    result = .success(snapshot.documents.compactMap { doc in
                        let data = doc.data()
                        return SportsChatMessage.parse(id: doc.documentID, data: data,
                            sentAt: (data["sentAt"] as? Timestamp)?.dateValue(), pending: doc.metadata.hasPendingWrites)
                    })
                } else { result = .failure(SportsChatError.unavailable) }
                Task { @MainActor in receive(result) }
            }
        return SportsChatSubscription { registration.remove() }
    }

    func send(room: String, messageID: String, text: String, reply: SportsChatReply?) async throws {
        guard SportsChatContract.validRoom(room) else { throw SportsChatError.invalidRoom }
        guard !messageID.isEmpty, !messageID.contains("/"), messageID.utf16.count <= 150 else { throw SportsChatError.invalidMessage }
        let text = try SportsChatContract.message(text)
        let db = try database()
        try Task.checkCancellation()
        let auth = Auth.auth()
        let user: User = try await AccountAuthGate.perform {
            if let current = auth.currentUser { return current }
            return try await auth.signInAnonymously().user
        }
        try Task.checkCancellation()
        let uid = user.uid
        let displayName = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = displayName.isEmpty ? (user.isAnonymous ? SportsChatContract.guestName(uid: uid) : "Streamify viewer") : SportsChatContract.limit(displayName, utf16Count: 160)
        let roomRef = db.collection("live-chats").document(room)
        let entry = roomRef.collection("messages").document(messageID)
        let expiration = Timestamp(date: Date().addingTimeInterval(12 * 60 * 60))
        var fields: [String: Any] = ["message": text, "sentAt": FieldValue.serverTimestamp(),
            "senderId": uid, "senderName": sender, "reactions": [String]()]
        if let reply { fields["replyTo"] = ["id": reply.id, "sender": reply.sender, "message": reply.message] }
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(roomRef)
                guard auth.currentUser?.uid == uid else { throw SportsChatError.accountChanged }
                if !existing.exists {
                    transaction.setData(["createdAt": FieldValue.serverTimestamp(), "expiresAt": expiration], forDocument: roomRef)
                }
                transaction.setData(fields, forDocument: entry)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
    }

    func react(room: String, messageID: String, emoji: String?) async throws {
        guard SportsChatContract.validRoom(room), !messageID.isEmpty, !messageID.contains("/"),
              emoji == nil || SportsChatContract.reactions.contains(emoji!) else { throw SportsChatError.invalidReaction }
        let db = try database()
        guard let user = Auth.auth().currentUser else { throw SportsChatError.reactionNeedsGuest }
        let uid = user.uid, auth = Auth.auth()
        let ref = db.collection("live-chats").document(room).collection("messages").document(messageID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                _ = try transaction.getDocument(ref)
                guard auth.currentUser?.uid == uid else { throw SportsChatError.accountChanged }
                let value: Any = emoji.map { $0 as Any } ?? FieldValue.delete()
                transaction.updateData([FieldPath(["reactionVotes", uid]): value], forDocument: ref)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
    }
}

@MainActor final class SportsChatStore: ObservableObject {
    @Published private(set) var messages: [SportsChatMessage] = []
    @Published private(set) var loading = true
    @Published private(set) var error: String?
    @Published private(set) var actionError: String?
    @Published private(set) var sending = false
    @Published private(set) var userID: String?
    @Published var draft = ""
    @Published var reply: SportsChatReply?
    private let backend: SportsChatBackend
    private var subscription: SportsChatSubscription?
    private var room: String?
    private var generation = UUID()
    private var roomVersion = UUID()
    private var failedAction: (message: String, emoji: String?)?
    private var remoteMessages: [SportsChatMessage] = []
    private var outbox: [String: SportsChatMessage] = [:]
    private var outboxOrder: [String] = []
    private struct ReactionIntent { let revision = UUID(); let emoji: String?; var acknowledged = false }
    private var reactions: [String: ReactionIntent] = [:]
    private var reacting = Set<String>()
    private let initialResponseTimeout: Duration
    private var connectionTimeout: Task<Void, Never>?

    init(backend: SportsChatBackend? = nil, initialResponseTimeout: Duration = .seconds(12)) {
        self.initialResponseTimeout = initialResponseTimeout
        if let backend { self.backend = backend }
        else {
            #if DEBUG
            self.backend = PreviewFixtures.enabled ? FixtureSportsChatBackend() : FirebaseSportsChatBackend()
            #else
            self.backend = FirebaseSportsChatBackend()
            #endif
        }
    }
    func listen(room: String?, active: Bool) {
        connectionTimeout?.cancel(); connectionTimeout = nil
        subscription?.remove(); subscription = nil; generation = UUID()
        if self.room != room {
            roomVersion = UUID(); sending = false
            messages = []; remoteMessages = []; outbox = [:]; outboxOrder = []; reactions = [:]; reacting = []
            draft = ""; reply = nil; error = nil; actionError = nil; failedAction = nil
        }
        self.room = room
        guard active else { loading = false; return }
        guard let room else { loading = false; error = SportsChatError.invalidRoom.localizedDescription; return }
        loading = messages.isEmpty; error = nil; userID = backend.currentUserID
        let request = generation
        connectionTimeout = Task { @MainActor [weak self, initialResponseTimeout] in
            do { try await Task.sleep(for: initialResponseTimeout) } catch { return }
            guard let self, !Task.isCancelled, self.generation == request, self.loading else { return }
            self.loading = false
            self.error = SportsChatError.connectionTimedOut.localizedDescription
        }
        do {
            subscription = try backend.listen(room: room) { [weak self] result in
                guard let self, self.generation == request else { return }
                self.connectionTimeout?.cancel(); self.connectionTimeout = nil
                self.loading = false
                switch result {
                case .failure(let error): self.error = error.localizedDescription
                case .success(let messages):
                    let known = Dictionary(uniqueKeysWithValues: self.remoteMessages.map { ($0.id, $0) })
                    self.remoteMessages = messages.map { message in
                        var value = message
                        if message.pending { value.votes = known[message.id]?.votes ?? [:] }
                        return value
                    }
                    self.publishMessages()
                    self.error = nil
                }
            }
        } catch { connectionTimeout?.cancel(); connectionTimeout = nil; loading = false; self.error = error.localizedDescription }
    }
    func send() async {
        guard !sending, let room else { return }
        let original = draft, quote = reply
        let text: String
        do { text = try SportsChatContract.message(original) }
        catch { actionError = error.localizedDescription; return }
        let post = SportsChatMessage(id: UUID().uuidString, text: text, sender: backend.currentSenderName,
            uid: backend.currentUserID ?? "local-self", sentAt: Date(), reply: quote, votes: [:], pending: true)
        outboxOrder.append(post.id); outbox[post.id] = post
        draft = ""; reply = nil
        publishMessages()
        await deliver(post, room: room)
    }
    func retrySend(_ id: String) async {
        guard !sending, let room, let post = outbox[id], post.deliveryError != nil else { return }
        await deliver(post, room: room)
    }
    private func deliver(_ post: SportsChatMessage, room: String) async {
        let context = roomVersion
        sending = true; actionError = nil; failedAction = nil
        outbox[post.id] = post.delivery(pending: true); publishMessages()
        defer { if roomVersion == context { sending = false; userID = backend.currentUserID; publishMessages() } }
        do {
            try await backend.send(room: room, messageID: post.id, text: post.text, reply: post.reply)
            if self.roomVersion == context {
                outbox[post.id] = post.delivery(pending: false)
            }
        } catch {
            if self.roomVersion == context {
                outbox[post.id] = post.delivery(pending: false, error: error.localizedDescription)
                actionError = error.localizedDescription
            }
        }
    }
    func react(messageID: String, emoji: String) async {
        guard let message = messages.first(where: { $0.id == messageID }), !message.pending,
              message.deliveryError == nil, SportsChatContract.reactions.contains(emoji) else { return }
        let uid = backend.currentUserID ?? userID ?? "local-self"
        await setReaction(messageID: messageID, emoji: message.votes[uid] == emoji ? nil : emoji)
    }
    private func setReaction(messageID: String, emoji: String?) async {
        guard let room else { return }
        let context = roomVersion
        reactions[messageID] = ReactionIntent(emoji: emoji)
        publishMessages()
        actionError = nil
        guard reacting.insert(messageID).inserted else { return }
        defer { if roomVersion == context { reacting.remove(messageID); publishMessages() } }
        // Serialize requests for one message. Later taps stay visible while an
        // earlier request is in flight, and stale completions cannot undo them.
        while roomVersion == context, let intent = reactions[messageID], !intent.acknowledged {
            do {
                try await backend.react(room: room, messageID: messageID, emoji: intent.emoji)
                guard roomVersion == context else { return }
                if reactions[messageID]?.revision == intent.revision {
                    reactions[messageID]?.acknowledged = true; failedAction = nil; break
                }
            } catch {
                guard roomVersion == context else { return }
                if reactions[messageID]?.revision == intent.revision {
                    reactions.removeValue(forKey: messageID)
                    actionError = error.localizedDescription; failedAction = (messageID, intent.emoji); break
                }
            }
        }
    }
    func retryAction() async {
        if let failedAction { await setReaction(messageID: failedAction.message, emoji: failedAction.emoji) }
        else if let id = outboxOrder.first(where: { outbox[$0]?.deliveryError != nil }) { await retrySend(id) }
        else { await send() }
    }
    private func publishMessages() {
        let uid = backend.currentUserID ?? userID ?? "local-self"
        for message in remoteMessages where !message.pending {
            if let local = outbox[message.id], !local.pending { outbox.removeValue(forKey: message.id) }
            if let intent = reactions[message.id], intent.acknowledged, message.votes[uid] == intent.emoji { reactions.removeValue(forKey: message.id) }
        }
        outboxOrder.removeAll { outbox[$0] == nil }
        let ids = Set(remoteMessages.map(\.id))
        var values = remoteMessages.map { message in
            outbox[message.id].map { message.delivery(pending: $0.pending, error: $0.deliveryError) } ?? message
        }
        values += outboxOrder.filter { !ids.contains($0) }.compactMap { outbox[$0] }
        messages = values.map { message in
            var value = message
            if let intent = reactions[message.id] { value.votes[uid] = intent.emoji }
            return value
        }
    }
    deinit { connectionTimeout?.cancel(); subscription?.remove() }
}

#if DEBUG
@MainActor private final class FixtureSportsChatBackend: SportsChatBackend {
    var currentUserID: String?
    private var messages = [SportsChatMessage(id: "fixture-chat-1", text: "What a game!", sender: "Guest 2048", uid: "fixture2048",
        sentAt: Date().addingTimeInterval(-120), reply: nil, votes: ["fixture-other": "🔥"], pending: false)]
    private var receive: ((Result<[SportsChatMessage], Error>) -> Void)?
    private var listenCount = 0
    func listen(room: String, receive: @escaping (Result<[SportsChatMessage], Error>) -> Void) throws -> SportsChatSubscription {
        self.receive = receive; listenCount += 1
        if !ProcessInfo.processInfo.arguments.contains("--ui-chat-stalled-fixture") || listenCount > 1 {
            receive(.success(messages))
        }
        return SportsChatSubscription {}
    }
    func send(room: String, messageID: String, text: String, reply: SportsChatReply?) async throws {
        let text = try SportsChatContract.message(text)
        if ProcessInfo.processInfo.arguments.contains("--ui-chat-delayed-send-fixture") {
            try await Task.sleep(for: .seconds(2))
        }
        currentUserID = "fixture-guest-1024"
        messages.append(SportsChatMessage(id: messageID, text: text, sender: "Guest 1024", uid: currentUserID!, sentAt: Date(), reply: reply, votes: [:], pending: false))
        receive?(.success(messages))
    }
    func react(room: String, messageID: String, emoji: String?) async throws {
        guard currentUserID != nil else { throw SportsChatError.reactionNeedsGuest }
        // Match the inspected production rule: message creates are allowed,
        // reaction updates currently fail. Fixtures must not imply otherwise.
        throw NSError(domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."])
    }
}
#endif
