import AVFoundation
import CoreImage
import CoreVideo
import Foundation

/// A private, silent decoder for an already validated system-owned HLS cache.
/// It never seeks the visible player, opens a remote URL or handles key bytes.
final class OfflineHLSSeekFrameDecoder: @unchecked Sendable {
    enum Failure: Error { case unavailableLocalPackage, notReady, seekFailed, frameUnavailable }
    private final class SeekResult: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Bool?
        func finish(_ value: Bool) { lock.lock(); result = value; lock.unlock() }
        var value: Bool? { lock.lock(); defer { lock.unlock() }; return result }
    }
    private let lock = NSLock()
    private var generation = UUID()
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(asset: AVURLAsset) throws {
        guard asset.url.isFileURL, asset.url.pathExtension.lowercased() == "movpkg",
              asset.assetCache?.isPlayableOffline == true else { throw Failure.unavailableLocalPackage }
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        let player = AVPlayer(playerItem: item)
        self.item = item; self.output = output; self.player = player
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        item.preferredForwardBufferDuration = 0.25
        output.suppressesPlayerRendering = true
        item.add(output)
        player.isMuted = true; player.volume = 0
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    /// Cancellation invalidates the exact request before interrupting its seek.
    /// A superseded request's cleanup must never pause a newer preview request.
    func cancel() {
        lock.lock(); generation = UUID(); lock.unlock()
        item.cancelPendingSeeks(); player.pause()
    }
    func close() { cancel(); player.replaceCurrentItem(with: nil) }
    deinit { close() }

    private func token() -> UUID { lock.lock(); defer { lock.unlock() }; return generation }
    private func check(_ request: UUID) throws {
        try Task.checkCancellation()
        guard token() == request else { throw CancellationError() }
    }

    @MainActor
    func image(at time: CMTime, timeout: TimeInterval = 4) async throws -> CGImage {
        guard time.seconds.isFinite, time.seconds >= 0 else { throw Failure.frameUnavailable }
        cancel()
        let request = token()
        let deadline = Date().addingTimeInterval(min(8, max(0.1, timeout.isFinite ? timeout : 4)))
        defer {
            if token() == request { item.cancelPendingSeeks(); player.pause() }
        }
        while item.status == .unknown && Date() < deadline {
            try check(request); try await Task.sleep(nanoseconds: 15_000_000)
        }
        try check(request)
        guard item.status == .readyToPlay else { throw item.error ?? Failure.notReady }
        let seek = SeekResult()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { seek.finish($0) }
        while seek.value == nil && Date() < deadline {
            try check(request); try await Task.sleep(nanoseconds: 15_000_000)
        }
        try check(request)
        guard seek.value == true else { throw Failure.seekFailed }
        // AVPlayer's native HLS decoder can produce frames without an image
        // generator/I-frame rendition. Briefly advance this muted item only.
        // A slow private clock gives a cold decoder time to return the target
        // frame without drifting several seconds past the hovered timestamp.
        player.playImmediately(atRate: 0.1)
        while Date() < deadline {
            try check(request)
            if item.status == .failed { throw item.error ?? Failure.frameUnavailable }
            let current = item.currentTime()
            if output.hasNewPixelBuffer(forItemTime: current) {
                var display = CMTime.invalid
                if let pixel = output.copyPixelBuffer(forItemTime: current, itemTimeForDisplay: &display),
                   display.seconds.isFinite, display.seconds >= time.seconds - 0.25,
                   display.seconds <= time.seconds + 1 {
                    let image = CIImage(cvPixelBuffer: pixel)
                    let width = image.extent.width, height = image.extent.height
                    guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw Failure.frameUnavailable }
                    let scale = min(1, min(320 / width, 180 / height))
                    let bounds = CGRect(x: 0, y: 0,
                        width: max(1, min(320, floor(width * scale))),
                        height: max(1, min(180, floor(height * scale))))
                    guard let result = context.createCGImage(image.transformed(by:
                        CGAffineTransform(scaleX: scale, y: scale)), from: bounds) else { throw Failure.frameUnavailable }
                    try check(request)
                    return result
                }
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        throw Failure.frameUnavailable
    }

    var observedTransferredBytes: Int64 {
        item.accessLog()?.events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) } ?? 0
    }
}
