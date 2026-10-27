import AVFoundation
import CoreVideo
import Foundation
import XCTest
@testable import Streamify

/// These independently encoded synthetic clips contain the same one-second
/// 1080p Main8-bit HEVC scene and AAC audio, with hvc1 versus hev1 packaging.
/// The actual H.264 source fixture is a bounded one-second passthrough sample.
/// No network, provider account, protected video, or production retagging.
final class HEVCPackagingDiagnosticsTests: XCTestCase {
    @MainActor
    func testHvc1AndHev1CompareNativeMetadataActualFrameAndPlayback() async throws {
        let hvc1 = try await inspectFixture("hevc-hvc1-aac-1080", expectedTag: "hvc1")
        let hev1 = try await inspectFixture("hevc-hev1-aac-1080", expectedTag: "hev1")
        let actualSource = try await inspectFixture("from-s1e1-daratech-native-first-second", expectedTag: "avc1")
        record(hvc1)
        record(hev1)
        record(actualSource)

        XCTAssertEqual(hvc1.width, 1920)
        XCTAssertEqual(hvc1.height, 1080)
        XCTAssertTrue(hvc1.nativeTags.contains("hvc1"))
        XCTAssertTrue(hvc1.frameDecoded, "The normal Main8-bit hvc1 fixture must decode a real frame: \(hvc1.frameError)")
        XCTAssertTrue(hvc1.playerAdvanced, "The hvc1 fixture must actually play, not only load metadata: \(hvc1.playerError)")
        XCTAssertTrue(hvc1.localValidatorPassed, "The production validator must accept the working hvc1 fixture")
        XCTAssertEqual(actualSource.width, 1920)
        XCTAssertEqual(actualSource.height, 1080)
        XCTAssertTrue(actualSource.nativeTags.contains("avc1"))
        XCTAssertTrue(actualSource.frameDecoded, "The actual1080p H.264 source must decode a real frame: \(actualSource.frameError)")
        XCTAssertTrue(actualSource.playerAdvanced, "The actual source must play, not only advertise readable metadata: \(actualSource.playerError)")
        XCTAssertTrue(actualSource.preflightPassed, "The actual H.264 source must pass the production native metadata check: \(actualSource.preflightError)")
        XCTAssertTrue(actualSource.localValidatorPassed, "The actual source must pass local native frame validation: \(actualSource.localValidatorError)")

        // An unsupported hev1 result is diagnostic evidence, not a claim that
        // every Apple decoder supports the format. A file which really plays
        // must never be rejected solely by a metadata capability flag.
        if hev1.frameDecoded && hev1.playerAdvanced {
            XCTAssertTrue(hev1.localValidatorPassed,
                "A real decoded and playing hev1 file was rejected by the local metadata gate: \(hev1.localValidatorError)")
            XCTAssertTrue(hev1.preflightPassed,
                "The same playable hev1 file was rejected by the preflight metadata gate: \(hev1.preflightError)")
        } else {
            XCTAssertFalse(hev1.localValidatorPassed,
                "A file with failed real frame/playback must not be accepted as a completed download")
            XCTAssertFalse(hev1.frameError.isEmpty && hev1.playerError.isEmpty,
                "A non-playing clip must include the actual native error, rather than silently timing out")
        }
    }

    private struct NativeReport: Codable {
        let fixture: String
        let encodedTag: String
        var width = 0
        var height = 0
        var nativeTags: [String] = []
        var assetPlayable: Bool? = nil
        var videoDecodable: Bool? = nil
        var videoPlayable: Bool? = nil
        var metadataError = ""
        var frameDecoded = false
        var frameError = ""
        var playerAdvanced = false
        var playerProducedFrame = false
        var playerTime = 0.0
        var playerStatus = "unknown"
        var playerError = ""
        var preflightPassed = false
        var preflightError = ""
        var localValidatorPassed = false
        var localValidatorError = ""
    }

    @MainActor
    private func inspectFixture(_ name: String, expectedTag: String) async throws -> NativeReport {
        let bundle = Bundle(for: HEVCPackagingDiagnosticsTests.self)
        let file = try XCTUnwrap(bundle.url(forResource: name, withExtension: "mp4")
            ?? bundle.url(forResource: name, withExtension: "mp4", subdirectory: "Fixtures"))
        let original = try Data(contentsOf: file)
        // Controlled fixtures are independently verified with FFmpeg. Native
        // metadata may itself fail for unsupported packaging; record that
        // instead of inventing dimensions from the filename or expected tag.
        XCTAssertNotNil(original.range(of: Data(expectedTag.utf8)))
        XCTAssertNotNil(original.range(of: Data("mp4a".utf8)), "The controlled fixture contains an AAC track")
        var report = NativeReport(fixture: name, encodedTag: expectedTag)
        let asset = AVURLAsset(url: file)
        defer { asset.cancelLoading() }
        do { report.assetPlayable = try await asset.load(.isPlayable) }
        catch { report.metadataError = errorChain(error) }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let (size, formats) = try await track.load(.naturalSize, .formatDescriptions)
                if size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                   size.width <= 65_535, size.height <= 65_535 {
                    report.width = Int(size.width.rounded()); report.height = Int(size.height.rounded())
                }
                report.nativeTags = formats.map { format in
                    let code = CMFormatDescriptionGetMediaSubType(format)
                    return String(decoding: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255),
                        UInt8((code >> 8) & 255), UInt8(code & 255)], as: UTF8.self)
                }
                report.videoDecodable = try? await track.load(.isDecodable)
                report.videoPlayable = try? await track.load(.isPlayable)
            }
        } catch { report.metadataError += " " + errorChain(error) }

        // Deliberately attempt real decode even when metadata says unplayable.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.appliesPreferredTrackTransform = true
        defer { generator.cancelAllCGImageGeneration() }
        do {
            report.frameDecoded = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        let result = try await generator.image(at: .zero)
                        return result.image.width > 0 && result.image.height > 0
                    } onCancel: { generator.cancelAllCGImageGeneration() }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next() ?? false
            }
        } catch { report.frameError = errorChain(error) }

        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.allowsExternalPlayback = false
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        player.play()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try Task.checkCancellation()
            if item.status == .failed {
                report.playerError = item.error.map(errorChain) ?? "AVPlayerItem failed without an error"
                break
            }
            let time = item.currentTime()
            let seconds = time.seconds
            if seconds.isFinite { report.playerTime = seconds; report.playerAdvanced = seconds > 0.04 }
            if output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                report.playerProducedFrame = CVPixelBufferGetWidth(buffer) > 0
            }
            if report.playerAdvanced && report.playerProducedFrame { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        report.playerStatus = item.status == .readyToPlay ? "readyToPlay" : item.status == .failed ? "failed" : "unknown"
        if !report.playerAdvanced && report.playerError.isEmpty { report.playerError = "No playback advancement within5seconds" }
        player.pause()

        do { try await OfflineVideoValidation.validateRemoteSource(file, timeout: 5); report.preflightPassed = true }
        catch { report.preflightError = errorChain(error) }
        do { _ = try await OfflineVideoValidation.validate(file); report.localValidatorPassed = true }
        catch { report.localValidatorError = errorChain(error) }
        XCTAssertEqual(try Data(contentsOf: file), original, "Diagnostic validation must not rewrite sample tags or encoded bytes")
        return report
    }

    private func errorChain(_ error: Error) -> String {
        var values: [String] = []
        var current: NSError? = error as NSError
        for _ in 0..<6 {
            guard let item = current else { break }
            values.append("\(item.domain):\(item.code) \(item.localizedDescription)")
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return values.joined(separator: " → ")
    }

    private func record(_ report: NativeReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Native video packaging \(report.encodedTag)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("HEVC_NATIVE_DIAGNOSTIC \(json)")
    }
}
