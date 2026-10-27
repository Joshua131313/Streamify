import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import XCTest
@testable import Streamify

/// Manual local research, outside the ordinary application test directory.
/// Uses Apple's AVAssetExportPresetPassthrough only. No writer, transcoding,
/// atom/tag edits, custom resource loader, protected content or network is used.
final class ApplePassthroughExportDiagnosticsTests: XCTestCase {
    private let phaseSeconds: TimeInterval = 8

    @MainActor
    func testNativePassthroughPreservesHVC1BaselineAndRecordsHEV1Feasibility() async throws {
        executionTimeAllowance = 120
        let cases: [(String, String, AVFileType, String)] = [
            ("hevc-hvc1-aac-1080", "hvc1", .mp4, "mp4"),
            ("hevc-hev1-aac-1080", "hev1", .mp4, "mp4"),
            ("hevc-hev1-aac-1080", "hev1", .mov, "mov")
        ]
        for (fixture, inputPackaging, fileType, suffix) in cases {
            let report = try await experiment(fixture: fixture, inputPackaging: inputPackaging,
                                              fileType: fileType, suffix: suffix)
            record(report)
            if inputPackaging == "hvc1" {
                XCTAssertEqual(report["exportStatus"] as? String, "completed", "The working HVC1 control must export normally.")
                XCTAssertEqual(report["productionValidatorPassed"] as? Bool, true)
                XCTAssertEqual(report["fullVideoFramesDecoded"] as? Bool, true)
                XCTAssertEqual(report["fullAudioSamplesDecoded"] as? Bool, true)
                XCTAssertEqual(report["qualityPreserved"] as? Bool, true)
                XCTAssertEqual(report["videoCodecPreserved"] as? Bool, true)
                XCTAssertEqual(report["audioCodecPreserved"] as? Bool, true)
                XCTAssertEqual(report["audioFormatPreserved"] as? Bool, true)
            }
            // A successful export alone is not evidence that an unsupported
            // input became playable, and a research failure is not suppressed.
            if report["productionValidatorPassed"] as? Bool == true {
                XCTAssertEqual(report["fullVideoFramesDecoded"] as? Bool, true)
                XCTAssertEqual(report["fullAudioSamplesDecoded"] as? Bool, true)
                XCTAssertEqual(report["qualityPreserved"] as? Bool, true)
                XCTAssertEqual(report["videoCodecPreserved"] as? Bool, true)
                XCTAssertEqual(report["audioCodecPreserved"] as? Bool, true)
                XCTAssertEqual(report["audioFormatPreserved"] as? Bool, true)
            } else if inputPackaging == "hev1" {
                XCTAssertNotNil(report["failure"], "An unsupported result must retain its actual native failure.")
            }
            XCTAssertEqual(report["inputUnchanged"] as? Bool, true)
        }
    }

    @MainActor
    private func experiment(fixture: String, inputPackaging: String,
                            fileType: AVFileType, suffix: String) async throws -> [String: Any] {
        let bundle = Bundle(for: ApplePassthroughExportDiagnosticsTests.self)
        let source = try XCTUnwrap(bundle.url(forResource: fixture, withExtension: "mp4")
            ?? bundle.url(forResource: fixture, withExtension: "mp4", subdirectory: "Fixtures"))
        XCTAssertTrue(source.isFileURL)
        let original = try Data(contentsOf: source)
        XCTAssertLessThan(original.count, 1024 * 1024, "Only the controlled one-second synthetic fixtures belong in this experiment.")

        let manager = FileManager.default
        let temporaryRoot = manager.temporaryDirectory.resolvingSymlinksInPath()
        let owned = temporaryRoot.appendingPathComponent("streamify-apple-passthrough-\(UUID().uuidString)", isDirectory: true)
        guard owned.deletingLastPathComponent().standardizedFileURL == temporaryRoot.standardizedFileURL else {
            throw ProbeError.message("Temporary output escaped the owned diagnostic directory")
        }
        try manager.createDirectory(at: owned, withIntermediateDirectories: false)
        defer {
            // This fresh, verified child directory contains only this case's
            // export and Apple's temporary files. Never remove a fixture.
            if owned.deletingLastPathComponent().standardizedFileURL == temporaryRoot.standardizedFileURL {
                try? manager.removeItem(at: owned)
            }
        }
        let output = owned.appendingPathComponent("apple-passthrough.\(suffix)")
        let asset = AVURLAsset(url: source)
        defer { asset.cancelLoading() }
        var report: [String: Any] = [
            "observedAt": ISO8601DateFormatter().string(from: Date()),
            "fixture": fixture, "knownInputPackaging": inputPackaging,
            "sourceBytes": original.count, "sourceSHA256": digest(original),
            "requestedContainer": suffix, "preset": AVAssetExportPresetPassthrough,
            "globalPassthroughPresetAvailable": AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetPassthrough),
            "phaseDeadlineSeconds": phaseSeconds, "manualMediaRewriting": false,
            "transcoding": false, "networkRequests": 0, "productionPipelineChanged": false
        ]
        var phase = "source native metadata"
        let sourceBudget = budget { asset.cancelLoading() }
        do {
            do { report["sourceIsExportable"] = try await asset.load(.isExportable) }
            catch { report["sourceExportableError"] = errorChain(error) }
            let protected = try await asset.load(.hasProtectedContent)
            report["sourceProtected"] = protected
            guard !protected else { throw ProbeError.message("Protected content is outside this experiment") }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, duration < 2 else {
                throw ProbeError.message("The controlled source is not a complete one-second fixture")
            }
            report["sourceDurationSeconds"] = duration
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            report["sourceVideoFormats"] = try await formats(video)
            let sourceAudioFormats = try await formats(audio)
            report["sourceAudioFormats"] = sourceAudioFormats
            guard video.count == 1, audio.count == 1 else { throw ProbeError.message("The controlled fixture must have one video and one audio track") }
            sourceBudget.cancel()

            // Compressed reads are read-only public AVAssetReader outputs with
            // nil settings. Digests describe what Apple exposes; no encoded
            // byte, sample description or parameter set is changed by us.
            var originalVideo: Samples?, originalAudio: Samples?
            do { originalVideo = try samples(asset, track: video[0], settings: nil, decodeVideo: false) }
            catch { report["sourceCompressedVideoReadError"] = errorChain(error) }
            do { originalAudio = try samples(asset, track: audio[0], settings: nil, decodeVideo: false) }
            catch { report["sourceCompressedAudioReadError"] = errorChain(error) }

            phase = "native passthrough export"
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw ProbeError.message("Apple could not create a passthrough export session for this source")
            }
            defer { exporter.cancelExport() }
            report["actualExportPreset"] = exporter.presetName
            report["supportedFileTypes"] = exporter.supportedFileTypes.map(\.rawValue)
            guard exporter.supportedFileTypes.contains(fileType) else {
                throw ProbeError.message("Apple does not advertise this output container for the passthrough session")
            }
            exporter.outputURL = output
            exporter.outputFileType = fileType
            exporter.directoryForTemporaryFiles = owned
            // Entire fixture, original time range and tracks; no composition,
            // audio mix, quality preset or file-length truncation is configured.
            let exportBudget = budget { exporter.cancelExport() }
            exporter.exportAsynchronously { }
            let deadline = Date().addingTimeInterval(phaseSeconds)
            while [.unknown, .waiting, .exporting].contains(exporter.status), Date() < deadline {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            exportBudget.cancel()
            if [.unknown, .waiting, .exporting].contains(exporter.status) {
                exporter.cancelExport()
                // Let Apple's own cancellation settle before removing only our
                // output directory. Export + cancellation stays below 10s.
                let cancellationDeadline = Date().addingTimeInterval(1)
                while [.unknown, .waiting, .exporting].contains(exporter.status), Date() < cancellationDeadline {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            }
            report["exportStatus"] = status(exporter.status)
            if let error = exporter.error { report["nativeExportError"] = errorChain(error) }
            guard exporter.status == .completed else {
                exporter.cancelExport()
                throw exporter.error ?? ProbeError.message("Passthrough export did not complete within the eight-second deadline")
            }

            phase = "exported native format and quality"
            let size = try output.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard size.isRegularFile == true, let bytes = size.fileSize, bytes > 0, bytes <= 16 * 1024 * 1024 else {
                throw ProbeError.message("Export did not produce a bounded complete output file")
            }
            report["outputBytes"] = bytes
            report["outputSHA256"] = digest(try Data(contentsOf: output))
            let result = AVURLAsset(url: output)
            defer { result.cancelLoading() }
            let outputBudget = budget { result.cancelLoading() }
            defer { outputBudget.cancel() }
            let outputVideo = try await result.loadTracks(withMediaType: .video)
            let outputAudio = try await result.loadTracks(withMediaType: .audio)
            let videoFormats = try await formats(outputVideo), audioFormats = try await formats(outputAudio)
            report["outputVideoFormats"] = videoFormats
            report["outputAudioFormats"] = audioFormats
            guard outputVideo.count == 1, outputAudio.count == 1 else { throw ProbeError.message("Export lost a video or audio track") }
            let videoDescriptions = try await outputVideo[0].load(.formatDescriptions)
            let audioDescriptions = try await outputAudio[0].load(.formatDescriptions)
            let videoTypes = videoDescriptions.map { CMFormatDescriptionGetMediaSubType($0) }
            let audioTypes = audioDescriptions.map { CMFormatDescriptionGetMediaSubType($0) }
            report["videoCodecPreserved"] = !videoTypes.isEmpty && videoTypes.allSatisfy { ["hvc1", "hev1"].contains(fourCC($0)) }
            report["audioCodecPreserved"] = !audioTypes.isEmpty && audioTypes.allSatisfy { $0 == kAudioFormatMPEG4AAC }
            report["audioFormatPreserved"] = try JSONSerialization.data(withJSONObject: sourceAudioFormats, options: [.sortedKeys])
                == JSONSerialization.data(withJSONObject: audioFormats, options: [.sortedKeys])
            // Native FourCCs are retained separately because Apple may expose
            // HEVC's semantic subtype rather than the container's sample tag.
            report["nativeOutputVideoFourCC"] = videoTypes.map(fourCC)
            report["nativeOutputAudioFourCC"] = audioTypes.map(fourCC)
            let natural = try await outputVideo[0].load(.naturalSize)
            guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0,
                  natural.width <= 65_535, natural.height <= 65_535 else {
                throw ProbeError.message("Exported native video dimensions are invalid")
            }
            let width = Int(natural.width.rounded()), height = Int(natural.height.rounded())
            report["outputWidth"] = width; report["outputHeight"] = height
            try OfflineVideoValidation.requireQuality(1080, width: width, height: height)
            report["qualityPreserved"] = width == 1920 && height == 1080
            let exportedDuration = try await result.load(.duration).seconds
            guard exportedDuration.isFinite, abs(exportedDuration - duration) <= 0.1 else {
                throw ProbeError.message("Passthrough export changed the complete fixture duration")
            }
            report["outputDurationSeconds"] = exportedDuration
            outputBudget.cancel()

            let exportedVideo = try samples(result, track: outputVideo[0], settings: nil, decodeVideo: false)
            let exportedAudio = try samples(result, track: outputAudio[0], settings: nil, decodeVideo: false)
            if let originalVideo {
                report["compressedVideoPayloadUnchanged"] = originalVideo.digest == exportedVideo.digest
                report["sourceVideoSamples"] = originalVideo.count; report["outputVideoSamples"] = exportedVideo.count
                report["sourceVideoMarkerBuffers"] = originalVideo.markers; report["outputVideoMarkerBuffers"] = exportedVideo.markers
            }
            if let originalAudio {
                report["compressedAudioPayloadUnchanged"] = originalAudio.digest == exportedAudio.digest
                report["sourceAudioSamples"] = originalAudio.count; report["outputAudioSamples"] = exportedAudio.count
                report["sourceAudioMarkerBuffers"] = originalAudio.markers; report["outputAudioMarkerBuffers"] = exportedAudio.markers
            }

            phase = "full one-second native video and audio decode"
            let decodedVideo = try samples(result, track: outputVideo[0], settings:
                [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA], decodeVideo: true)
            let decodedAudio = try samples(result, track: outputAudio[0], settings:
                [AVFormatIDKey: kAudioFormatLinearPCM], decodeVideo: false)
            report["decodedVideoFrames"] = decodedVideo.count
            report["decodedAudioSamples"] = decodedAudio.count
            report["decodedAudioBuffers"] = decodedAudio.buffers
            report["decodedVideoMarkerBuffers"] = decodedVideo.markers
            report["decodedAudioMarkerBuffers"] = decodedAudio.markers
            report["decodedAudioBytes"] = decodedAudio.bytes
            report["fullVideoFramesDecoded"] = decodedVideo.count > 0 && decodedVideo.completed
            report["fullAudioSamplesDecoded"] = decodedAudio.count > 0 && decodedAudio.bytes > 0 && decodedAudio.completed

            phase = "exact production local validator"
            let validation = Task { try await OfflineVideoValidation.validate(output) }
            let validationBudget = budget { validation.cancel() }
            defer { validationBudget.cancel(); validation.cancel() }
            let accepted = try await validation.value
            report["productionValidatorPassed"] = true
            report["productionValidatorCodecs"] = accepted.codecs
            report["actualFrameDecoded"] = true
            report["outcome"] = "Apple passthrough output passed full fixture video/audio decode and production frame validation"
        } catch {
            report["failurePhase"] = phase
            report["failure"] = errorChain(error)
            report["outcome"] = "Unsupported or unverified; no production conversion path is enabled"
        }
        sourceBudget.cancel()
        report["inputUnchanged"] = (try Data(contentsOf: source)) == original
        return report
    }

    private struct Samples {
        let count: Int
        let buffers: Int
        let markers: Int
        let bytes: Int
        let digest: String
        let completed: Bool
    }

    private func samples(_ asset: AVAsset, track: AVAssetTrack, settings: [String: Any]?, decodeVideo: Bool) throws -> Samples {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ProbeError.message("Native reader refused the requested track output") }
        reader.add(output)
        let watchdog = budget { reader.cancelReading() }
        defer { watchdog.cancel(); reader.cancelReading() }
        guard reader.startReading() else { throw reader.error ?? ProbeError.message("Native reader could not start") }
        let deadline = Date().addingTimeInterval(phaseSeconds)
        var count = 0, buffers = 0, markers = 0, bytes = 0
        var hasher = SHA256()
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard Date() < deadline, buffers < 512 else { throw ProbeError.message("Native sample-reader deadline or buffer budget reached") }
            buffers += 1
            // A decoded PCM buffer contains hundreds/thousands of audio
            // frames. Bound buffer allocations separately from media samples;
            // otherwise a valid 48kHz one-second control falsely fails here.
            let sampleCount = CMSampleBufferGetNumSamples(sample)
            // AVAssetReader can return zero-sample edit/format marker buffers.
            // They consume the buffer/deadline budget but are not decoded
            // media, and must never count as positive video/audio evidence.
            if sampleCount == 0 { markers += 1; continue }
            guard sampleCount > 0, sampleCount <= 500_000, count <= 500_000 - sampleCount else {
                throw ProbeError.message("Native media-sample budget reached (sampleCount=\(sampleCount), total=\(count), buffers=\(buffers), markerBuffers=\(markers), decodedVideo=\(decodeVideo))")
            }
            count += sampleCount
            if decodeVideo {
                guard let frame = CMSampleBufferGetImageBuffer(sample),
                      CVPixelBufferGetWidth(frame) == 1920, CVPixelBufferGetHeight(frame) == 1080 else {
                    throw ProbeError.message("Native decoder did not produce a real full-resolution frame")
                }
            } else if let block = CMSampleBufferGetDataBuffer(sample) {
                let length = CMBlockBufferGetDataLength(block)
                guard length > 0, length <= 4 * 1024 * 1024, bytes <= 4 * 1024 * 1024 - length else {
                    throw ProbeError.message("Native sample-byte budget reached")
                }
                var data = Data(count: length)
                let copied = data.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
                }
                guard copied == kCMBlockBufferNoErr else { throw ProbeError.message("Native sample bytes could not be read") }
                bytes += length; hasher.update(data: data)
            }
        }
        guard reader.status == .completed else { throw reader.error ?? ProbeError.message("Native reader did not finish the entire one-second fixture") }
        return Samples(count: count, buffers: buffers, markers: markers, bytes: bytes, digest: hasher.finalize().map { String(format: "%02x", $0) }.joined(), completed: true)
    }

    private func formats(_ tracks: [AVAssetTrack]) async throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        for track in tracks {
            let descriptions = try await track.load(.formatDescriptions)
            for format in descriptions {
                var item: [String: Any] = ["fourCC": fourCC(CMFormatDescriptionGetMediaSubType(format))]
                if CMFormatDescriptionGetMediaType(format) == kCMMediaType_Video {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                    item["width"] = Int(dimensions.width); item["height"] = Int(dimensions.height)
                } else if CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio,
                          let audio = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    guard audio.mSampleRate.isFinite, audio.mSampleRate > 0 else {
                        throw ProbeError.message("Native audio format has an invalid sample rate")
                    }
                    item["sampleRate"] = audio.mSampleRate; item["channels"] = audio.mChannelsPerFrame
                    item["formatID"] = fourCC(audio.mFormatID)
                }
                result.append(item)
            }
        }
        return result
    }

    private func budget(_ cancel: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: cancel)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + phaseSeconds, execute: work)
        return work
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func fourCC(_ value: FourCharCode) -> String {
        String(decoding: [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)], as: UTF8.self)
    }
    private func status(_ value: AVAssetExportSession.Status) -> String {
        switch value {
        case .unknown: return "unknown"
        case .waiting: return "waiting"
        case .exporting: return "exporting"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "future-status"
        }
    }
    private enum ProbeError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
    private func errorChain(_ error: Error) -> String {
        var values: [String] = [], current: NSError? = error as NSError
        for _ in 0..<6 {
            guard let item = current else { break }
            values.append("\(item.domain):\(item.code) \(item.localizedDescription)")
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return values.joined(separator: " → ")
    }
    private func record(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { XCTFail("Could not encode diagnostic JSON"); return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Apple passthrough \(report["knownInputPackaging"] ?? "unknown") \(report["requestedContainer"] ?? "unknown")"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("APPLE_PASSTHROUGH_DIAGNOSTIC \(json)")
    }
}
