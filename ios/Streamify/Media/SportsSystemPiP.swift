import Foundation
import Combine

enum SportsPiPCapability: String { case available = "Available", unavailable = "Unavailable", checking = "Checking" }

/// Only an AVKit delegate or an observed HTML5 presentation mode can mark PiP
/// active. Requesting it never hides the full player by itself.
@MainActor
final class SportsSystemPiP: ObservableObject {
    @Published private(set) var capability: SportsPiPCapability = .checking
    @Published private(set) var isActive = false
    @Published private(set) var isRequesting = false
    /// WebKit can keep the video in its own fullscreen window while PiP stops.
    /// The app's black player window must not cover that retained surface.
    @Published private(set) var providerOwnsFullscreen = false
    @Published var message: String?
    var onStateChange: ((Bool, Bool) -> Void)?
    private var owner: UUID?
    private var requestAction: (() -> Void)?
    private var stopAction: (() -> Void)?
    private var restoreRequested = false
    private var timeout: Task<Void, Never>?
    func owns(owner: UUID) -> Bool { self.owner == owner }

    func attach(owner: UUID, capability: SportsPiPCapability, request: @escaping () -> Void, stop: @escaping () -> Void) {
        if self.owner != owner { reset() }
        self.owner = owner; self.capability = capability
        requestAction = request; stopAction = stop
    }
    func reportCapability(_ value: SportsPiPCapability, owner: UUID) {
        // WebKit reports a heartbeat every second. Publishing identical values
        // rebuilds the observed player chrome, including an open source menu.
        guard self.owner == owner, capability != value else { return }
        capability = value
    }
    func reportProviderFullscreen(_ value: Bool, owner: UUID) {
        guard self.owner == owner, providerOwnsFullscreen != value else { return }
        providerOwnsFullscreen = value
    }
    func request() {
        guard !isActive, !isRequesting else { return }
        guard capability == .available, let owner, let requestAction else {
            message = capability == .checking ? "Wait for the video to start, then try Picture in Picture again."
                : "This source does not currently support iOS Picture in Picture. Try another source or use its own video controls."
            return
        }
        message = nil; isRequesting = true; restoreRequested = false
        requestAction()
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, self.owner == owner, self.isRequesting, !self.isActive else { return }
            self.failed("iOS Picture in Picture could not start for this source. Keep the video playing and try again, or choose another source.", owner: owner)
        }
    }
    func didStart(owner: UUID) {
        guard self.owner == owner else { return }
        timeout?.cancel(); timeout = nil; isRequesting = false; message = nil
        guard !isActive else { return }; isActive = true; onStateChange?(true, false)
    }
    func didStop(owner: UUID, restoring: Bool) {
        guard self.owner == owner else { return }
        timeout?.cancel(); timeout = nil
        let wasActive = isActive, restore = restoring || restoreRequested
        isActive = false; isRequesting = false; restoreRequested = false
        if wasActive { onStateChange?(false, restore) }
    }
    func failed(_ text: String, owner: UUID) {
        guard self.owner == owner else { return }
        timeout?.cancel(); timeout = nil; isRequesting = false; message = text
    }
    func restore() {
        guard isActive else { return }
        restoreRequested = true; stopAction?()
    }
    func detach(owner: UUID) {
        guard self.owner == owner else { return }
        let wasActive = isActive
        reset()
        if wasActive { onStateChange?(false, false) }
    }
    func reset() {
        timeout?.cancel(); timeout = nil
        let stop = stopAction
        owner = nil; requestAction = nil; stopAction = nil
        capability = .checking; isActive = false; isRequesting = false; restoreRequested = false; message = nil
        providerOwnsFullscreen = false
        stop?()
    }
}
