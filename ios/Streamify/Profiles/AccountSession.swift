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
    func signInWithGoogle() async throws
    func register(email: String, password: String) async throws
    func signOut() async throws
    func resetPassword(email: String) async throws
}

extension AccountAuthClient {
    func signInWithGoogle() async throws { throw AccountError.unavailable }
}

struct AccountHomeIntent: Equatable {
    let id = UUID()
    let uid: String
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
    func signInWithGoogle() async throws {
        try await AccountAuthGate.perform {
            let credential = try await GoogleAccountSignIn.credential()
            try Task.checkCancellation()
            _ = try await self.auth().signIn(with: credential)
        }
    }
    func signOut() async throws {
        try await AccountAuthGate.perform { try self.auth().signOut(); GoogleAccountSignIn.signOut() }
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
    @Published private(set) var homeIntent: AccountHomeIntent?
    @Published private(set) var isSigningIn = false
    private let client: any AccountAuthClient
    private var observation: SportsChatSubscription?

    init(client: (any AccountAuthClient)? = nil) {
        let client = client ?? FirebaseAccountAuthClient()
        self.client = client
        identity = client.currentIdentity
        observation = client.observe { [weak self] identity in
            self?.identity = identity; self?.isResolved = true
            if let pending = self?.homeIntent, pending.uid != identity?.uid { self?.homeIntent = nil }
        }
    }
    func signIn(email: String, password: String) async {
        await perform(openHome: true) {
            let email = try self.validEmail(email)
            guard !password.isEmpty else { throw AccountError.password }
            try await self.client.signIn(email: email, password: password)
        }
    }
    func register(email: String, password: String) async {
        await perform(openHome: true) {
            let email = try self.validEmail(email)
            guard password.count >= 6 else { throw AccountError.password }
            try await self.client.register(email: email, password: password)
        }
    }
    func signInWithGoogle() async { await perform(openHome: true) { try await self.client.signInWithGoogle() } }
    func consumeHomeIntent(_ id: UUID) { if homeIntent?.id == id { homeIntent = nil } }
    func signOut() async { await perform { try await self.client.signOut() } }
    func resetPassword(email: String) async {
        await perform {
            try await self.client.resetPassword(email: self.validEmail(email))
            self.message = "If an account uses that email, a password reset link has been sent."
        }
    }
    private func perform(openHome: Bool = false, _ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true; isSigningIn = openHome; error = nil; message = nil
        defer { isWorking = false; isSigningIn = false; identity = client.currentIdentity }
        do {
            try await operation()
            identity = client.currentIdentity
            if openHome, let identity, identity.isValid {
                isResolved = true
                homeIntent = AccountHomeIntent(uid: identity.uid)
            }
        }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func validEmail(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 254, value.contains("@"), !value.contains(" ") else { throw AccountError.email }
        return value
    }
}
