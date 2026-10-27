import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit
import XCTest
@testable import HLSResearchHost

/// Complete native lifecycle against tiny media that we generated ourselves.
/// The live provider episode is never downloaded by these tests. A cached
/// local playback check is not represented as physical airplane-mode proof.
@MainActor
final class NativeOfflineHLSLifecycleTests: XCTestCase, HLSDownloadSessionObserver {
    private let byteBudget: Int64 = 2 * 1024 * 1024
    private var owner: HLSDownloadSessionOwner?
    private var snapshots: [HLSDownloadSnapshot] = []
    private var startReturned = false
    private var cancelWhenPrepared = false
    private var preparedWasSynchronous = false

    func testClearFixtureCompletesAndPlaysFromSavedSystemPackage() async throws {
        try await exerciseCompletedPackage(fixture: "clear")
    }

    func testIdentityAES128FixtureCompletesAndPlaysFromSavedSystemPackage() async throws {
        try await exerciseCompletedPackage(fixture: "aes128")
    }

    func testPreparedObserverCanCancelBeforeTaskResumes() async throws {
        var report = Self.initialReport(fixture: "clear", purpose: "prepared observer cancellation")
        defer { record(report) }
        let source = Self.source(fixture: "clear")
        let session = HLSDownloadSessionOwner(observer: self,
            sessionIdentifier: "com.streamify.hls.lifecycle.cancel.\(UUID().uuidString)")
        owner = session; cancelWhenPrepared = true; startReturned = false; snapshots = []
        defer { cleanUpOwnedPackages(session); owner = nil }
        let identity = try await session.start(id: UUID(), attempt: UUID(), source: source,
            title: "Own HLS cancellation fixture", metadataTimeout: 15)
        startReturned = true
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(preparedWasSynchronous)
        XCTAssertEqual(snapshots.first(where: { $0.event == .prepared })?.identity, identity)
        XCTAssertTrue(snapshots.contains(where: { $0.event == .cancelled && $0.identity == identity }))
        XCTAssertFalse(session.activeIdentities.contains(identity))
        XCTAssertFalse(snapshots.contains(where: { [.progress, .packageFinished, .completed].contains($0.event) }))
        XCTAssertFalse(snapshots.contains(where: { $0.didFinishPackage }))
        report["preparedSynchronous"] = preparedWasSynchronous
        report["activeAfterPreparedCancel"] = session.activeIdentities.contains(identity)
        report["nativeProgressObserved"] = snapshots.contains(where: { $0.event == .progress })
        report["nativeCompletedObserved"] = snapshots.contains(where: { $0.event == .completed })
        report["events"] = snapshots.map { $0.event.rawValue }
    }

    func hlsDownloadSessionOwner(_ owner: HLSDownloadSessionOwner, didReceive snapshot: HLSDownloadSnapshot) {
        snapshots.append(snapshot)
        if snapshot.event == .prepared {
            preparedWasSynchronous = !startReturned
            if cancelWhenPrepared { owner.cancel(snapshot.identity) }
        }
    }

    private func exerciseCompletedPackage(fixture: String) async throws {
        var report = Self.initialReport(fixture: fixture, purpose: "complete own native HLS package")
        var phase = "native source preparation"
        defer { report["lastPhase"] = phase; record(report) }
        let source = Self.source(fixture: fixture)
        let session = HLSDownloadSessionOwner(observer: self,
            sessionIdentifier: "com.streamify.hls.lifecycle.\(fixture).\(UUID().uuidString)")
        owner = session; cancelWhenPrepared = false; startReturned = false; snapshots = []
        defer { cleanUpOwnedPackages(session); owner = nil }
        do {
            let deadline = Date().addingTimeInterval(90)
            let identity = try await session.start(id: UUID(), attempt: UUID(), source: source,
                title: "Own short \(fixture) HLS fixture", metadataTimeout: 15)
            startReturned = true
            report["preparedSynchronous"] = preparedWasSynchronous
            XCTAssertTrue(preparedWasSynchronous)
            XCTAssertEqual(snapshots.first(where: { $0.event == .prepared })?.identity, identity)
            phase = "bounded complete native download"
            var maximumPackageBytes: Int64 = 0, maximumNativeBytes: Int64 = 0
            while Date() < deadline {
                try Task.checkCancellation()
                maximumNativeBytes = max(maximumNativeBytes, session.observedBytes(identity: identity))
                if let package = snapshots.last(where: { $0.identity == identity && $0.packageURL != nil })?.packageURL {
                    maximumPackageBytes = max(maximumPackageBytes, try Self.ownedPackageBytes(package))
                }
                if max(maximumPackageBytes, maximumNativeBytes) > byteBudget {
                    session.cancel(identity)
                    throw LifecycleError.message("The tiny native fixture exceeded its observed 2MiB byte budget")
                }
                if snapshots.contains(where: { $0.identity == identity && [.completed, .failed, .cancelled].contains($0.event) }) { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            report["maximumOwnedPackageBytes"] = maximumPackageBytes
            report["maximumNativeTaskBytes"] = maximumNativeBytes
            report["nativeNetworkByteCounterKnown"] = maximumNativeBytes > 0
            report["events"] = snapshots.map { $0.event.rawValue }
            report["progressFractions"] = snapshots.filter { $0.event == .progress }.compactMap(\.fractionCompleted)
            guard let completion = snapshots.last(where: { $0.identity == identity && [.completed, .failed, .cancelled].contains($0.event) }) else {
                session.cancel(identity)
                throw LifecycleError.message("Native own-fixture download did not complete within 90seconds")
            }
            if let failure = completion.error { throw failure }
            guard completion.event == .completed, completion.didFinishPackage, let package = completion.packageURL,
                  !completion.selectedVariants.isEmpty,
                  completion.selectedVariants.allSatisfy({ $0.width == 1920 && $0.height == 1080 }),
                  completion.selectedAudioLanguage?.lowercased().hasPrefix("en") == true else {
                throw LifecycleError.message("Native completion did not confirm actual 1080p video, English audio and a finished package")
            }
            let fractions = snapshots.filter { $0.event == .progress }.compactMap(\.fractionCompleted)
            XCTAssertFalse(fractions.isEmpty, "A genuine loaded-time progress callback is required")
            XCTAssertTrue(fractions.allSatisfy { $0.isFinite && (0...1).contains($0) })
            XCTAssertTrue(fractions.contains(where: { $0 > 0 }))
            report["nativePackageCompleted"] = true
            report["selectedVariants"] = completion.selectedVariants.map { ["width": $0.width, "height": $0.height] }
            report["selectedAudioLanguage"] = completion.selectedAudioLanguage ?? "unknown"

            phase = "relative path persistence and fresh local asset"
            let relative = try HLSDownloadedPackages.relativePath(of: package)
            let metadataFile = FileManager.default.temporaryDirectory.appendingPathComponent("hls-lifecycle-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: metadataFile) }
            try JSONEncoder().encode(PersistedPackage(relativePath: relative, quality: 1080, audioLanguage: "en"))
                .write(to: metadataFile, options: .atomic)
            let restored = try JSONDecoder().decode(PersistedPackage.self, from: Data(contentsOf: metadataFile))
            guard let restoredURL = HLSDownloadedPackages.fileURL(for: restored.relativePath) else {
                throw LifecycleError.message("Saved relative native package location could not be restored")
            }
            XCTAssertEqual(restoredURL, package.standardizedFileURL.resolvingSymlinksInPath())
            let validation = try await OfflineHLSValidation.validate(restoredURL,
                quality: restored.quality, audioLanguage: restored.audioLanguage, timeout: 15)
            report["relativePathRoundTrip"] = true
            report["freshAssetCachePlayableOffline"] = validation.asset.assetCache?.isPlayableOffline ?? false
            report["cachedEnglishOptions"] = validation.asset.assetCache?.mediaSelectionOptions(in: validation.audioGroup)
                .filter { OfflineHLSValidation.isRequestedLanguage($0, language: "en") }
                .map { $0.extendedLanguageTag ?? $0.displayName } ?? []
            XCTAssertTrue(validation.asset.assetCache?.isPlayableOffline == true)
            XCTAssertTrue(validation.asset.assetCache?.mediaSelectionOptions(in: validation.audioGroup)
                .contains(where: { $0.isPlayable && OfflineHLSValidation.isRequestedLanguage($0, language: "en") }) == true)

            phase = "real local package video playback"
            let playback = try await Self.localPlayback(validation)
            report["localPlayback"] = playback
            report["completeOwnFixturePackageProven"] = true
            report["physicalAirplaneModeVerified"] = false
        } catch {
            report["error"] = HLSDownloadFailure(error).message
            throw error
        }
    }

    private struct PersistedPackage: Codable { let relativePath: String; let quality: Int; let audioLanguage: String }
    private enum LifecycleError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }

    private static func source(fixture: String) -> HLSDownloadSource {
        // These are literal repository paths generated and hashed with the
        // test fixture. No source URL, segment or key path is fabricated.
        let root = "https://raw.githubusercontent.com/Joshua131313/streamify/cf27bf56346bf94f12a55a0556f1f14be048b3fd/ios/NativeHLSDiagnostics/Fixtures/offline-hls-control"
        return HLSDownloadSource(masterURL: URL(string: "\(root)/\(fixture)/master.m3u8")!, quality: 1080,
            audioLanguage: "en", protection: .clearOrIdentityAES128, isVOD: true)
    }

    private static func initialReport(fixture: String, purpose: String) -> [String: Any] {
        ["fixture": fixture, "purpose": purpose, "providerEpisodeDownloaded": false,
         "observedAt": ISO8601DateFormatter().string(from: Date()), "manualKeyFetch": false,
         "networkActuallyDisabled": false, "networkIndependenceProven": false,
         "physicalAirplaneModeVerified": false, "completeOwnFixturePackageProven": false,
         "maximumObservedByteBudget": 2 * 1024 * 1024]
    }

    private static func ownedPackageBytes(_ package: URL) throws -> Int64 {
        _ = try HLSDownloadedPackages.relativePath(of: package)
        let root = package.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        guard let files = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var count: Int64 = 0
        for case let file as URL in files {
            let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(root.path + "/") else { throw LifecycleError.message("Native package member escaped its owned directory") }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                let size = Int64(max(0, values.fileSize ?? 0))
                guard size <= 2 * 1024 * 1024 - count else { return 2 * 1024 * 1024 + 1 }
                count += size
            }
        }
        return count
    }

    private static func localPlayback(_ validation: OfflineHLSValidation.Result) async throws -> [String: Any] {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .moviePlayback); try audio.setActive(true)
        defer { try? audio.setActive(false, options: .notifyOthersOnDeactivation) }
        let item = AVPlayerItem(asset: validation.asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.volume = 0.1; player.allowsExternalPlayback = false
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first,
              let view = window.rootViewController?.view else { throw LifecycleError.message("Research host has no visible playback view") }
        let layer = AVPlayerLayer(player: player); layer.frame = view.bounds; layer.videoGravity = .resizeAspect
        view.layer.addSublayer(layer)
        defer { player.pause(); player.replaceCurrentItem(with: nil); layer.removeFromSuperlayer() }
        let deadline = Date().addingTimeInterval(15)
        var started = false, width = 0, height = 0, seconds = 0.0
        while Date() < deadline {
            try Task.checkCancellation()
            if item.status == .failed { throw item.error ?? LifecycleError.message("Native local HLS item failed") }
            if !started && item.status == .readyToPlay {
                item.select(validation.audioOption, in: validation.audioGroup)
                player.playImmediately(atRate: 1); started = true
            }
            let time = item.currentTime()
            if time.seconds.isFinite { seconds = time.seconds }
            if output.hasNewPixelBuffer(forItemTime: time),
               let pixel = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                width = CVPixelBufferGetWidth(pixel); height = CVPixelBufferGetHeight(pixel)
            }
            if width == 1920 && height == 1080 && seconds >= 1 { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let selected = item.currentMediaSelection.selectedMediaOption(in: validation.audioGroup)
        guard width == 1920, height == 1080, seconds >= 1, selected?.isPlayable == true,
              selected.map({ OfflineHLSValidation.isRequestedLanguage($0, language: "en") }) == true else {
            throw LifecycleError.message("Fresh local HLS package did not produce actual advancing 1080p video with selected playable English audio")
        }
        let bytes = item.accessLog()?.events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) } ?? 0
        return ["pixelWidth": width, "pixelHeight": height, "playbackSeconds": seconds,
            "selectedEnglishAudio": selected?.extendedLanguageTag ?? "unknown",
            "nativePlayerObservedBytes": bytes, "networkActuallyDisabled": false,
            "actualDecodedAudioPCMProven": false, "playerLayerReadyForDisplay": layer.isReadyForDisplay]
    }

    private func cleanUpOwnedPackages(_ session: HLSDownloadSessionOwner) {
        for identity in Set(snapshots.map(\.identity)) { session.cancel(identity) }
        for snapshot in snapshots where snapshot.packageURL != nil {
            if let package = snapshot.packageURL { try? session.removeOwnedPackage(identity: snapshot.identity, packageURL: package) }
        }
    }
    private func record(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Own native HLS lifecycle"; attachment.lifetime = .keepAlways; add(attachment)
        print("NATIVE_HLS_LIFECYCLE \(text)")
    }
}
