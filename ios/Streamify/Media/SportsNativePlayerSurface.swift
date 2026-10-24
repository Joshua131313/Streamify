import SwiftUI
import AVKit
import AVFoundation

/// One public AVPlayerLayer feeds inline video and Apple's system PiP window.
@MainActor
struct SportsNativePlayerSurface: View {
    let player: AVPlayer?
    let pictureInPicture: SportsSystemPiP

    var body: some View {
        SportsNativePlayerLayer(player: player, pictureInPicture: pictureInPicture)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class SportsNativeLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let transport = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        transport.tintColor = .white
        transport.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        transport.layer.cornerRadius = 22
        transport.translatesAutoresizingMaskIntoConstraints = false
        transport.accessibilityIdentifier = "sports-native-play-pause"
        transport.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
        addSubview(transport)
        NSLayoutConstraint.activate([
            transport.widthAnchor.constraint(equalToConstant: 44),
            transport.heightAnchor.constraint(equalToConstant: 44),
            transport.centerXAnchor.constraint(equalTo: centerXAnchor),
            transport.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        updateTransport()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateTransport() {
        let playing = playerLayer.player?.timeControlStatus == .playing
        transport.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        transport.accessibilityLabel = playing ? "Pause" : "Play"
        transport.isEnabled = playerLayer.player?.currentItem?.status == .readyToPlay && playerLayer.player?.timeControlStatus != .waitingToPlayAtSpecifiedRate
    }
    private func togglePlayback() {
        guard let player = playerLayer.player else { return }
        AppHaptics.tap()
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        updateTransport()
    }
}

@MainActor
private struct SportsNativePlayerLayer: UIViewRepresentable {
    let player: AVPlayer?
    let pictureInPicture: SportsSystemPiP

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SportsNativeLayerView {
        let view = SportsNativeLayerView(frame: .zero)
        context.coordinator.bind(view: view, player: player, pictureInPicture: pictureInPicture)
        return view
    }
    func updateUIView(_ view: SportsNativeLayerView, context: Context) {
        context.coordinator.bind(view: view, player: player, pictureInPicture: pictureInPicture)
    }
    static func dismantleUIView(_ view: SportsNativeLayerView, coordinator: Coordinator) {
        coordinator.detach()
        if view.playerLayer.player != nil { view.playerLayer.player = nil }
    }

    @MainActor
    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        private weak var view: SportsNativeLayerView?
        private weak var player: AVPlayer?
        private weak var pictureInPicture: SportsSystemPiP?
        private var controller: AVPictureInPictureController?
        private var possibleObservation: NSKeyValueObservation?
        private var playbackObservation: NSKeyValueObservation?
        private var itemObservation: NSKeyValueObservation?
        private var owner = UUID()
        private var attached = false
        private var restoring = false

        func bind(view: SportsNativeLayerView, player: AVPlayer?, pictureInPicture: SportsSystemPiP) {
            guard !attached || self.view !== view || self.player !== player || self.pictureInPicture !== pictureInPicture || !pictureInPicture.owns(owner: owner) else { return }
            detach()
            owner = UUID(); attached = true; restoring = false
            self.view = view; self.player = player; self.pictureInPicture = pictureInPicture
            if view.playerLayer.player !== player { view.playerLayer.player = player }
            view.updateTransport()
            let currentOwner = owner
            pictureInPicture.attach(owner: currentOwner, capability: player == nil ? .checking : .unavailable,
                request: { [weak self] in guard let self, self.owner == currentOwner else { return }; self.start() },
                stop: { [weak self] in guard let self, self.owner == currentOwner else { return }; self.stop() })
            guard let player else { return }
            itemObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.attached, self.owner == currentOwner else { return }
                    self.view?.updateTransport(); self.publishCapability()
                }
            }
            playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.attached, self.owner == currentOwner, self.player === observed else { return }
                    self.view?.updateTransport(); self.publishCapability()
                }
            }
            guard AVPictureInPictureController.isPictureInPictureSupported(),
                  let created = AVPictureInPictureController(playerLayer: view.playerLayer) else {
                pictureInPicture.reportCapability(.unavailable, owner: currentOwner); return
            }
            controller = created; created.delegate = self
            created.canStartPictureInPictureAutomaticallyFromInline = true
            possibleObservation = created.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.attached, self.owner == currentOwner, self.controller === observed else { return }
                    self.publishCapability()
                }
            }
        }

        private func publishCapability() {
            guard attached else { return }
            let capability: SportsPiPCapability
            if controller?.isPictureInPicturePossible == true { capability = .available }
            else if player == nil || player?.currentItem?.status == .unknown { capability = .checking }
            else { capability = .unavailable }
            pictureInPicture?.reportCapability(capability, owner: owner)
        }
        private func start() {
            guard attached, let controller, controller.isPictureInPicturePossible else {
                pictureInPicture?.failed("Picture in Picture is not currently available for this source.", owner: owner); return
            }
            restoring = false
            controller.startPictureInPicture()
        }
        private func stop() { controller?.stopPictureInPicture() }

        func detach() {
            guard attached else { return }
            attached = false
            possibleObservation?.invalidate(); possibleObservation = nil
            playbackObservation?.invalidate(); playbackObservation = nil
            itemObservation?.invalidate(); itemObservation = nil
            controller?.delegate = nil
            controller?.stopPictureInPicture(); controller = nil
            pictureInPicture?.detach(owner: owner)
            view = nil; player = nil; pictureInPicture = nil; restoring = false
        }

        nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor [weak self] in
                guard let self, self.attached, self.controller === pictureInPictureController else { return }
                self.pictureInPicture?.didStart(owner: self.owner)
            }
        }
        nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor [weak self] in
                guard let self, self.attached, self.controller === pictureInPictureController else { return }
                if self.restoring { self.restoring = false }
                else { self.pictureInPicture?.didStop(owner: self.owner, restoring: false) }
                self.publishCapability()
            }
        }
        nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.attached, self.controller === pictureInPictureController else { return }
                self.pictureInPicture?.failed(message, owner: self.owner)
            }
        }
        nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void) {
            Task { @MainActor [weak self] in
                guard let self, self.attached, self.controller === pictureInPictureController else { completionHandler(false); return }
                self.restoring = true
                self.pictureInPicture?.didStop(owner: self.owner, restoring: true)
                completionHandler(true)
            }
        }
    }
}
