import Foundation
import Combine

@MainActor
protocol SportsMultiWatchAudioTarget: AnyObject {
    /// Completion includes muting/unmuting media in descendant frames.
    func setAudible(_ audible: Bool) async throws
}

/// One serial worker owns audio changes. A newer selection cannot unmute until
/// the previous command (including its frame acknowledgements) has completed.
@MainActor
final class SportsMultiWatchAudio: ObservableObject {
    @Published private(set) var selectedID: String?
    @Published private(set) var audibleID: String?
    @Published private(set) var errorMessage: String?
    private struct Entry { weak var target: (any SportsMultiWatchAudioTarget)? }
    private var targets: [String: Entry] = [:]
    private var retiring: [ObjectIdentifier: any SportsMultiWatchAudioTarget] = [:]
    private var active = false
    private var revision = 0
    private var worker: Task<Void, Never>?

    func register(_ target: any SportsMultiWatchAudioTarget, id: String) {
        if let old = targets[id]?.target, old !== target { retiring[ObjectIdentifier(old)] = old }
        targets[id] = Entry(target: target)
        reconcile()
    }

    func unregister(_ target: any SportsMultiWatchAudioTarget, id: String) {
        guard targets[id]?.target === target else { return }
        retiring[ObjectIdentifier(target)] = target
        targets.removeValue(forKey: id)
        reconcile()
    }

    func select(_ id: String?) { selectedID = id; reconcile() }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        reconcile()
    }
    func retry() { reconcile() }

    private func reconcile() {
        revision += 1
        guard worker == nil else { return }
        worker = Task { await run() }
    }

    private func run() async {
        while true {
            let request = revision
            let players = targets.compactMapValues(\.target)
            var barrier = retiring
            for target in players.values { barrier[ObjectIdentifier(target)] = target }
            audibleID = nil
            errorMessage = nil
            var muteFailed = false
            // Mute every existing target, even after one failure. No target is
            // enabled unless every mute acknowledged successfully.
            for (identity, target) in barrier {
                do {
                    try await target.setAudible(false)
                    retiring.removeValue(forKey: identity)
                }
                catch { muteFailed = true }
            }
            guard request == revision else { continue }
            if muteFailed {
                errorMessage = "Audio couldn't switch. Try again."
            } else if active, let id = selectedID, let target = players[id] {
                do {
                    try await target.setAudible(true)
                    if request == revision { audibleID = id }
                } catch {
                    // A partial unmute must be reversed before a retry/another
                    // selection. The worker remains serial during this cleanup.
                    try? await target.setAudible(false)
                    if request == revision { errorMessage = "Audio couldn't switch. Try again." }
                }
            }
            guard request == revision else { continue }
            worker = nil
            return
        }
    }
}
