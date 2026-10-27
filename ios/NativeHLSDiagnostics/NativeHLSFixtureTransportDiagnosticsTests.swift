import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit
import XCTest
@testable import HLSResearchHost

/// Manual research only: isolate real native fixture playback from native
/// offline transfer, with an Apple-published transport control. No provider
/// episode, relay, custom loader, private headers or manual key reads.
@MainActor
final class NativeHLSFixtureTransportDiagnosticsTests: XCTestCase {
    private static let raw = URL(string: "https://raw.githubusercontent.com/Joshua131313/Streamify/cf27bf56346bf94f12a55a0556f1f14be048b3fd/ios/NativeHLSDiagnostics/Fixtures/offline-hls-control/clear/master.m3u8")!
    // Literal URL from Apple's published example HTML, retrieved normally:
    // https://developer.apple.com/streaming/examples/advanced-stream-hevc.html
    private static let apple = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8")!

    func testRawFixturePlaybackAndBoundedDownloadWithPublishedAppleControl() async {
        executionTimeAllowance = 2 * 60
        var report: [String: Any] = ["manualOnly": true, "providerEpisodeDownloaded": false,
            "manualKeyFetch": false, "completeOfflinePersistenceProven": false,
            "maximumObservedBytesPerDownload": 2 * 1024 * 1024, "maximumTransferSecondsPerDownload": 12,
            "networkActuallyDisabled": false, "observedAt": ISO8601DateFormatter().string(from: Date())]
        do { report["rawRealPlayback"] = try await Self.previewRawFixture() }
        catch { report["rawPlaybackError"] = Self.errorChain(error); XCTFail("Raw fixture native playback failed: \(HLSDownloadFailure(error).message)") }
        // Fresh assets and the public native background-session transport
        // distinguish playback buffering from offline transfer acceptance.
        for (name, url, fullHD) in [("rawFixture", Self.raw, true), ("applePublished", Self.apple, false)] {
            do {
                let result = try await Self.download(url, fullHD: fullHD)
                report[name] = result
                XCTAssertEqual(result["firstMediaRangeAccepted"] as? Bool, true, "\(name) did not accept any real media range; inspect native metrics")
                XCTAssertEqual(result["callbackCompleted"] as? Bool, true, "\(name) did not complete its bounded native task callback")
                XCTAssertNil(result["packageByteCounterError"], "\(name) could not verify its owned package byte count")
                XCTAssertNil((result["cleanup"] as? [String: Any])?["error"], "\(name) could not remove its own native package")
            } catch {
                report[name] = ["error": Self.errorChain(error)]
                XCTFail("\(name) native transport diagnostic failed: \(HLSDownloadFailure(error).message)")
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Bounded native HLS transport isolation"; attachment.lifetime = .keepAlways; add(attachment)
            print("NATIVE_HLS_TRANSPORT_DIAGNOSTIC \(text)")
        }
    }

    private static func previewRawFixture() async throws -> [String: Any] {
        let asset = AVURLAsset(url: raw)
        let watchdog = Task { try? await Task.sleep(nanoseconds: 15_000_000_000); if !Task.isCancelled { asset.cancelLoading() } }
        defer { watchdog.cancel(); asset.cancelLoading() }
        guard let group = try await asset.loadMediaSelectionGroup(for: .audible),
              let english = group.options.first(where: { $0.isPlayable && OfflineHLSValidation.isRequestedLanguage($0, language: "en") }) else {
            throw DiagnosticError.message("Raw fixture did not offer playable English audio")
        }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .moviePlayback); try audio.setActive(true)
        defer { try? audio.setActive(false, options: .notifyOthersOnDeactivation) }
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item); player.volume = 0.1; player.allowsExternalPlayback = false
        guard let view = (UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first)?.rootViewController?.view else {
            throw DiagnosticError.message("Research host has no visible playback surface")
        }
        let layer = AVPlayerLayer(player: player); layer.frame = view.bounds; view.layer.addSublayer(layer)
        defer { player.pause(); player.replaceCurrentItem(with: nil); layer.removeFromSuperlayer() }
        var width = 0, height = 0, seconds = 0.0, started = false
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if item.status == .failed { throw item.error ?? DiagnosticError.message("Native raw-fixture player failed") }
            if !started && item.status == .readyToPlay { item.select(english, in: group); player.playImmediately(atRate: 1); started = true }
            let time = item.currentTime()
            if time.seconds.isFinite { seconds = time.seconds }
            if output.hasNewPixelBuffer(forItemTime: time), let pixel = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                width = CVPixelBufferGetWidth(pixel); height = CVPixelBufferGetHeight(pixel)
            }
            if width == 1920 && height == 1080 && seconds >= 1 { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard width == 1920, height == 1080, seconds >= 1,
              let selected = item.currentMediaSelection.selectedMediaOption(in: group), selected.isPlayable,
              OfflineHLSValidation.isRequestedLanguage(selected, language: "en") else {
            throw DiagnosticError.message("Raw fixture did not render advancing 1080p pixels with selected playable English audio")
        }
        return ["pixelWidth": width, "pixelHeight": height, "playbackSeconds": seconds,
            "selectedEnglish": item.currentMediaSelection.selectedMediaOption(in: group)?.extendedLanguageTag ?? "unknown",
            "layerReady": layer.isReadyForDisplay, "decodedAudioPCMProven": false]
    }

    private static func download(_ url: URL, fullHD: Bool) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let watchdog = Task { try? await Task.sleep(nanoseconds: 35_000_000_000); if !Task.isCancelled { asset.cancelLoading() } }
        defer { watchdog.cancel(); asset.cancelLoading() }
        let all = try await asset.load(.variants)
        let h264 = all.filter { $0.videoAttributes?.codecTypes.contains(kCMVideoCodecType_H264) == true }
        let candidates = h264.filter { variant in
            guard let size = variant.videoAttributes?.presentationSize else { return false }
            return fullHD ? (size.width == 1920 && size.height == 1080) : (size.width == 416 && size.height == 234)
        }
        // Apple comparison uses its smallest H.264 tier so the bounded first
        // segment stays tiny. It is a transport control, not 1080p verification.
        let preferred = try await asset.load(.preferredMediaSelection)
        guard let variant = candidates.min(by: { ($0.peakBitRate ?? .greatestFiniteMagnitude) < ($1.peakBitRate ?? .greatestFiniteMagnitude) }),
              let group = try await asset.loadMediaSelectionGroup(for: .audible),
              let english = group.options.first(where: { $0.isPlayable && OfflineHLSValidation.isRequestedLanguage($0, language: "en") }),
              let selection = preferred.mutableCopy() as? AVMutableMediaSelection else {
            throw DiagnosticError.message("Published transport control lacks the selected H.264/English configuration")
        }
        selection.select(english, in: group)
        let delegate = NativeTransportDelegate()
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.streamify.hls.transport.\(UUID().uuidString)")
        configuration.isDiscretionary = false; configuration.sessionSendsLaunchEvents = false
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 15
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: delegate, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        let download = AVAssetDownloadConfiguration(asset: asset, title: "Bounded native transport control")
        download.primaryContentConfiguration.variantQualifiers = [AVAssetVariantQualifier(variant: variant)]
        download.primaryContentConfiguration.mediaSelections = [selection]
        let task = session.makeAssetDownloadTask(downloadConfiguration: download)
        let identity = HLSDownloadIdentity(id: UUID(), attempt: UUID(), taskIdentifier: task.taskIdentifier)
        task.taskDescription = identity.taskDescription; delegate.register(identity)
        defer { delegate.cancel(task, reason: "final diagnostic cleanup"); _ = delegate.cleanup() }
        task.resume()
        let deadline = Date().addingTimeInterval(12)
        var nativeBytes: Int64 = 0, packageBytes: Int64 = 0
        var byteCounterError: [[String: Any]]?
        while Date() < deadline && !delegate.finished {
            nativeBytes = max(nativeBytes, task.countOfBytesReceived)
            do { packageBytes = max(packageBytes, try delegate.packageBytes()) }
            catch {
                byteCounterError = Self.errorChain(error)
                delegate.cancel(task, reason: "package byte counter unavailable")
                break
            }
            if max(nativeBytes, packageBytes) >= 2 * 1024 * 1024 { delegate.cancel(task, reason: "observed byte budget"); break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if !delegate.finished { delegate.cancel(task, reason: "short diagnostic deadline") }
        let completionDeadline = Date().addingTimeInterval(2)
        while !delegate.finished && Date() < completionDeadline { try await Task.sleep(nanoseconds: 25_000_000) }
        // A summary metric can follow completion; retain the delegate briefly.
        try await Task.sleep(nanoseconds: 200_000_000)
        nativeBytes = max(nativeBytes, task.countOfBytesReceived)
        var report = delegate.summary()
        report["observedNativeBytes"] = max(0, nativeBytes)
        report["observedPackageBytes"] = packageBytes
        report["nativeByteCounterKnown"] = nativeBytes > 0
        if let byteCounterError { report["packageByteCounterError"] = byteCounterError }
        report["selectedWidth"] = variant.videoAttributes?.presentationSize.width ?? 0
        report["selectedHeight"] = variant.videoAttributes?.presentationSize.height ?? 0
        report["selectedPeakBitRate"] = variant.peakBitRate ?? 0
        report["usesUnmodifiedNativeHTTPTransport"] = true
        report["cleanup"] = delegate.cleanup()
        return report
    }

    nonisolated fileprivate static func errorChain(_ error: Error) -> [[String: Any]] {
        var chain: [[String: Any]] = [], current: NSError? = error as NSError
        for _ in 0..<6 {
            guard let value = current else { break }
            chain.append(["domain": value.domain, "code": value.code, "message": HLSDownloadFailure(value).message,
                "infoKeys": value.userInfo.keys.sorted()])
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }
    private enum DiagnosticError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
}

private final class NativeTransportDelegate: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var identity: HLSDownloadIdentity?
    private var reference: HLSOwnedPackageReference?
    private var done = false, accepted = false
    private var failure: [[String: Any]] = [], metrics: [[String: Any]] = []
    private var cancelReason = ""
    func register(_ identity: HLSDownloadIdentity) { lock.lock(); self.identity = identity; lock.unlock() }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return done }
    func cancel(_ task: AVAssetDownloadTask, reason: String) {
        lock.lock(); if cancelReason.isEmpty { cancelReason = reason }; lock.unlock(); task.cancel()
    }
    private func checked(_ task: AVAssetDownloadTask) -> HLSDownloadIdentity? {
        lock.lock(); defer { lock.unlock() }
        let actual = HLSDownloadIdentity.parse(task.taskDescription, taskIdentifier: task.taskIdentifier)
        return actual == identity ? actual : nil
    }
    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, willDownloadTo location: URL) {
        guard let identity = checked(task), let owned = try? HLSOwnedPackageReference.nativeCallback(location: location, identity: identity) else { return }
        lock.lock(); reference = owned; lock.unlock()
    }
    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded ranges: [NSValue], timeRangeExpectedToLoad expected: CMTimeRange) {
        guard checked(task) != nil, ranges.contains(where: { $0.timeRangeValue.duration.seconds > 0 }) else { return }
        lock.lock(); accepted = true; lock.unlock(); cancel(task, reason: "first actual media range accepted")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let download = task as? AVAssetDownloadTask, checked(download) != nil else { return }
        lock.lock(); done = true
        if let error, (error as NSError).domain != NSURLErrorDomain || (error as NSError).code != NSURLErrorCancelled {
            failure = NativeHLSFixtureTransportDiagnosticsTests.errorChain(error)
        }
        lock.unlock()
    }
    @available(iOS 26.0, *)
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didReceive event: AVMetricEvent) {
        guard checked(assetDownloadTask) != nil else { return }
        guard let summary = event as? AVMetricDownloadSummaryEvent else { return }
        var value: [String: Any] = ["type": "downloadSummary", "bytes": summary.bytesDownloadedCount,
            "resourceRequests": summary.mediaResourceRequestCount, "recoverableErrors": summary.recoverableErrorCount,
            "duration": summary.downloadDuration.isFinite ? summary.downloadDuration : 0]
        if let error = summary.errorEvent?.error { value["errors"] = NativeHLSFixtureTransportDiagnosticsTests.errorChain(error) }
        lock.lock(); metrics.append(value); lock.unlock()
    }
    func summary() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["firstMediaRangeAccepted": accepted, "callbackCompleted": done, "failure": failure,
            "metrics": metrics, "cancelReason": cancelReason, "completeOfflinePackageProven": false]
    }
    func packageBytes() throws -> Int64 {
        lock.lock(); var owned = reference; let identity = identity; lock.unlock()
        guard let identity, owned != nil else { return 0 }
        let package: URL
        do {
            guard let resolved = try owned?.resolve(expectedIdentity: identity) else { return 0 }
            package = resolved
        } catch HLSOwnedPackageReferenceError.missingPackage { return 0 }
        var enumerationError: Error?
        guard let files = FileManager.default.enumerator(at: package,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw NSError(domain: "NativeHLSFixtureDiagnostics", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The exact native package could not be enumerated"])
        }
        var total: Int64 = 0
        for case let file as URL in files {
            do {
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink == false else {
                    files.skipDescendants()
                    throw NSError(domain: "NativeHLSFixtureDiagnostics", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "A package link prevents a complete byte count"])
                }
                if values.isRegularFile == true {
                    let fileValues = try file.resourceValues(forKeys: [.fileSizeKey])
                    guard let size = fileValues.fileSize, size >= 0 else {
                        throw NSError(domain: "NativeHLSFixtureDiagnostics", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "A package member byte count is unavailable"])
                    }
                    total += Int64(size)
                    if total >= 2 * 1024 * 1024 { return total }
                }
            } catch {
                let value = error as NSError
                // The native daemon may rename or purge an in-progress member.
                if value.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(value.code) { continue }
                throw error
            }
        }
        if let enumerationError { throw enumerationError }
        return total
    }
    func cleanup() -> [String: Any] {
        lock.lock(); var owned = reference; let identity = identity; lock.unlock()
        guard let identity, owned != nil else { return ["ownedPackageKnown": false] }
        do { try owned?.remove(expectedIdentity: identity); return ["ownedPackageRemoved": true] }
        catch HLSOwnedPackageReferenceError.missingPackage { return ["alreadyRemovedByNativeSystem": true] }
        catch { return ["error": HLSDownloadFailure(error).message] }
    }
}
