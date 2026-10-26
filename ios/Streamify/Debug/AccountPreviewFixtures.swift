#if DEBUG
import Foundation

/// Local account transitions for UI verification. Never authenticates with Firebase.
@MainActor final class PreviewAccountClient: AccountAuthClient {
    private(set) var currentIdentity: AccountIdentity?
    private var receive: ((AccountIdentity?) -> Void)?
    func observe(_ receive: @escaping (AccountIdentity?) -> Void) -> SportsChatSubscription {
        self.receive = receive
        receive(currentIdentity)
        return SportsChatSubscription {}
    }
    func signIn(email: String, password: String) async throws { try await complete(email: email) }
    func signInWithGoogle() async throws {
        if ProcessInfo.processInfo.arguments.contains("--ui-google-cancel") { throw CancellationError() }
        try await complete(email: "review@example.invalid")
    }
    func register(email: String, password: String) async throws { try await complete(email: email) }
    func signOut() async throws { currentIdentity = nil; receive?(nil) }
    func resetPassword(email: String) async throws {}
    private func complete(email: String) async throws {
        currentIdentity = AccountIdentity(uid: "local-review-account", email: email)
        receive?(currentIdentity)
        // Exercise the real auth-observer-before-method-return ordering.
        try await Task.sleep(for: .milliseconds(150))
    }
}

@MainActor final class PreviewProfileBackend: ProfileSyncBackend {
    private var document = ProfileCloudDocument(revision: 1, payload: ProfileCloudPayload(profiles: [
        ProfileCloudEntry(profile: AppProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!, name: "Account viewer", avatar: .gold),
            appearance: "Dark", serverID: "vidy", favoriteGenres: [18], followedTeams: ["nba:200"])
    ]))
    func load(uid: String) async throws -> ProfileCloudDocument? {
        try await Task.sleep(for: .milliseconds(200))
        return document
    }
    func createIfAbsent(uid: String, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument { document }
    func commit(uid: String, expectedRevision: Int, payload: ProfileCloudPayload) async throws -> ProfileCloudDocument {
        guard expectedRevision == document.revision else { throw ProfileSyncError.conflict }
        document = ProfileCloudDocument(revision: expectedRevision + 1, payload: payload)
        return document
    }
}
#endif
