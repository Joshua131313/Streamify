import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

struct ProfileCloudEntry: Codable, Equatable, Sendable {
    var profile: AppProfile
    var appearance: String
    var serverID: String
    var favoriteGenres: [Int]
    var followedTeams: [String]
}

struct ProfileCloudPayload: Codable, Equatable, Sendable {
    var profiles: [ProfileCloudEntry]
    func validated() throws -> Self {
        guard (1...5).contains(profiles.count), Set(profiles.map { $0.profile.id }).count == profiles.count,
              profiles.allSatisfy({ entry in
                  let name = entry.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !name.isEmpty && name.count <= 24 && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                    && ["Dark", "Light", "System"].contains(entry.appearance)
                    && !entry.serverID.isEmpty && entry.serverID.count <= 80
                    && entry.favoriteGenres.count <= 100 && entry.favoriteGenres.allSatisfy { $0 > 0 }
                    && entry.followedTeams.count <= 500 && entry.followedTeams.allSatisfy { !$0.isEmpty && $0.count <= 160 }
              }) else { throw ProfileSyncError.invalidData }
        return self
    }
}

struct ProfileCloudDocument: Equatable, Sendable {
    let revision: Int
    let payload: ProfileCloudPayload
    var createdNew = false
}

enum ProfileSyncError: LocalizedError {
    case unavailable, accountChanged, invalidData, conflict, timeout, notReady
    var errorDescription: String? {
        switch self {
        case .unavailable: "Profile sync is unavailable in this build. Your profiles remain on this device."
        case .accountChanged: "Your account changed. Please retry."
        case .invalidData: "Account profile data could not be read safely. Your local profiles are unchanged."
        case .conflict: "Profiles changed on another device. Reload account profiles to use those changes. Your local changes are still saved on this device."
        case .timeout: "The account service did not respond. Changes are saved on this device and will retry."
        case .notReady: "Connect to load this account’s profiles before editing them."
        }
    }
}

@MainActor protocol ProfileSyncBackend: AnyObject {
    func load(uid: String) async throws -> ProfileCloudDocument?
    func createIfAbsent(uid: String, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument
    func commit(uid: String, expectedRevision: Int, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument
}

/// A callback deadline does not wait for a non-cancellable Firebase operation.
/// Late acknowledgments are ignored; a subsequent server read reconciles them.
private final class ProfileRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ value: Result<Value, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: value)
    }
}

func withProfileDeadline<Value>(seconds: TimeInterval = 15,
    start: (@escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
    let request = ProfileRequest<Value>()
    return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            request.install(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { request.finish(.failure(ProfileSyncError.timeout)) }
            start { request.finish($0) }
        }
    } onCancel: { request.finish(.failure(CancellationError())) }
}

@MainActor final class FirebaseProfileSyncBackend: ProfileSyncBackend {
    private func reference(uid: String) throws -> DocumentReference {
        guard FirebaseApp.app() != nil else { throw ProfileSyncError.unavailable }
        try Self.checkIdentity(uid)
        return Firestore.firestore().collection("users").document(uid).collection("profileSettings").document("native-v1")
    }
    private nonisolated static func checkIdentity(_ uid: String) throws {
        guard !uid.isEmpty, uid.count <= 128, !uid.contains("/"),
              let user = Auth.auth().currentUser, !user.isAnonymous, user.uid == uid else { throw ProfileSyncError.accountChanged }
    }
    private nonisolated static func decode(_ fields: [String: Any]) throws -> ProfileCloudDocument {
        guard fields["schemaVersion"] as? Int == 1, let revision = fields["revision"] as? Int, revision > 0, revision < Int.max,
              let string = fields["payload"] as? String, string.utf8.count <= 65_536,
              let data = string.data(using: .utf8) else { throw ProfileSyncError.invalidData }
        let payload = try JSONDecoder().decode(ProfileCloudPayload.self, from: data).validated()
        return ProfileCloudDocument(revision: revision, payload: payload, createdNew: fields["createdNew"] as? Bool ?? false)
    }
    func load(uid: String) async throws -> ProfileCloudDocument? {
        let ref = try reference(uid: uid)
        return try await withProfileDeadline { finish in
            ref.getDocument(source: .server) { snapshot, error in
                do {
                    if let error { throw error }
                    try Self.checkIdentity(uid)
                    guard let snapshot else { throw ProfileSyncError.unavailable }
                    guard snapshot.exists else { finish(.success(nil)); return }
                    finish(.success(try Self.decode(snapshot.data() ?? [:])))
                } catch { finish(.failure(error)) }
            }
        }
    }
    func createIfAbsent(uid: String, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument {
        try await write(uid: uid, expectedRevision: nil, payload: payload)
    }
    func commit(uid: String, expectedRevision: Int, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument {
        try await write(uid: uid, expectedRevision: expectedRevision, payload: payload)
    }
    private func write(uid: String, expectedRevision: Int?, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument {
        let ref = try reference(uid: uid)
        let valid = try payload.validated()
        let data = try JSONEncoder().encode(valid)
        guard data.count <= 65_536, let encoded = String(data: data, encoding: .utf8) else { throw ProfileSyncError.invalidData }
        let db = Firestore.firestore()
        let fields: [String: Any] = try await withProfileDeadline { finish in
            db.runTransaction({ transaction, errorPointer -> Any? in
                do {
                    try Self.checkIdentity(uid)
                    let snapshot = try transaction.getDocument(ref)
                    if snapshot.exists {
                        let current = try Self.decode(snapshot.data() ?? [:])
                        if expectedRevision == nil { return snapshot.data() }
                        guard current.revision == expectedRevision else { throw ProfileSyncError.conflict }
                    } else if expectedRevision != nil { throw ProfileSyncError.conflict }
                    let revision = (expectedRevision ?? 0) + 1
                    let fields: [String: Any] = ["schemaVersion": 1, "revision": revision,
                        "payload": encoded, "updatedAt": FieldValue.serverTimestamp()]
                    try Self.checkIdentity(uid)
                    transaction.setData(fields, forDocument: ref)
                    return ["schemaVersion": 1, "revision": revision, "payload": encoded, "createdNew": expectedRevision == nil]
                } catch { errorPointer?.pointee = error as NSError; return nil }
            }, completion: { result, error in
                if let error { finish(.failure(error)) }
                else if let fields = result as? [String: Any] { finish(.success(fields)) }
                else { finish(.failure(ProfileSyncError.invalidData)) }
            })
        }
        try Self.checkIdentity(uid)
        return try Self.decode(fields)
    }
}
