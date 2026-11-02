import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@MainActor protocol HistorySyncBackend: AnyObject {
    func load(uid: String, profileID: UUID) async throws -> [String: HistorySyncEnvelope]
    func commit(uid: String, profileID: UUID, id: String, record: HistorySyncEnvelope, importing: Bool, metadataOnly: Bool) async throws -> HistorySyncEnvelope
    func legacyTarget(uid: String, firstProfileID: UUID) async throws -> UUID
    func legacyHistory(uid: String) async throws -> [String: HistorySyncEnvelope]
    func listen(uid: String, profileID: UUID, receive: @escaping (Result<[String: HistorySyncEnvelope], Error>) -> Void) -> () -> Void
}

@MainActor final class FirebaseHistorySyncBackend: HistorySyncBackend {
    private nonisolated static func check(_ uid: String) throws {
        guard FirebaseApp.app() != nil, !uid.isEmpty, uid.count <= 128, !uid.contains("/"),
              let user = Auth.auth().currentUser, !user.isAnonymous, user.uid == uid else { throw ProfileSyncError.accountChanged }
    }
    private func collection(uid: String, profileID: UUID) throws -> CollectionReference {
        try Self.check(uid)
        return Firestore.firestore().collection("users").document(uid).collection("profileLibraries")
            .document(profileID.uuidString).collection("items")
    }
    private nonisolated static func records(_ snapshot: QuerySnapshot) -> [String: HistorySyncEnvelope] {
        Dictionary(snapshot.documents.compactMap { document in
            HistorySyncEnvelope(fields: document.data(), documentID: document.documentID).map { (document.documentID, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }
    func load(uid: String, profileID: UUID) async throws -> [String: HistorySyncEnvelope] {
        let ref = try collection(uid: uid, profileID: profileID)
        return try await withProfileDeadline { finish in
            ref.getDocuments(source: .server) { snapshot, error in
                do {
                    if let error { throw error }; try Self.check(uid)
                    guard let snapshot else { throw ProfileSyncError.unavailable }
                    finish(.success(Self.records(snapshot)))
                } catch { finish(.failure(error)) }
            }
        }
    }
    func commit(uid: String, profileID: UUID, id: String, record: HistorySyncEnvelope, importing: Bool, metadataOnly: Bool) async throws -> HistorySyncEnvelope {
        guard record.valid(documentID: id) else { throw ProfileSyncError.invalidData }
        let ref = try collection(uid: uid, profileID: profileID).document(id)
        return try await withProfileDeadline { finish in
            Firestore.firestore().runTransaction({ transaction, pointer -> Any? in
                do {
                    try Self.check(uid)
                    let snapshot = try transaction.getDocument(ref)
                    var candidate = record
                    if let data = snapshot.data(), let current = HistorySyncEnvelope(fields: data, documentID: id) {
                        if current == record || current.wins(over: record) || importing && current.protectsFromImport(record, id: id) || metadataOnly && current.deleted { return current.fields }
                        candidate = record.mergingKnownData(from: current, id: id, preservePlayback: metadataOnly)
                    }
                    transaction.setData(candidate.fields, forDocument: ref)
                    return candidate.fields
                } catch { pointer?.pointee = error as NSError; return nil }
            }, completion: { result, error in
                do {
                    if let error { throw error }; try Self.check(uid)
                    guard let fields = result as? [String: Any], let winner = HistorySyncEnvelope(fields: fields, documentID: id)
                    else { throw ProfileSyncError.invalidData }
                    finish(.success(winner))
                } catch { finish(.failure(error)) }
            })
        }
    }
    func legacyTarget(uid: String, firstProfileID: UUID) async throws -> UUID {
        try Self.check(uid)
        let ref = Firestore.firestore().collection("users").document(uid).collection("profileSettings").document("history-migration-v1")
        return try await withProfileDeadline { finish in
            Firestore.firestore().runTransaction({ transaction, pointer -> Any? in
                do {
                    try Self.check(uid)
                    let snapshot = try transaction.getDocument(ref)
                    if snapshot.exists {
                        guard let fields = snapshot.data(), fields["schemaVersion"] as? Int == 1,
                              let raw = fields["profileID"] as? String, let target = HistorySyncEnvelope.profileID(raw), target == raw
                        else { throw ProfileSyncError.invalidData }
                        return target
                    }
                    transaction.setData(["schemaVersion": 1, "profileID": firstProfileID.uuidString], forDocument: ref)
                    return firstProfileID.uuidString
                } catch { pointer?.pointee = error as NSError; return nil }
            }, completion: { result, error in
                do {
                    if let error { throw error }; try Self.check(uid)
                    guard let raw = result as? String, let id = UUID(uuidString: raw) else { throw ProfileSyncError.invalidData }
                    finish(.success(id))
                } catch { finish(.failure(error)) }
            })
        }
    }
    func legacyHistory(uid: String) async throws -> [String: HistorySyncEnvelope] {
        try Self.check(uid)
        let ref = Firestore.firestore().collection("users").document(uid).collection("watchHistory")
        return try await withProfileDeadline { finish in
            ref.getDocuments(source: .server) { snapshot, error in
                do {
                    if let error { throw error }; try Self.check(uid)
                    guard let snapshot else { throw ProfileSyncError.unavailable }
                    var result: [String: HistorySyncEnvelope] = [:]
                    for document in snapshot.documents {
                        let fields = document.data()
                        guard let timestamp = fields["updatedAt"] as? Timestamp,
                              let record = HistorySyncEnvelope.legacy(fields, timestamp: timestamp.dateValue().timeIntervalSince1970 * 1000),
                              let data = record.payload.data(using: .utf8), let entry = try? HistorySyncEnvelope.decoder.decode(WatchEntry.self, from: data)
                        else { continue }
                        let id = HistorySyncEnvelope.documentID(entry)
                        if result[id] == nil || record.wins(over: result[id]!) { result[id] = record }
                    }
                    finish(.success(result))
                } catch { finish(.failure(error)) }
            }
        }
    }
    func listen(uid: String, profileID: UUID, receive: @escaping (Result<[String: HistorySyncEnvelope], Error>) -> Void) -> () -> Void {
        guard let ref = try? collection(uid: uid, profileID: profileID) else { return {} }
        let registration = ref.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            if let error { Task { @MainActor in receive(.failure(error)) }; return }
            guard let snapshot, !snapshot.metadata.isFromCache, (try? Self.check(uid)) != nil else { return }
            let records = Self.records(snapshot)
            Task { @MainActor in receive(.success(records)) }
        }
        return { registration.remove() }
    }
}

/// One account/profile session owns its listener, transactions and bounded retry task.
@MainActor final class HistoryCloudSync {
    private weak var library: LibraryStore?
    private let uid: String
    private let profileID: UUID
    private let firstProfileID: UUID
    private let backend: any HistorySyncBackend
    private let identityValid: () -> Bool
    private let retrySeconds: Double
    private var cancelListener: (() -> Void)?
    private var work: Task<Void, Never>?
    private var stopped = false
    private var ready = false
    private var migrated = false
    private var listenerSession = UUID()

    init(library: LibraryStore, uid: String, profileID: UUID, firstProfileID: UUID,
         backend: any HistorySyncBackend, retrySeconds: Double = 10, identityValid: @escaping () -> Bool) {
        self.library = library; self.uid = uid; self.profileID = profileID; self.firstProfileID = firstProfileID
        self.backend = backend; self.retrySeconds = retrySeconds; self.identityValid = identityValid
        library.onHistoryChange = { [weak self] in self?.schedule() }
        schedule()
    }
    deinit { work?.cancel(); cancelListener?() }
    private var current: Bool { !stopped && !Task.isCancelled && identityValid() }
    func stop() {
        stopped = true; listenerSession = UUID(); work?.cancel(); work = nil; cancelListener?(); cancelListener = nil
        library?.onHistoryChange = nil
    }
    func retry() { guard !stopped else { return }; work?.cancel(); work = nil; schedule() }
    private func schedule(after delay: Double = 0) {
        guard current, work == nil else { return }
        work = Task { [weak self] in
            if delay > 0 { do { try await Task.sleep(for: .seconds(delay)) } catch { return } }
            guard let self, self.current else { return }
            await self.run()
        }
    }
    private func run() async {
        do {
            guard current, let library else { return }
            if !ready {
                let records = try await backend.load(uid: uid, profileID: profileID)
                guard current else { return }
                library.updateHistoryJournal { $0.mergeServer(records) }
                ready = true
                let expectedListener = UUID(); listenerSession = expectedListener
                cancelListener = backend.listen(uid: uid, profileID: profileID) { [weak self] result in
                    guard let self, self.current, self.listenerSession == expectedListener, let library = self.library else { return }
                    switch result {
                    case .success(let records):
                        library.updateHistoryJournal { $0.mergeServer(records) }; self.schedule()
                    case .failure:
                        self.listenerSession = UUID(); self.cancelListener?(); self.cancelListener = nil
                        self.work?.cancel(); self.work = nil; self.ready = false
                        library.historySyncMessage = "History is saved on this device. Sync will retry when connected."
                        self.schedule(after: self.retrySeconds)
                    }
                }
            }
            if !migrated {
                let target = try await backend.legacyTarget(uid: uid, firstProfileID: firstProfileID)
                guard current else { return }
                if target == profileID {
                    let legacy = try await backend.legacyHistory(uid: uid)
                    guard current else { return }
                    library.updateHistoryJournal { $0.importLegacy(legacy) }
                }
                migrated = true
            }
            while current, let next = library.historySyncJournal.pending.sorted(by: { $0.key < $1.key }).first {
                let winner = try await backend.commit(uid: uid, profileID: profileID, id: next.key, record: next.value,
                    importing: library.historySyncJournal.isImport(next.key), metadataOnly: library.historySyncJournal.isMetadataOnly(next.key))
                guard current else { return }
                library.updateHistoryJournal { $0.acknowledge(id: next.key, sent: next.value, winner: winner) }
            }
            guard current else { return }
            library.historySyncMessage = "History and progress synced with this profile"
            work = nil
        } catch {
            guard current else { return }
            library?.historySyncMessage = "History is saved on this device. Sync will retry when connected."
            work = nil; schedule(after: retrySeconds)
        }
    }
}
