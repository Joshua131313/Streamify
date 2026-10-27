import Foundation
import XCTest
#if canImport(Streamify)
@testable import Streamify
#else
@testable import HLSResearchHost
#endif

/// Local delegate state contracts: synthetic callback values only, no native
/// session, provider, account, media file or completed library status. The
/// native fixture suite separately proves real package/cache/playback behavior.
@MainActor
final class HLSRestorationLifecycleTests: XCTestCase {
    func testAudioMetadataTimeoutPreservesAnAdoptedUnfinishedTransfer() {
        let identity = identity()
        let delegate = makeDelegate { _ in XCTFail("A metadata timeout must not manufacture a native terminal event") }
        _ = delegate.register(record(identity), audioGroup: nil, event: .restored)
        XCTAssertTrue(delegate.canResume(identity))
        XCTAssertTrue(delegate.needsAudioRebinding(identity))
        delegate.metadataRebindingFailed(identity, error: HLSDownloadSessionError.metadataTimedOut)
        XCTAssertTrue(delegate.canResume(identity))
        XCTAssertFalse(delegate.transportHasFinished(identity))
        let same = delegate.register(record(identity), audioGroup: nil, event: .restored)
        XCTAssertEqual(same.identity, identity)
        XCTAssertEqual(same.event, .restored)
        XCTAssertNil(same.error)
    }

    func testNativeSuccessWithoutKnownAudioRequestsVerificationOnceAndCannotComplete() async {
        let identity = identity()
        let required = expectation(description: "Native success requires missing audio metadata")
        let failed = expectation(description: "An unverified completed transport remains a visible failure")
        var events: [HLSDownloadSnapshot.Event] = []
        let delegate = makeDelegate { snapshot in
            events.append(snapshot.event)
            if snapshot.event == .transportFinishedAwaitingMetadata { required.fulfill() }
            if snapshot.event == .failed { failed.fulfill() }
        }
        _ = delegate.register(record(identity), audioGroup: nil, event: .restored)
        delegate.completedTransport(identity)
        delegate.finishPendingCompletion(identity)
        await fulfillment(of: [required], timeout: 2)
        XCTAssertTrue(delegate.transportHasFinished(identity))
        XCTAssertTrue(delegate.canResume(identity))
        XCTAssertFalse(events.contains(.completed))
        delegate.metadataRebindingFailed(identity, error: HLSDownloadSessionError.metadataTimedOut)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(delegate.canResume(identity))
        XCTAssertEqual(events.filter { $0 == .transportFinishedAwaitingMetadata }.count, 1)
        XCTAssertEqual(events.filter { $0 == .failed }.count, 1)
        XCTAssertFalse(events.contains(.completed))
    }

    func testCancellationWinsWhileCompletedTransportIsWaitingForAudioVerification() async {
        let identity = identity()
        let required = expectation(description: "Waiting for audio verification")
        let cancelled = expectation(description: "Explicit cancellation retained")
        var events: [HLSDownloadSnapshot.Event] = []
        let delegate = makeDelegate { snapshot in
            events.append(snapshot.event)
            if snapshot.event == .transportFinishedAwaitingMetadata { required.fulfill() }
            if snapshot.event == .cancelled { cancelled.fulfill() }
        }
        _ = delegate.register(record(identity), audioGroup: nil, event: .restored)
        delegate.completedTransport(identity)
        await fulfillment(of: [required], timeout: 2)
        delegate.cancel(identity, removePartialPackage: false)
        delegate.metadataRebindingFailed(identity, error: HLSDownloadSessionError.metadataTimedOut)
        delegate.completedTransport(identity)
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertFalse(delegate.canResume(identity))
        XCTAssertFalse(events.contains(.failed)); XCTAssertFalse(events.contains(.completed))
        XCTAssertEqual(events.filter { $0 == .cancelled }.count, 1)
    }

    func testGenuineNativeTransportFailureStillEmitsTheRealErrorOnce() async {
        let identity = identity()
        let failure = expectation(description: "Actual native error remains visible")
        var errors: [HLSDownloadFailure] = []
        let delegate = makeDelegate { snapshot in
            if snapshot.event == .failed, let error = snapshot.error { errors.append(error); failure.fulfill() }
        }
        _ = delegate.register(record(identity), audioGroup: nil, event: .restored)
        delegate.fail(identity, error: URLError(.networkConnectionLost))
        delegate.metadataRebindingFailed(identity, error: HLSDownloadSessionError.metadataTimedOut)
        delegate.fail(identity, error: URLError(.timedOut))
        await fulfillment(of: [failure], timeout: 2)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.domain, NSURLErrorDomain)
        XCTAssertEqual(errors.first?.code, URLError.networkConnectionLost.rawValue)
        XCTAssertFalse(delegate.canResume(identity))
    }

    func testActualPersistedSelectionDoesNotRequireARefreshToRemainKnown() {
        let identity = identity()
        var saved = record(identity)
        saved.selectedVariants = [HLSDownloadedVariant(width: 1920, height: 1080)]
        saved.selectedAudioLanguage = "en-US"
        let delegate = makeDelegate { _ in }
        let restored = delegate.register(saved, audioGroup: nil, event: .restored)
        XCTAssertEqual(restored.selectedAudioLanguage, "en-US")
        XCTAssertEqual(restored.selectedVariants, saved.selectedVariants)
        XCTAssertFalse(delegate.needsAudioRebinding(identity), "Known same-task native selection evidence must not require a fresh remote lookup.")
        XCTAssertFalse(restored.didFinishPackage)
        XCTAssertEqual(restored.event, .restored, "Selection alone cannot manufacture transport or package completion.")
    }

    private func identity() -> HLSDownloadIdentity { HLSDownloadIdentity(id: UUID(), attempt: UUID(), taskIdentifier: 42) }
    private func record(_ identity: HLSDownloadIdentity) -> HLSDownloadRestoreRecord {
        HLSDownloadRestoreRecord(identity: identity, quality: 1080, audioLanguage: "en")
    }
    private func makeDelegate(deliver: @escaping @MainActor (HLSDownloadSnapshot) -> Void) -> HLSAssetDownloadDelegate {
        HLSAssetDownloadDelegate(deliver: deliver, eventsFinished: {}, deliveryFinished: {}, removePartialPackage: { _, _ in })
    }
}
