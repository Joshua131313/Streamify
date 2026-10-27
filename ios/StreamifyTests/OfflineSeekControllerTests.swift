import XCTest
import AVFoundation
@testable import Streamify

final class OfflineSeekControllerTests: XCTestCase {
    @MainActor func testRapidSkipAndScrubKeepOneNativeSeekAndFinishAtLatestActualPosition() async throws {
        let driver = HeldSeekDriver()
        var results: [OfflineSeekController.Result] = []
        let controller = OfflineSeekController(driver: driver) { results.append($0) }
        defer { controller.cancel() }
        controller.seek(to: 13)
        controller.seek(to: try XCTUnwrap(controller.pendingTarget) + 10)
        controller.seek(to: try XCTUnwrap(controller.pendingTarget) + 10)
        controller.seek(to: 420)
        XCTAssertEqual(driver.requests.map(\.target), [13])
        XCTAssertEqual(driver.cancelCount, 0, "New thumb/skip positions must not cancel an active native seek.")
        driver.finish(0, actual: 13.1)
        await assertSettled { driver.requests.count == 2 }
        XCTAssertEqual(driver.requests.map(\.target), [13, 420])
        XCTAssertTrue(results.isEmpty, "An intermediate seek must not publish the stale requested position.")
        driver.finish(1, actual: 419.9)
        await assertSettled { !controller.isSeeking }
        XCTAssertNil(controller.pendingTarget)
        guard case .completed(let actual)? = results.last else { return XCTFail("Expected actual completion") }
        XCTAssertEqual(actual, 419.9, accuracy: 0.001)
    }

    @MainActor func testMissingCompletionRetriesOnceWithBoundedToleranceAndRejectsLateCompletion() async throws {
        let driver = HeldSeekDriver()
        var results: [OfflineSeekController.Result] = []
        let controller = OfflineSeekController(driver: driver, timeout: .milliseconds(100)) { results.append($0) }
        defer { controller.cancel() }
        controller.seek(to: 13)
        await assertSettled { driver.requests.count == 2 }
        XCTAssertEqual(driver.requests.map(\.tolerance), [0.25, 1])
        XCTAssertEqual(driver.cancelCount, 1)
        driver.finish(0, actual: 3)
        await Task.yield()
        XCTAssertTrue(controller.isSeeking)
        XCTAssertTrue(results.isEmpty, "The abandoned seek completion cannot settle the replacement request.")
        driver.finish(1, actual: 13.2)
        await assertSettled { !controller.isSeeking }
        guard case .completed(let actual)? = results.last else { return XCTFail("Expected recovered actual seek") }
        XCTAssertEqual(actual, 13.2, accuracy: 0.001)
    }

    @MainActor func testStalledNativeSeekEndsLoadingWithoutInventingTargetAndAllowsRetry() async throws {
        let driver = HeldSeekDriver()
        driver.currentSeconds = 3
        var results: [OfflineSeekController.Result] = []
        let controller = OfflineSeekController(driver: driver, timeout: .milliseconds(40)) { results.append($0) }
        defer { controller.cancel() }
        controller.seek(to: 13)
        await assertSettled { !controller.isSeeking }
        XCTAssertEqual(driver.requests.count, 2, "Recovery must be bounded, not an infinite retry loop.")
        XCTAssertNil(controller.pendingTarget)
        guard case .failed(let actual)? = results.last else { return XCTFail("A seek that never moved must fail") }
        XCTAssertEqual(actual, 3)
        controller.seek(to: 23)
        driver.finish(2, actual: 23)
        await assertSettled { !controller.isSeeking }
        guard case .completed(let retried)? = results.last else { return XCTFail("Controls must remain usable after a stalled seek") }
        XCTAssertEqual(retried, 23)
    }

    @MainActor func testTeardownCancelsDeadlineAndCannotApplyOldCompletionToAnotherVideo() async throws {
        let driver = HeldSeekDriver()
        var results: [OfflineSeekController.Result] = []
        let controller = OfflineSeekController(driver: driver, timeout: .milliseconds(30)) { results.append($0) }
        controller.seek(to: 100)
        controller.cancel()
        driver.finish(0, actual: 100)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(controller.isSeeking)
        XCTAssertNil(controller.pendingTarget)
        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor func testNativeSuccessWithoutRequestedMovementDoesNotFakeProgress() async throws {
        let driver = HeldSeekDriver()
        var results: [OfflineSeekController.Result] = []
        let controller = OfflineSeekController(driver: driver) { results.append($0) }
        defer { controller.cancel() }
        controller.seek(to: 13)
        driver.finish(0, actual: 3)
        await assertSettled { driver.requests.count == 2 }
        driver.finish(1, actual: 3)
        await assertSettled { !controller.isSeeking }
        guard case .failed(let actual)? = results.last else { return XCTFail("Success requires observed native movement") }
        XCTAssertEqual(actual, 3)
    }

    @MainActor private func assertSettled(file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async {
        let result = await settled(predicate)
        XCTAssertTrue(result, file: file, line: line)
    }

    @MainActor private func settled(timeout: Duration = .seconds(2), _ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }
}

@MainActor private final class HeldSeekDriver: OfflineSeekDriving {
    struct Request {
        let target: Double
        let tolerance: Double
        let completion: @Sendable (Bool) -> Void
    }
    var currentSeconds = 0.0
    var requests: [Request] = []
    var cancelCount = 0
    func seek(to seconds: Double, tolerance: Double, completion: @escaping @Sendable (Bool) -> Void) {
        requests.append(Request(target: seconds, tolerance: tolerance, completion: completion))
    }
    func cancelPendingSeeks() { cancelCount += 1 }
    func finish(_ index: Int, actual: Double, completed: Bool = true) {
        currentSeconds = actual; requests[index].completion(completed)
    }
}
