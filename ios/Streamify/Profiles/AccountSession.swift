import Foundation
import Combine
import FirebaseCore
import FirebaseAuth

struct AccountIdentity: Equatable, Sendable {
    let uid: String
    let email: String?
    var isValid: Bool { !uid.isEmpty && uid.count <= 128 && !uid.contains("/") }
}

@MainActor protocol AccountAuthClient: AnyObject {
    var currentIdentity: AccountIdentity? { get }
    func observe(_ receive: @escaping (AccountIdentity?) -> Void) -> SportsChatSubscription
    func signIn(email: String, password: String) async throws
    func register(email: String, password: String) async throws
    func signOut() async throws
    func resetPassword(email: String) async throws
}

/// Anonymous chat and account sign-in share one auth instance. Serialize mutations
/// so an anonymous request cannot finish after a real sign-in and replace it.
@MainActor enum AccountAuthGate {
    private static var occupied = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []
    static func perform<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        if occupied { await withCheckedContinuation { waiters.append($0) } }
        else { occupied = true }
        defer {
            if waiters.isEmpty { occupied = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        return try await operation()
    }
}

@MainActor final class FirebaseAccountAuthClient: AccountAuthClient {
    private func auth() throws -> Auth {
        guard FirebaseApp.app() != nil else { throw AccountError.unavailable }
        return Auth.auth()
    }
    var currentIdentity: AccountIdentity? {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser, !user.isAnonymous else { return nil }
        let identity = AccountIdentity(uid: user.uid, email: user.email)
        return identity.isValid ? identity : nil
    }
    func observe(_ receive: @escaping (AccountIdentity?) -> Void) -> SportsChatSubscription {
        guard let auth = try? auth() else { receive(nil); return SportsChatSubscription {} }
        let handle = auth.addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in receive(self?.currentIdentity) }
        }
        return SportsChatSubscription { auth.removeStateDidChangeListener(handle) }
    }
    func signIn(email: String, password: String) async throws {
        try await AccountAuthGate.perform { _ = try await self.auth().signIn(withEmail: email, password: password) }
    }
    func register(email: String, password: String) async throws {
        try await AccountAuthGate.perform { _ = try await self.auth().createUser(withEmail: email, password: password) }
    }
    func signOut() async throws {
        try await AccountAuthGate.perform { try self.auth().signOut() }
    }
    func resetPassword(email: String) async throws { try await auth().sendPasswordReset(withEmail: email) }
}

enum AccountError: LocalizedError {
    case unavailable, email, password
    var errorDescription: String? {
        switch self {
        case .unavailable: "Account sign-in is unavailable in this build."
        case .email: "Enter your email address."
        case .password: "Use a password with at least 6 characters."
        }
    }
}

@MainActor final class AccountSession: ObservableObject {
    @Published private(set) var identity: AccountIdentity?
    @Published private(set) var isWorking = false
    @Published private(set) var isResolved = false
    @Published private(set) var error: String?
    @Published private(set) var message: String?
    private let client: any AccountAuthClient
    private var observation: SportsChatSubscription?

    init(client: (any AccountAuthClient)? = nil) {
        let client = client ?? FirebaseAccountAuthClient()
        self.client = client
        identity = client.currentIdentity
        observation = client.observe { [weak self] in self?.identity = $0; self?.isResolved = true }
    }
    func signIn(email: String, password: String) async {
        await perform {
            let email = try self.validEmail(email)
            guard !password.isEmpty else { throw AccountError.password }
            try await self.client.signIn(email: email, password: password)
        }
    }
    func register(email: String, password: String) async {
        await perform {
            let email = try self.validEmail(email)
            guard password.count >= 6 else { throw AccountError.password }
            try await self.client.register(email: email, password: password)
        }
    }
    func signOut() async { await perform { try await self.client.signOut() } }
    func resetPassword(email: String) async {
        await perform {
            try await self.client.resetPassword(email: self.validEmail(email))
            self.message = "If an account uses that email, a password reset link has been sent."
        }
    }
    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true; error = nil; message = nil
        defer { isWorking = false; identity = client.currentIdentity }
        do { try await operation() }
        catch { self.error = error.localizedDescription }
    }
    private func validEmail(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 254, value.contains("@"), !value.contains(" ") else { throw AccountError.email }
        return value
    }
}
