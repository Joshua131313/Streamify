import XCTest
import AVFoundation
@testable import Streamify

final class OfflineVideoValidationTests: XCTestCase {
    func testBundledH264VideoIsActuallyPlayableAndHasADecodableVideoTrack() async throws {
        let source = try XCTUnwrap(Bundle(for: DownloadStore.self).url(forResource: "offline-player", withExtension: "mp4"))
        let result = try await OfflineVideoValidation.validate(source)
        XCTAssertGreaterThan(result.duration, 0)
        let tracks = try await result.asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
        let decodable = try await XCTUnwrap(tracks.first).load(.isDecodable)
        XCTAssertTrue(decodable)
    }

    func testMissingEmptyAndDisguisedMP4AreRejectedWithoutDeletingOriginal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.mp4")
        await assertFailure(missing, expected: [.missingFile])
        let empty = directory.appendingPathComponent("empty.mp4")
        try Data().write(to: empty)
        await assertFailure(empty, expected: [.damagedFile])
        let invalid = directory.appendingPathComponent("not-a-video.mp4")
        let bytes = Data("<!doctype html><html>Expired source</html>".utf8)
        try bytes.write(to: invalid)
        await assertFailure(invalid, expected: [.damagedFile, .unplayable])
        XCTAssertEqual(try Data(contentsOf: invalid), bytes, "Compatibility inspection must not delete an existing download")
    }

    func testAudioOnlyAssetIsNotAcceptedAsAnOfflineMovie() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audio-only.wav")
        // A real, one-second 8 kHz PCM WAV, rather than a mocked asset result.
        var data = Data("RIFF".utf8)
        func little<T: FixedWidthInteger>(_ value: T) -> Data {
            var value = value.littleEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
        data += little(UInt32(36 + 16_000)); data += Data("WAVEfmt ".utf8)
        data += little(UInt32(16)); data += little(UInt16(1)); data += little(UInt16(1))
        data += little(UInt32(8_000)); data += little(UInt32(16_000))
        data += little(UInt16(2)); data += little(UInt16(16)); data += Data("data".utf8)
        data += little(UInt32(16_000)); data += Data(repeating: 0, count: 16_000)
        try data.write(to: url)
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audio.isEmpty, "The test must exercise an actual readable audio asset")
        await assertFailure(url, expected: [.noVideo])
    }

    func testImportRejectsInvalidFileAndKeepsTheUsersOriginal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("invalid.mp4")
        let bytes = Data("not a movie".utf8)
        try bytes.write(to: source)
        let downloads = try DownloadFiles.directory()
        func videoNames() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil)
                .filter { DownloadFiles.isSupported($0) }.map(\.lastPathComponent))
        }
        let before = try videoNames()
        do {
            _ = try await DownloadFiles.importVideo(source)
            XCTFail("An invalid import must never become a completed download")
        } catch {
            XCTAssertTrue(error is OfflineVideoError)
        }
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try videoNames(), before,
            "A rejected import must remove its copied staging file")
    }

    func testPendingValidationPersistsAndRejectsCancelledOrRetriedCallbacks() throws {
        let id = UUID()
        let name = "pending-\(id.uuidString)-17-\(UUID().uuidString).mp4"
        var item = DownloadItem(id: id, title: "Movie", source: "https://example.test/video.mp4",
            createdAt: Date(), status: .downloading, taskIdentifier: 17, pendingFileName: name)
        let restored = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item))
        XCTAssertTrue(restored.acceptsValidation(taskIdentifier: 17, fileName: name))
        XCTAssertEqual(restored.pendingFileName, name)
        item.status = .cancelled
        XCTAssertFalse(item.acceptsValidation(taskIdentifier: 17, fileName: name))
        item.status = .downloading; item.taskIdentifier = 18
        XCTAssertFalse(item.acceptsValidation(taskIdentifier: 17, fileName: name))
        XCTAssertFalse(item.acceptsValidation(taskIdentifier: 18, fileName: "another-file.mp4"))
        XCTAssertNotNil(try DownloadFiles.pendingURL(fileName: name, id: id))
        XCTAssertNil(try DownloadFiles.pendingURL(fileName: name, id: UUID()))
        XCTAssertNil(try DownloadFiles.pendingURL(fileName: "../\(name)", id: id))
    }

    func testValidationCancellationIsNotReclassifiedAsACodecError() async throws {
        let source = try XCTUnwrap(Bundle(for: DownloadStore.self).url(forResource: "offline-player", withExtension: "mp4"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OfflineVideoValidation.validate(source)
        }
        do { _ = try await task.value; XCTFail("Cancelled validation must not complete") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSourcePreflightUsesTheActualBundledH264AssetMetadata() async throws {
        let source = try XCTUnwrap(Bundle(for: DownloadStore.self).url(forResource: "offline-player", withExtension: "mp4"))
        try await OfflineVideoValidation.validateRemoteSource(source, timeout: 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Preflight only inspects the source and never changes its bytes")
    }

    func testUnreadableSourceMetadataStopsPreflightWithoutChangingOriginal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("unreadable.mp4")
        let bytes = Data("This is not media metadata.".utf8)
        try bytes.write(to: source)
        do {
            try await OfflineVideoValidation.validateRemoteSource(source, timeout: 3)
            XCTFail("Unreadable native metadata must fail preflight")
        } catch {
            XCTAssertTrue(error is OfflineSourceValidationError || error as? OfflineVideoError == .unplayable,
                "Unreadable metadata must stop transfer with availability or an explicit native format rejection: \(error)")
        }
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testSourcePreflightCancellationIsNotReclassifiedAsCompatibilityFailure() async throws {
        let source = try XCTUnwrap(Bundle(for: DownloadStore.self).url(forResource: "offline-player", withExtension: "mp4"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await OfflineVideoValidation.validateRemoteSource(source)
        }
        do { try await task.value; XCTFail("Cancelled source inspection must not continue") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testRemoteTransportErrorsTakePrecedenceOverMediaWrapperErrors() {
        let network = NSError(domain: NSURLErrorDomain, code: URLError.badServerResponse.rawValue)
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decoderNotFound.rawValue,
            userInfo: [NSUnderlyingErrorKey: network])
        XCTAssertTrue(OfflineSourceValidationError.classify(wrapped) is OfflineSourceValidationError,
            "A server/rate-limit failure must not become a codec verdict merely because AVFoundation wraps it")
        let unsupported = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decoderNotFound.rawValue)
        XCTAssertEqual(OfflineSourceValidationError.classify(unsupported) as? OfflineVideoError, .incompatible)
        XCTAssertTrue(OfflineSourceValidationError.classify(URLError(.timedOut)) is OfflineSourceValidationError)
        let format = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.fileFormatNotRecognized.rawValue)
        XCTAssertEqual(OfflineSourceValidationError.classify(format) as? OfflineVideoError, .unplayable,
            "An explicit native format rejection should permit inspecting another available file")
        let networkWrappedAsFormat = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.fileFormatNotRecognized.rawValue,
            userInfo: [NSUnderlyingErrorKey: network])
        XCTAssertTrue(OfflineSourceValidationError.classify(networkWrappedAsFormat) is OfflineSourceValidationError)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func assertFailure(_ url: URL, expected: Set<OfflineVideoError>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await OfflineVideoValidation.validate(url); XCTFail("Expected an invalid video", file: file, line: line) }
        catch let error as OfflineVideoError { XCTAssertTrue(expected.contains(error), "Unexpected error: \(error)", file: file, line: line) }
        catch { XCTFail("Expected a structured offline error: \(error)", file: file, line: line) }
    }
}
