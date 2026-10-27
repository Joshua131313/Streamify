import Foundation
import XCTest
@testable import Streamify

/// Persisted transfer contracts only: no native session, singleton store,
/// account, provider request, or downloaded package is created by these tests.
final class HLSDownloadStateTests: XCTestCase {
    func testLegacyProgressiveMetadataDecodesWithoutHLSFieldsOrLosingItsFile() throws {
        let id = UUID()
        let legacy = """
        {"id":"\(id.uuidString)","title":"Saved movie","source":"https://video.example.test/movie.mp4","fileName":"existing.mp4","createdAt":0,"status":"completed","bytesWritten":4096,"expectedBytes":4096}
        """
        let item = try JSONDecoder().decode(DownloadItem.self, from: Data(legacy.utf8))
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.fileName, "existing.mp4")
        XCTAssertEqual(item.progress, 1)
        XCTAssertNil(item.transport)
        XCTAssertNil(item.hlsAttempt)
        XCTAssertNil(item.hlsPackagePath)
        XCTAssertNil(item.pendingHLSPackagePath)
        XCTAssertNil(item.hlsFractionCompleted)
        XCTAssertNil(item.hlsIdentity)

        let restored = try roundTrip(item)
        XCTAssertEqual(restored.fileName, "existing.mp4")
        XCTAssertNil(restored.transport)
        XCTAssertNil(restored.hlsPackagePath)
    }

    func testProgressiveCallbacksCannotBindToAnHLSItemWithTheSameUUIDAndTaskNumber() throws {
        var progressive = DownloadItem(id: UUID(), title: "Episode", source: nil,
            createdAt: Date(timeIntervalSince1970: 123), status: .downloading)
        progressive.taskIdentifier = 42
        progressive.pendingFileName = "pending-existing.mp4"
        XCTAssertTrue(progressive.acceptsCallback(taskIdentifier: 42))
        XCTAssertTrue(progressive.acceptsValidation(taskIdentifier: 42, fileName: "pending-existing.mp4"))

        var hls = progressive
        hls.transport = .hlsVOD
        hls.hlsAttempt = UUID()
        XCTAssertFalse(hls.acceptsCallback(taskIdentifier: 42), "Native identifiers belong to their own session, even when integers and item UUIDs coincide.")
        XCTAssertFalse(hls.acceptsValidation(taskIdentifier: 42, fileName: "pending-existing.mp4"))
        XCTAssertTrue(hls.acceptsHLS(try XCTUnwrap(hls.hlsIdentity)))
        XCTAssertNil(progressive.hlsIdentity)
    }

    func testHLSCallbacksRequireExactItemAttemptTaskAndDownloadingStatus() throws {
        let item = activeHLS()
        let current = try XCTUnwrap(item.hlsIdentity)
        XCTAssertTrue(item.acceptsHLS(current))
        for stale in [
            HLSDownloadIdentity(id: UUID(), attempt: current.attempt, taskIdentifier: current.taskIdentifier),
            HLSDownloadIdentity(id: current.id, attempt: UUID(), taskIdentifier: current.taskIdentifier),
            HLSDownloadIdentity(id: current.id, attempt: current.attempt, taskIdentifier: current.taskIdentifier + 1)
        ] {
            XCTAssertFalse(item.acceptsHLS(stale))
        }
        for status in [DownloadStatus.cancelled, .failed, .completed] {
            var terminal = item
            terminal.status = status
            XCTAssertFalse(terminal.acceptsHLS(current), "A late callback must not revive a \(status.rawValue) item.")
        }
        var missingIdentity = item
        missingIdentity.taskIdentifier = nil
        XCTAssertNil(missingIdentity.hlsIdentity)
        XCTAssertFalse(missingIdentity.acceptsHLS(current))
        missingIdentity = item
        missingIdentity.hlsAttempt = nil
        XCTAssertNil(missingIdentity.hlsIdentity)
        XCTAssertFalse(missingIdentity.acceptsHLS(current))
    }

    func testRetryRejectsTheCancelledAttemptEvenWhenNativeTaskNumbersAreReused() throws {
        var item = activeHLS()
        let cancelled = try XCTUnwrap(item.hlsIdentity)
        item.status = .cancelled
        XCTAssertFalse(item.acceptsHLS(cancelled))

        item.hlsAttempt = UUID()
        item.status = .downloading
        let retry = try XCTUnwrap(item.hlsIdentity)
        XCTAssertEqual(retry.id, cancelled.id)
        XCTAssertEqual(retry.taskIdentifier, cancelled.taskIdentifier)
        XCTAssertNotEqual(retry.attempt, cancelled.attempt)
        XCTAssertFalse(item.acceptsHLS(cancelled), "Attempt identity must prevent a previous session's late callback from committing to Retry.")
        XCTAssertTrue(item.acceptsHLS(retry))
    }

    func testHLSPackageIdentityAndSelectionSurviveCodableRoundTrip() throws {
        var item = activeHLS()
        let identity = try XCTUnwrap(item.hlsIdentity)
        let relative = "Library/managed-assets/\(item.id.uuidString).movpkg"
        item.catalogKey = "tv:123:1:2"
        item.quality = 1080
        item.sourceAudioLanguage = "en"
        item.sourceProviderID = "VixSrc"
        item.hlsVerifiedVOD = true
        item.pendingHLSPackagePath = relative
        item.hlsSelectedVariants = [HLSDownloadedVariant(width: 1920, height: 1080)]
        item.hlsSelectedAudioLanguage = "en-US"
        item.hlsDidFinishPackage = true
        item.hlsTransferSucceeded = true
        item.hlsFractionCompleted = 1

        let pending = try roundTrip(item)
        XCTAssertEqual(pending.hlsIdentity, identity)
        XCTAssertEqual(pending.pendingHLSPackagePath, relative)
        XCTAssertEqual(pending.hlsSelectedVariants, item.hlsSelectedVariants)
        XCTAssertEqual(pending.hlsSelectedAudioLanguage, "en-US")
        XCTAssertEqual(pending.hlsDidFinishPackage, true)
        XCTAssertEqual(pending.hlsTransferSucceeded, true)
        XCTAssertEqual(pending.sourceProviderID, "VixSrc")
        XCTAssertNil(pending.fileURL, "A destination and successful transport do not publish a package before validation commits it.")

        item.hlsPackagePath = relative
        item.pendingHLSPackagePath = nil
        item.status = .completed
        item.taskIdentifier = nil
        let completed = try roundTrip(item)
        let package = try XCTUnwrap(completed.fileURL)
        XCTAssertEqual(package, HLSDownloadedPackages.fileURL(for: relative))
        XCTAssertEqual(try HLSDownloadedPackages.relativePath(of: package), relative)
        XCTAssertEqual(completed.catalogKey, "tv:123:1:2")
        XCTAssertEqual(completed.quality, 1080)
        XCTAssertNil(completed.fileName)
        XCTAssertNil(completed.hlsIdentity)
    }

    func testUnsafeOrUncommittedPackageCannotFallBackToRetainedProgressiveFile() {
        var item = activeHLS()
        item.fileName = "retained-original.mp4"
        item.status = .completed
        for path in ["../outside.movpkg", "Library/../Documents/episode.movpkg", "/Library/episode.movpkg",
                     "Documents/episode.movpkg", "Library/episode.mp4", "Library//episode.movpkg"] {
            item.hlsPackagePath = path
            XCTAssertNil(item.fileURL, path)
        }
        item.hlsPackagePath = "Library/managed-assets/episode.movpkg"
        XCTAssertNotNil(item.fileURL)
        for status in [DownloadStatus.downloading, .cancelled, .failed] {
            item.status = status
            XCTAssertNil(item.fileURL, "A retained package must not bypass the \(status.rawValue) transfer state.")
        }
        item.status = .completed
        item.hlsPackagePath = nil
        item.pendingHLSPackagePath = "Library/managed-assets/unfinished.movpkg"
        XCTAssertNil(item.fileURL)
    }

    func testHLSUsesItsRealFractionWithoutInventingByteCounts() throws {
        var item = activeHLS()
        item.hlsFractionCompleted = 0.375
        XCTAssertEqual(try XCTUnwrap(item.progress), 0.375, accuracy: 0.000001)
        XCTAssertEqual(item.bytesWritten, 0)
        XCTAssertEqual(item.expectedBytes, 0)

        item.bytesWritten = 9_000
        item.expectedBytes = 10_000
        XCTAssertEqual(try XCTUnwrap(item.progress), 0.375, accuracy: 0.000001,
            "A transport-specific time fraction must not accidentally become a byte fraction.")
        item.transport = .progressiveFile
        XCTAssertEqual(try XCTUnwrap(item.progress), 0.9, accuracy: 0.000001)
    }

    func testUnknownHLSProgressRemainsIndeterminateAndFiniteValuesAreBounded() {
        var item = activeHLS()
        item.bytesWritten = 100
        item.expectedBytes = 100
        XCTAssertNil(item.progress, "Old byte counters cannot fabricate HLS completion.")
        for invalid in [Double.nan, .infinity, -.infinity] {
            item.hlsFractionCompleted = invalid
            XCTAssertNil(item.progress)
        }
        item.hlsFractionCompleted = -0.25
        XCTAssertEqual(item.progress, 0)
        item.hlsFractionCompleted = 0
        XCTAssertEqual(item.progress, 0)
        item.hlsFractionCompleted = 1.25
        XCTAssertEqual(item.progress, 1)
    }

    private func activeHLS() -> DownloadItem {
        var item = DownloadItem(id: UUID(), title: "Show · S1 E2", source: "https://video.example.test/master.m3u8",
            createdAt: Date(timeIntervalSince1970: 123), status: .downloading)
        item.transport = .hlsVOD
        item.hlsAttempt = UUID()
        item.taskIdentifier = 42
        return item
    }

    private func roundTrip(_ item: DownloadItem) throws -> DownloadItem {
        try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
    }
}
