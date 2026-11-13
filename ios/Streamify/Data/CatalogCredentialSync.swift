import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@MainActor protocol CatalogCredentialBackend: AnyObject {
    func load(uid: String) async throws -> String?
    func write(uid: String, key: String, onlyIfAbsent: Bool) async throws -> String
    func listen(uid: String, receive: @escaping (Result<String?, Error>) -> Void) -> () -> Void
}

enum CatalogCredentialError: LocalizedError {
    case invalid, accountChanged, unavailable

    var errorDescription: String? {
        switch self {
        case .invalid: "Enter a TMDB key or access token of at most 512 characters."
        case .accountChanged: "The account changed. Reopen Settings to edit its catalog key."
        case .unavailable: "The account catalog key could not be synced. Streamify will retry."
        }
    }
}

@MainActor final class FirebaseCatalogCredentialBackend: CatalogCredentialBackend {
    private nonisolated static func checkIdentity(_ uid: String) throws {
        guard FirebaseApp.app() != nil, AccountIdentity(uid: uid, email: nil).isValid,
              let user = Auth.auth().currentUser, user.uid == uid, !user.isAnonymous else { throw CatalogCredentialError.accountChanged }
    }

    private func reference(_ uid: String) throws -> DocumentReference {
        try Self.checkIdentity(uid)
        return Firestore.firestore().collection("catalogCredentials").document(uid)
    }

    private nonisolated static func decode(_ document: DocumentSnapshot) throws -> String? {
        guard document.exists else { return nil }
        guard let data = document.data(), data["schemaVersion"] as? Int == 1,
              let key = data["tmdbKey"] as? String, key.utf16.count <= 512,
              key == key.trimmingCharacters(in: .whitespacesAndNewlines) else { throw CatalogCredentialError.unavailable }
        return key
    }

    func load(uid: String) async throws -> String? {
        let ref = try reference(uid)
        return try await withProfileDeadline { finish in
            ref.getDocument(source: .server) { snapshot, error in
                do {
                    if let error { throw error }
                    try Self.checkIdentity(uid)
                    guard let snapshot else { throw CatalogCredentialError.unavailable }
                    finish(.success(try Self.decode(snapshot)))
                } catch { finish(.failure(error)) }
            }
        }
    }

    func write(uid: String, key: String, onlyIfAbsent: Bool) async throws -> String {
        let ref = try reference(uid)
        return try await withProfileDeadline { finish in
            Firestore.firestore().runTransaction({ transaction, pointer -> Any? in
                do {
                    try Self.checkIdentity(uid)
                    if onlyIfAbsent, let existing = try Self.decode(transaction.getDocument(ref)) { return existing }
                    try Self.checkIdentity(uid)
                    transaction.setData(["schemaVersion": 1, "tmdbKey": key], forDocument: ref)
                    return key
                } catch { pointer?.pointee = error as NSError; return nil }
            }, completion: { result, error in
                do {
                    if let error { throw error }
                    try Self.checkIdentity(uid)
                    guard let result = result as? String else { throw CatalogCredentialError.unavailable }
                    finish(.success(result))
                } catch { finish(.failure(error)) }
            })
        }
    }

    func listen(uid: String, receive: @escaping (Result<String?, Error>) -> Void) -> () -> Void {
        guard let ref = try? reference(uid) else { return {} }
        let registration = ref.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            guard (try? Self.checkIdentity(uid)) != nil else { return }
            if let error { Task { @MainActor in receive(.failure(error)) }; return }
            guard let snapshot, !snapshot.metadata.isFromCache, !snapshot.metadata.hasPendingWrites else { return }
            let result = Result { try Self.decode(snapshot) }
            Task { @MainActor in receive(result) }
        }
        return { registration.remove() }
    }
}

/// Keep one credential for the account, shared by its profiles. Store only UID-scoped
/// cached values and offline edits in Keychain. The old key remains the guest key.
@MainActor final class CatalogCredentialSync: ObservableObject {
    struct State: Equatable {
        let owner: String?
        let key: String
        var error: String? = nil
    }

    private struct Stored: Codable {
        var remote: String?
        var pending: String?
        var migration: String?
    }

    @Published private(set) var state = State(owner: nil, key: "")
    let packagedDefault: String
    private let backend: any CatalogCredentialBackend
    private let read: (String) throws -> String?
    private let write: (String, String) throws -> Void
    private let isAuthorized: (String?) -> Bool
    private let syncEnabled: Bool
    private let retrySeconds: Double
    private var owner: String?
    private var stored = Stored()
    private var session = UUID()
    private var listener: (() -> Void)?
    private var listenerID = UUID()
    private var work: Task<Void, Never>?
    private var ready = false
    private var firstResolution = true
    private static let guestKey = "tmdbToken"
    private static let migrationKey = "tmdbToken.accountMigration.v1"

    init(backend: (any CatalogCredentialBackend)? = nil, packagedDefault: String = "", syncEnabled: Bool = true,
         retrySeconds: Double = 15, read: @escaping (String) throws -> String? = SecureCredentialStore.get,
         write: @escaping (String, String) throws -> Void = SecureCredentialStore.set,
         isAuthorized: ((String?) -> Bool)? = nil) {
        self.backend = backend ?? FirebaseCatalogCredentialBackend()
        self.packagedDefault = packagedDefault
        self.syncEnabled = syncEnabled
        self.retrySeconds = retrySeconds
        self.read = read
        self.write = write
        self.isAuthorized = isAuthorized ?? Self.matchesAuth
        if syncEnabled { loadGuest() }
    }

    deinit { work?.cancel(); listener?() }

    private nonisolated static func matchesAuth(_ uid: String?) -> Bool {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser, !user.isAnonymous else { return uid == nil }
        return user.uid == uid
    }

    func connect(_ identity: AccountIdentity?) {
        let uid = identity.flatMap { $0.isValid ? $0.uid : nil }
        guard syncEnabled else { state = State(owner: uid, key: ""); return }
        guard uid != owner || firstResolution else { return }
        let initial = firstResolution
        firstResolution = false
        session = UUID()
        work?.cancel(); work = nil
        stopListener()
        ready = false
        owner = uid
        stored = Stored()
        if let uid {
            if let raw = try? read(storageKey(uid)), let data = raw.data(using: .utf8),
               let previous = try? JSONDecoder().decode(Stored.self, from: data) { stored = previous }
        }
        if initial { claimLegacy(for: uid) }
        if uid != nil { publish(); schedule() }
        else { loadGuest() }
    }

    func validateOwner(_ expected: String?) throws {
        guard owner == expected || !syncEnabled, !syncEnabled || isAuthorized(expected) else { throw CatalogCredentialError.accountChanged }
    }

    func save(_ input: String, owner expected: String?) throws {
        try validateOwner(expected)
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf16.count <= 512 else { throw CatalogCredentialError.invalid }
        let key = clean == packagedDefault ? "" : clean
        if !syncEnabled { state = State(owner: expected, key: key); return }
        guard let uid = expected else {
            try write(key, Self.guestKey)
            state = State(owner: nil, key: key)
            return
        }
        var edited = stored
        edited.pending = key
        edited.migration = nil
        try persist(edited, uid: uid)
        stored = edited
        publish()
        schedule()
    }

    private func storageKey(_ uid: String) -> String { "tmdbToken.account.v1.\(uid)" }

    private func persist(_ value: Stored, uid: String) throws {
        let data = try JSONEncoder().encode(value)
        try write(String(decoding: data, as: UTF8.self), storageKey(uid))
    }

    private func claimLegacy(for uid: String?) {
        do {
            let marker = try read(Self.migrationKey)
            guard marker == nil else { return }
            try write("resolved", Self.migrationKey)
            if let uid, isAuthorized(uid), stored.pending == nil, stored.remote == nil,
               let raw = try read(Self.guestKey) {
                let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, key != packagedDefault, key.utf16.count <= 512 {
                    var claimed = stored
                    claimed.migration = key
                    try persist(claimed, uid: uid)
                    stored = claimed
                }
            }
        } catch { /* A Keychain failure must not copy the credential to another account. */ }
    }

    private func loadGuest() {
        do {
            let raw = try read(Self.guestKey) ?? ""
            state = State(owner: nil, key: raw == packagedDefault ? "" : raw)
        } catch { state = State(owner: nil, key: "", error: error.localizedDescription) }
    }

    private func publish(error: String? = nil) {
        let key = stored.pending ?? stored.remote ?? ""
        state = State(owner: owner, key: key == packagedDefault ? "" : key, error: error)
    }

    private func current(_ expected: UUID, uid: String) -> Bool {
        session == expected && owner == uid && isAuthorized(uid) && !Task.isCancelled
    }

    private func schedule(after delay: Double = 0) {
        guard let uid = owner, work == nil, isAuthorized(uid) else { return }
        stopListener()
        let expected = session
        work = Task { [weak self] in
            if delay > 0 { do { try await Task.sleep(for: .seconds(delay)) } catch { return } }
            guard let self, self.current(expected, uid: uid) else { return }
            await self.run(uid: uid, session: expected)
        }
    }

    private func run(uid: String, session expected: UUID) async {
        do {
            if !ready {
                let remote = try await backend.load(uid: uid)
                guard current(expected, uid: uid) else { return }
                try accept(remote, uid: uid)
                ready = true
            }
            while let key = stored.pending ?? stored.migration {
                let importing = stored.pending == nil
                let remote = try await backend.write(uid: uid, key: key, onlyIfAbsent: importing)
                guard current(expected, uid: uid) else { return }
                var acknowledged = stored
                acknowledged.remote = remote
                acknowledged.migration = nil
                if !importing, acknowledged.pending == key { acknowledged.pending = nil }
                try persist(acknowledged, uid: uid)
                stored = acknowledged
                publish()
            }
            work = nil
            startListener(uid: uid, session: expected)
        } catch {
            guard current(expected, uid: uid) else { return }
            ready = false
            work = nil
            publish(error: CatalogCredentialError.unavailable.localizedDescription)
            schedule(after: retrySeconds)
        }
    }

    private func accept(_ key: String?, uid: String) throws {
        var updated = stored
        updated.remote = key
        if key != nil { updated.migration = nil }
        if updated.remote != stored.remote || updated.migration != stored.migration {
            try persist(updated, uid: uid)
            stored = updated
        }
        publish()
    }

    private func startListener(uid: String, session expected: UUID) {
        guard listener == nil else { return }
        let id = listenerID
        let cancel = backend.listen(uid: uid) { [weak self] result in
            guard let self, self.listenerID == id, self.current(expected, uid: uid), self.work == nil else { return }
            do { try self.accept(result.get(), uid: uid) }
            catch {
                self.stopListener()
                self.ready = false
                self.publish(error: CatalogCredentialError.unavailable.localizedDescription)
                self.schedule(after: self.retrySeconds)
            }
        }
        if listenerID == id { listener = cancel }
        else { cancel() }
    }

    private func stopListener() {
        listenerID = UUID()
        listener?(); listener = nil
    }
}
