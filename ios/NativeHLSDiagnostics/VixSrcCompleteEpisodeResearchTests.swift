import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit
import XCTest
@testable import HLSResearchHost

/// MANUAL ONLY. Root dispatches this separately after controlled clear and
/// identity-AES128 package lifecycle tests pass. Never part of ordinary CI.
/// Apple handles normal HLS transport keys; this test never reads key bytes.
@MainActor
final class VixSrcCompleteEpisodeResearchTests: XCTestCase, HLSDownloadSessionObserver {
    private static let byteBudget: Int64 = 2 * 1024 * 1024 * 1024
    private var snapshots: [HLSDownloadSnapshot] = []
    private var owner: HLSDownloadSessionOwner?
    private var startReturned = false
    private var preparedSynchronously = false

    func testFROMSeasonOneEpisodeOneComplete1080EnglishNativePackage() async {
        executionTimeAllowance = 8 * 60
        let began = Date(), deadline = Date().addingTimeInterval(6 * 60)
        var phase = "production public source resolver"
        var report: [String: Any] = ["tmdbID": 124364, "season": 1, "episode": 1,
            "requestedQuality": 1080, "requestedAudioLanguage": "en",
            "observedAt": ISO8601DateFormatter().string(from: began),
            "maximumSeconds": 6 * 60, "maximumObservedBytes": Self.byteBudget,
            "manualKeyFetch": false, "nativeCustomResourceLoader": false,
            "networkActuallyDisabled": false, "networkIndependenceProven": false,
            "physicalPhoneTested": false, "physicalAirplaneModeVerified": false,
            "completeProviderPackageProven": false, "fullIntegrityScanPerformed": false,
            "decodedAudioPCMProven": false, "mediaArtifactUploadAllowed": false]
        let session = HLSDownloadSessionOwner(observer: self,
            sessionIdentifier: "com.streamify.hls.full-episode-research.\(UUID().uuidString)")
        owner = session
        defer {
            let cleanup = cleanupOwnedPackages(session)
            XCTAssertTrue((cleanup["errors"] as? [String] ?? []).isEmpty, "Owned research packages must be removed successfully")
            report["cleanup"] = cleanup
            report["elapsedSeconds"] = Date().timeIntervalSince(began)
            report["lastPhase"] = phase
            record(report)
            owner = nil
        }
        do {
            let media = MediaItem(id: 124364, kind: .tv, title: "FROM", releaseDate: "2022-02-20")
            let resolved = try await VixSrcDownloadResolver().resolve(media: media,
                season: 1, episode: 1, quality: 1080)
            guard Date() < deadline else { throw ResearchError.deadline }
            guard resolved.transport == .hlsVOD, resolved.quality == 1080,
                  let source = resolved.hlsSource, source.quality == 1080, source.isVOD,
                  source.audioLanguage.lowercased().hasPrefix("en") else {
                throw ResearchError.message("Production resolver did not return exact1080p English HLS VOD")
            }
            report["resolvedTransport"] = resolved.transport.rawValue
            report["resolvedActualWidth"] = resolved.actualWidth ?? 0
            report["resolvedActualHeight"] = resolved.actualHeight ?? 0
            report["resolvedCodecs"] = resolved.actualCodecs ?? []
            report["sourceAddressLogged"] = false
            phase = "complete bounded native provider package"
            let identity = try await session.start(id: UUID(), attempt: UUID(), source: source,
                title: "Manual FROM S1E1 source research", metadataTimeout: min(15, remaining(deadline)))
            startReturned = true
            report["preparedSynchronous"] = preparedSynchronously
            guard preparedSynchronously else { throw ResearchError.message("Prepared native identity was not persisted before task resume") }
            var maximumNativeBytes: Int64 = 0, maximumPackageBytes: Int64 = 0
            while Date() < deadline {
                try Task.checkCancellation()
                maximumNativeBytes = max(maximumNativeBytes, session.observedBytes(identity: identity))
                if let reference = latestPackageReference(identity: identity) {
                    maximumPackageBytes = max(maximumPackageBytes, try Self.packageBytes(reference, expectedIdentity: identity))
                }
                report["maximumNativeTaskBytes"] = maximumNativeBytes
                report["maximumOwnedPackageBytes"] = maximumPackageBytes
                report["nativeNetworkByteCounterKnown"] = maximumNativeBytes > 0
                guard max(maximumNativeBytes, maximumPackageBytes) <= Self.byteBudget else {
                    session.cancel(identity); throw ResearchError.budget
                }
                if terminal(identity: identity) != nil { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard Date() < deadline else { session.cancel(identity); throw ResearchError.deadline }
            guard let finished = terminal(identity: identity) else { throw ResearchError.message("Native task did not report completion") }
            if let error = finished.error { throw error }
            guard finished.event == .completed, finished.didFinishPackage, finished.packageURL != nil,
                  var reference = finished.packageReference, reference.identity == identity,
                  !finished.selectedVariants.isEmpty,
                  finished.selectedVariants.allSatisfy({ $0.width == 1920 && $0.height == 1080 }),
                  finished.selectedAudioLanguage?.lowercased().hasPrefix("en") == true else {
                throw ResearchError.message("Native completion did not confirm a finished1080p English package")
            }
            maximumPackageBytes = max(maximumPackageBytes, try Self.packageBytes(reference, expectedIdentity: identity))
            guard maximumPackageBytes <= Self.byteBudget else { throw ResearchError.budget }
            report["maximumOwnedPackageBytes"] = maximumPackageBytes
            report["nativeTransportCompleted"] = true
            report["nativeSelectedVariants"] = finished.selectedVariants.map { ["width": $0.width, "height": $0.height] }
            report["nativeSelectedAudioLanguage"] = finished.selectedAudioLanguage ?? "unknown"
            let progress = snapshots.filter { $0.event == .progress }.compactMap(\.fractionCompleted)
            report["genuineTimeProgressCallbackCount"] = progress.count
            report["maximumGenuineTimeProgress"] = progress.max() ?? 0

            phase = "runtime-owned package validation and durable bookmark persistence"
            guard Date() < deadline else { throw ResearchError.deadline }
            let initial = try await OfflineHLSValidation.validate(reference: reference, expectedIdentity: identity,
                quality: 1080, audioLanguage: "en", timeout: min(15, remaining(deadline)))
            guard initial.asset.url.isFileURL, initial.asset.assetCache?.isPlayableOffline == true else {
                throw ResearchError.message("Runtime-owned provider package did not validate as locally playable offline")
            }
            report["runtimeOwnedPackageValidated"] = true
            try reference.makeDurable(expectedIdentity: identity)
            guard reference.isDurable else { throw ResearchError.message("Native completed package did not produce a durable bookmark") }
            let metadata = FileManager.default.temporaryDirectory.appendingPathComponent("from-package-research-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: metadata) }
            try JSONEncoder().encode(SavedPackage(reference: reference, quality: 1080, language: "en"))
                .write(to: metadata, options: .atomic)
            let saved = try JSONDecoder().decode(SavedPackage.self, from: Data(contentsOf: metadata))
            guard saved.reference.identity == identity, saved.reference.isDurable else {
                throw ResearchError.message("Saved native package lost its exact task identity or durable bookmark")
            }
            guard Date() < deadline else { throw ResearchError.deadline }
            // Decoding clears provisional authority. Only the durable bookmark
            // may resolve this new local asset; no runtime callback is replayed.
            let validation = try await OfflineHLSValidation.validate(reference: saved.reference,
                expectedIdentity: identity, quality: saved.quality,
                audioLanguage: saved.language, timeout: min(15, remaining(deadline)))
            guard initial.asset !== validation.asset else { throw ResearchError.message("Persisted package validation reused the first native asset") }
            report["durableBookmarkRoundTrip"] = true
            report["decodedReferenceReassociatedWithCallback"] = false
            report["freshLocalAssetUsed"] = validation.asset.url.isFileURL
            report["originalRemoteAssetReusedForPlayback"] = false
            report["assetCachePlayableOffline"] = validation.asset.assetCache?.isPlayableOffline ?? false
            let cachedEnglish = validation.asset.assetCache?.mediaSelectionOptions(in: validation.audioGroup)
                .filter { $0.isPlayable && OfflineHLSValidation.isRequestedLanguage($0, language: "en") } ?? []
            report["cachedEnglishOptionCount"] = cachedEnglish.count
            guard validation.asset.assetCache?.isPlayableOffline == true, !cachedEnglish.isEmpty else {
                throw ResearchError.message("Completed provider package did not retain playable offline video and English audio selection")
            }
            phase = "fresh local real frames at start middle near end"
            report["durationSeconds"] = validation.duration
            report["sampledLocalPlayback"] = try await Self.sampleLocalPackage(validation, deadline: deadline)
            report["completeProviderPackageProven"] = true
            report["finding"] = "Native completed1080p English package, offline-cache capability, cached English selection and three real local frame/playback samples passed. Network isolation, physical iPhone behaviour and full-file integrity remain unverified."
        } catch {
            report["error"] = HLSDownloadFailure(error).message
            XCTAssertTrue(false, "Full-provider HLS research failed at \(phase): \(HLSDownloadFailure(error).message)")
        }
    }

    func hlsDownloadSessionOwner(_ owner: HLSDownloadSessionOwner, didReceive snapshot: HLSDownloadSnapshot) {
        snapshots.append(snapshot)
        if snapshot.event == .prepared { preparedSynchronously = !startReturned }
    }
    private func latestPackageReference(identity: HLSDownloadIdentity) -> HLSOwnedPackageReference? {
        snapshots.last(where: { $0.identity == identity && $0.packageReference != nil })?.packageReference
    }
    private func terminal(identity: HLSDownloadIdentity) -> HLSDownloadSnapshot? {
        snapshots.last(where: { $0.identity == identity && [.completed, .failed, .cancelled].contains($0.event) })
    }
    private func remaining(_ deadline: Date) -> TimeInterval { max(0.1, deadline.timeIntervalSinceNow) }
    private struct SavedPackage: Codable { let reference: HLSOwnedPackageReference; let quality: Int; let language: String }
    private enum ResearchError: LocalizedError {
        case deadline, budget, message(String)
        var errorDescription: String? {
            switch self {
            case .deadline: return "Manual provider research reached its six-minute deadline."
            case .budget: return "Manual provider research reached its observed two-GiB package/native byte budget."
            case .message(let value): return value
            }
        }
    }

    private static func packageBytes(_ reference: HLSOwnedPackageReference, expectedIdentity: HLSDownloadIdentity) throws -> Int64 {
        var checked = reference
        let package: URL
        do { package = try checked.resolve(expectedIdentity: expectedIdentity) }
        catch HLSOwnedPackageReferenceError.missingPackage { return 0 }
        let rootPath = package.standardizedFileURL.resolvingSymlinksInPath().path
        guard let files = FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
            // Never traverse or inspect a link outside this exact package.
            guard resolved.path.hasPrefix(rootPath + "/") else { throw ResearchError.message("Native package member escaped its exact owned directory") }
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true {
                    let size = Int64(max(0, values.fileSize ?? 0))
                    guard size <= byteBudget - total else { return byteBudget + 1 }
                    total += size
                }
            } catch {
                let value = error as NSError
                // The daemon may atomically rename an in-progress member.
                if value.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(value.code) { continue }
                throw error
            }
        }
        return total
    }

    private static func sampleLocalPackage(_ validation: OfflineHLSValidation.Result, deadline: Date) async throws -> [[String: Any]] {
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
              let view = window.rootViewController?.view else { throw ResearchError.message("Manual research host has no visible playback surface") }
        let layer = AVPlayerLayer(player: player); layer.frame = view.bounds; layer.videoGravity = .resizeAspect
        view.layer.addSublayer(layer)
        defer { item.cancelPendingSeeks(); player.pause(); player.replaceCurrentItem(with: nil); layer.removeFromSuperlayer() }
        let readyDeadline = min(deadline, Date().addingTimeInterval(12))
        while item.status == .unknown && Date() < readyDeadline { try await Task.sleep(nanoseconds: 25_000_000) }
        guard item.status == .readyToPlay else { throw item.error ?? ResearchError.message("Fresh local player item did not become ready") }
        item.select(validation.audioOption, in: validation.audioGroup)
        let targets: [(String, Double)] = [("start", 0), ("middle", validation.duration / 2), ("nearEnd", max(0, validation.duration - 8))]
        var results: [[String: Any]] = []
        for (name, target) in targets {
            guard Date() < deadline else { throw ResearchError.deadline }
            player.pause()
            let signal = SeekSignal()
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak signal] success in
                DispatchQueue.main.async { signal?.completed = success }
            }
            let seekDeadline = min(deadline, Date().addingTimeInterval(12))
            while signal.completed == nil && Date() < seekDeadline { try await Task.sleep(nanoseconds: 25_000_000) }
            guard signal.completed == true else { item.cancelPendingSeeks(); throw ResearchError.message("Fresh local package could not seek to its \(name) sample") }
            player.playImmediately(atRate: 1)
            var width = 0, height = 0, seconds = target, frameSeconds: Double?
            let sampleDeadline = min(deadline, Date().addingTimeInterval(15))
            while Date() < sampleDeadline {
                try Task.checkCancellation()
                if item.status == .failed { throw item.error ?? ResearchError.message("Local package playback failed at \(name)") }
                let time = item.currentTime()
                if time.seconds.isFinite { seconds = time.seconds }
                if output.hasNewPixelBuffer(forItemTime: time) {
                    var displayTime = CMTime.invalid
                    if let pixel = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayTime) {
                        width = CVPixelBufferGetWidth(pixel); height = CVPixelBufferGetHeight(pixel)
                        frameSeconds = displayTime.seconds.isFinite ? displayTime.seconds : nil
                    }
                }
                if width == 1920 && height == 1080, seconds >= target + 0.75,
                   let frameSeconds, frameSeconds >= target - 0.25 { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            guard width == 1920, height == 1080, seconds >= target + 0.75,
                  let frameSeconds, frameSeconds >= target - 0.25 else {
                throw ResearchError.message("Fresh local \(name) sample did not produce a real1080p frame at the seek position with advancing playback")
            }
            let selected = item.currentMediaSelection.selectedMediaOption(in: validation.audioGroup)
            guard let selected, selected.isPlayable, OfflineHLSValidation.isRequestedLanguage(selected, language: "en") else {
                throw ResearchError.message("Fresh local \(name) sample did not retain selected playable English audio")
            }
            let bytes = item.accessLog()?.events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) } ?? 0
            results.append(["sample": name, "targetSeconds": target, "playbackSeconds": seconds,
                "actualFrameSeconds": frameSeconds, "pixelWidth": width, "pixelHeight": height,
                "selectedEnglishAudio": selected.extendedLanguageTag ?? "unknown",
                "playerObservedBytes": bytes, "networkActuallyDisabled": false])
        }
        return results
    }
    @MainActor
    private final class SeekSignal { var completed: Bool? }

    private func cleanupOwnedPackages(_ session: HLSDownloadSessionOwner) -> [String: Any] {
        let identities = Set(snapshots.map(\.identity))
        for identity in identities { session.cancel(identity) }
        var attempted = Set<String>(), failures: [String] = []
        for snapshot in snapshots {
            guard let package = snapshot.packageURL else { continue }
            let exactOwnedLocation = "\(snapshot.identity.taskDescription)|\(snapshot.identity.taskIdentifier)|\(package.absoluteString)"
            guard attempted.insert(exactOwnedLocation).inserted else { continue }
            do { try session.removeOwnedPackage(identity: snapshot.identity, packageURL: package) }
            catch { failures.append(HLSDownloadFailure(error).message) }
        }
        return ["ownedPackageRemovalAttempts": attempted.count, "errors": failures,
            "movedPackage": false, "rewroteNativeDestination": false, "readOrExportedKeyBytes": false]
    }
    private func record(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Complete provider HLS package research"; attachment.lifetime = .keepAlways; add(attachment)
        print("VIXSRC_COMPLETE_HLS_RESEARCH \(text)")
    }
}
