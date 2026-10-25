import Foundation
import XCTest
@testable import Streamify

@MainActor final class AccountSessionTests: XCTestCase {
    func testSignInRegisterResetAndSignOutUseInjectedClient() async {
        let client = AccountClientFake()
        let session = AccountSession(client: client)
        XCTAssertTrue(session.isResolved)
        XCTAssertNil(session.identity)
        await session.signIn(email: " alice@example.com ", password: "secret-value")
        XCTAssertEqual(session.identity?.uid, "account-alice")
        XCTAssertEqual(client.signIns, 1)
        XCTAssertEqual(client.lastEmail, "alice@example.com")
        await session.signOut()
        XCTAssertNil(session.identity)
        XCTAssertEqual(client.signOuts, 1)
        await session.register(email: "alice@example.com", password: "secret-value")
        XCTAssertEqual(client.registrations, 1)
        XCTAssertNotNil(session.identity)
        await session.resetPassword(email: "alice@example.com")
        XCTAssertEqual(client.resets, 1)
        XCTAssertNotNil(session.message)
        XCTAssertNil(session.error)
    }
    func testValidationAndBackendErrorsAreVisibleWithoutClaimingSignedIn() async {
        let client = AccountClientFake()
        let session = AccountSession(client: client)
        await session.signIn(email: "", password: "")
        XCTAssertEqual(client.signIns, 0)
        XCTAssertNotNil(session.error)
        await session.register(email: "a@example.com", password: "1")
        XCTAssertEqual(client.registrations, 0)
        client.failure = AccountError.unavailable
        await session.signIn(email: "a@example.com", password: "password")
        XCTAssertEqual(session.error, AccountError.unavailable.localizedDescription)
        XCTAssertNil(session.identity)
        XCTAssertFalse(session.isWorking)
    }
    func testAuthGateSerializesAnonymousAndRealAccountMutations() async {
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let anonymous = Task {
            try await AccountAuthGate.perform {
                events.append("anonymous-start")
                await withCheckedContinuation { release = $0 }
                events.append("anonymous-finish")
            }
        }
        for _ in 0..<100 where release == nil { await Task.yield() }
        let real = Task {
            try await AccountAuthGate.perform { events.append("real-sign-in") }
        }
        await Task.yield()
        XCTAssertEqual(events, ["anonymous-start"])
        release?.resume()
        _ = try? await anonymous.value
        _ = try? await real.value
        XCTAssertEqual(events, ["anonymous-start", "anonymous-finish", "real-sign-in"])
    }
    func testCancelledQueuedAuthMutationNeverRuns() async {
        var release: CheckedContinuation<Void, Never>?
        let first = Task {
            try await AccountAuthGate.perform { await withCheckedContinuation { release = $0 } }
        }
        for _ in 0..<100 where release == nil { await Task.yield() }
        var called = false
        let second = Task { try await AccountAuthGate.perform { called = true } }
        second.cancel()
        release?.resume()
        _ = try? await first.value
        _ = try? await second.value
        XCTAssertFalse(called)
    }
}

@MainActor private final class AccountClientFake: AccountAuthClient {
    var currentIdentity: AccountIdentity?
    var signIns = 0, registrations = 0, signOuts = 0, resets = 0
    var lastEmail: String?
    var failure: Error?
    private var observer: ((AccountIdentity?) -> Void)?
    func observe(_ receive: @escaping (AccountIdentity?) -> Void) -> SportsChatSubscription {
        observer = receive
        receive(currentIdentity)
        return SportsChatSubscription {}
    }
    func signIn(email: String, password: String) async throws {
        signIns += 1
        if let failure { throw failure }
        lastEmail = email
        currentIdentity = AccountIdentity(uid: "account-alice", email: email)
        observer?(currentIdentity)
    }
    func register(email: String, password: String) async throws {
        registrations += 1
        if let failure { throw failure }
        lastEmail = email
        currentIdentity = AccountIdentity(uid: "account-alice", email: email)
        observer?(currentIdentity)
    }
    func signOut() async throws {
        signOuts += 1
        if let failure { throw failure }
        currentIdentity = nil
        observer?(nil)
    }
    func resetPassword(email: String) async throws {
        resets += 1
        if let failure { throw failure }
        lastEmail = email
    }
}
