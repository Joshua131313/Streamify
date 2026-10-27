import AVFoundation
import Foundation

@MainActor protocol OfflineSeekDriving: AnyObject {
    var currentSeconds: Double { get }
    func seek(to seconds: Double, tolerance: Double, completion: @escaping @Sendable (Bool) -> Void)
    func cancelPendingSeeks()
}

@MainActor final class AVPlayerOfflineSeekDriver: OfflineSeekDriving {
    weak var player: AVPlayer?
    init(player: AVPlayer) { self.player = player }
    var currentSeconds: Double { player?.currentTime().seconds ?? .nan }
    func seek(to seconds: Double, tolerance: Double, completion: @escaping @Sendable (Bool) -> Void) {
        guard let player else { completion(false); return }
        let accuracy = CMTime(seconds: tolerance, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: accuracy, toleranceAfter: accuracy, completionHandler: completion)
    }
    func cancelPendingSeeks() { player?.currentItem?.cancelPendingSeeks() }
}

/// One native seek is in flight at a time (Apple QA1820). Repeated skip taps
/// accumulate against the latest requested position, without repeatedly
/// cancelling AVFoundation before it has displayed a frame. The small normal
/// tolerance avoids requesting edit-grade sample accuracy for a transport UI.
@MainActor final class OfflineSeekController {
    enum Result { case completed(Double), failed(Double?) }
    private struct Flight: Sendable {
        let id = UUID()
        let target: Double
        let attempt: Int
        var tolerance: Double { attempt == 0 ? 0.25 : 1 }
    }
    private let driver: any OfflineSeekDriving
    private let timeout: Duration
    private let onResult: (Result) -> Void
    private var flight: Flight?
    private var deadline: Task<Void, Never>?
    private(set) var pendingTarget: Double?
    var isSeeking: Bool { flight != nil }

    init(driver: any OfflineSeekDriving, timeout: Duration = .seconds(4), onResult: @escaping (Result) -> Void) {
        self.driver = driver; self.timeout = timeout; self.onResult = onResult
    }

    func seek(to target: Double) {
        guard target.isFinite, target >= 0 else { return }
        pendingTarget = target
        if flight == nil { start(target: target, attempt: 0) }
    }

    func cancel() {
        // Invalidate before cancellation: AVFoundation may synchronously deliver
        // the cancelled completion, which must not affect a replacement player.
        flight = nil; pendingTarget = nil
        deadline?.cancel(); deadline = nil
        driver.cancelPendingSeeks()
    }

    private func start(target: Double, attempt: Int) {
        let request = Flight(target: target, attempt: attempt)
        flight = request
        deadline?.cancel()
        deadline = Task { @MainActor [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(request, completed: false, timedOut: true)
        }
        driver.seek(to: target, tolerance: request.tolerance) { [weak self] completed in
            Task { @MainActor [weak self] in self?.finish(request, completed: completed) }
        }
    }

    private func finish(_ request: Flight, completed: Bool, timedOut: Bool = false) {
        guard flight?.id == request.id else { return }
        flight = nil; deadline?.cancel(); deadline = nil
        if timedOut { driver.cancelPendingSeeks() }
        guard let latest = pendingTarget else { return }
        if latest != request.target { start(target: latest, attempt: 0); return }
        let actual = driver.currentSeconds
        // Publish only the native playhead, never the requested timestamp. A
        // completion without movement is not a successful seek.
        if completed, actual.isFinite, abs(actual - latest) <= request.tolerance + 0.15 {
            pendingTarget = nil; onResult(.completed(actual)); return
        }
        if request.attempt == 0 { start(target: latest, attempt: 1); return }
        pendingTarget = nil
        onResult(.failed(actual.isFinite && actual >= 0 ? actual : nil))
    }

    deinit { deadline?.cancel() }
}
