import Foundation
import XCTest
@testable import Streamify

final class ResponseMemoryCacheTests: XCTestCase {
    func testConcurrentConsumersShareOneRequest() async throws {
        let cache = ResponseMemoryCache()
        let probe = CacheProbe()
        let values = try await withThrowingTaskGroup(of: Data.self, returning: [Data].self) { group in
            for _ in 0..<16 { group.addTask { try await cache.data(key: "game", lifetime: 30) { await probe.next() } } }
            var results: [Data] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(Set(values), [Data([1])])
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testFreshCacheExpiryAndExplicitRefresh() async throws {
        let clock = CacheClock()
        let cache = ResponseMemoryCache(now: { clock.value })
        let probe = CacheProbe()
        func load(_ reload: Bool = false) async throws -> Data {
            try await cache.data(key: "scoreboard", lifetime: 30, reload: reload) { await probe.next() }
        }
        let first = try await load()
        clock.advance(29)
        let fresh = try await load()
        XCTAssertEqual(fresh, first)
        clock.advance(1)
        let expired = try await load()
        XCTAssertEqual(expired, Data([2]))
        let forced = try await load(true)
        XCTAssertEqual(forced, Data([3]), "Pull-to-refresh must bypass an unexpired entry.")
    }

    func testCancelledViewDoesNotCancelSharedRequest() async throws {
        let cache = ResponseMemoryCache()
        let gate = CacheGate()
        let first = Task { try await cache.data(key: "shared", lifetime: 30) { await gate.load() } }
        await gate.waitUntilStarted()
        let second = Task { try await cache.data(key: "shared", lifetime: 30) { await gate.load() } }
        first.cancel()
        await gate.finish()
        do { _ = try await first.value; XCTFail("The disappeared consumer should be cancelled.") }
        catch is CancellationError { }
        let result = try await second.value
        XCTAssertEqual(result, Data([9]))
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
    }

    func testFailedRefreshDoesNotPoisonCacheOrBlockRetry() async throws {
        let cache = ResponseMemoryCache()
        _ = try await cache.data(key: "catalog", lifetime: 300) { Data([1]) }
        do {
            _ = try await cache.data(key: "catalog", lifetime: 300, reload: true) { throw URLError(.notConnectedToInternet) }
            XCTFail("A failed explicit refresh must report its error.")
        } catch { }
        let retained = try await cache.data(key: "catalog", lifetime: 300) { Data([99]) }
        XCTAssertEqual(retained, Data([1]))
        let retried = try await cache.data(key: "catalog", lifetime: 300, reload: true) { Data([2]) }
        XCTAssertEqual(retried, Data([2]))
    }

    func testCacheBoundsEvictLeastRecentlyUsedAndOversizedResponses() async throws {
        let clock = CacheClock()
        let cache = ResponseMemoryCache(entryLimit: 2, byteLimit: 4, now: { clock.value })
        _ = try await cache.data(key: "a", lifetime: 300) { Data([1]) }
        clock.advance(1)
        _ = try await cache.data(key: "b", lifetime: 300) { Data([2]) }
        clock.advance(1)
        _ = try await cache.data(key: "a", lifetime: 300) { Data([99]) }
        clock.advance(1)
        _ = try await cache.data(key: "c", lifetime: 300) { Data([3]) }
        let a = try await cache.data(key: "a", lifetime: 300) { Data([99]) }
        XCTAssertEqual(a, Data([1]))
        let b = try await cache.data(key: "b", lifetime: 300) { Data([8]) }
        XCTAssertEqual(b, Data([8]))
        _ = try await cache.data(key: "huge", lifetime: 300) { Data(repeating: 9, count: 5) }
        let huge = try await cache.data(key: "huge", lifetime: 300) { Data([7]) }
        XCTAssertEqual(huge, Data([7]), "Responses above the byte budget cannot remain cached.")
    }

    func testKeysPartitionCredentialsParametersBodyAndURLSession() throws {
        let a = URLSession(configuration: .ephemeral), b = URLSession(configuration: .ephemeral)
        defer { a.invalidateAndCancel(); b.invalidateAndCancel() }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/search?query=dragon&page=1")))
        request.setValue("Bearer one", forHTTPHeaderField: "Authorization")
        let original = ResponseMemoryCache.key(for: request, session: a)
        XCTAssertEqual(original, ResponseMemoryCache.key(for: request, session: a))
        XCTAssertNotEqual(original, ResponseMemoryCache.key(for: request, session: b))
        request.setValue("Bearer two", forHTTPHeaderField: "Authorization")
        XCTAssertNotEqual(original, ResponseMemoryCache.key(for: request, session: a))
        request.setValue("Bearer one", forHTTPHeaderField: "Authorization")
        request.url = URL(string: "https://example.com/search?query=dragon&page=2")
        XCTAssertNotEqual(original, ResponseMemoryCache.key(for: request, session: a))
        request.url = URL(string: "https://example.com/search?query=dragon&page=1")
        request.httpMethod = "POST"; request.httpBody = Data("different query".utf8)
        XCTAssertNotEqual(original, ResponseMemoryCache.key(for: request, session: a))
    }
}

private actor CacheProbe {
    private(set) var calls = 0
    func next() -> Data { calls += 1; return Data([UInt8(calls)]) }
}

private final class CacheClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1000)
    var value: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}

private actor CacheGate {
    private(set) var calls = 0
    private var response: CheckedContinuation<Data, Never>?
    private var started: [CheckedContinuation<Void, Never>] = []
    func load() async -> Data {
        calls += 1
        return await withCheckedContinuation { continuation in
            response = continuation
            started.forEach { $0.resume() }; started = []
        }
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started.append($0) }
    }
    func finish() { response?.resume(returning: Data([9])); response = nil }
}
