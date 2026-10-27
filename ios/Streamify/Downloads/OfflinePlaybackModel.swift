import Foundation
import AVFoundation
import Combine

enum OfflinePlaybackPolicy {
    static func seek(_ position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, position), duration)
    }
    static func resume(_ position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0,
              position >= 5, position < duration * 0.95 else { return 0 }
        return position
    }
    static func isAtEnd(_ position: Double, duration: Double) -> Bool {
        position.isFinite && duration.isFinite && duration > 0 && position >= duration - 1.0 / 600.0
    }
}

/// Owns the precise player used to register its periodic observer. Cleanup is
/// synchronous and does not call actor-isolated model methods from deinit.
private final class OfflinePlaybackObservers {
    var player: AVPlayer?
    var time: Any?
    var observations: [NSKeyValueObservation] = []
    var notifications: [NSObjectProtocol] = []
    func clear() {
        observations.forEach { $0.invalidate() }; observations.removeAll()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }; notifications.removeAll()
        if let time { player?.removeTimeObserver(time) }
        player?.pause()
        time = nil; player = nil
    }
    deinit { clear() }
}

@MainActor
final class OfflinePlaybackModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published private(set) var isBuffering = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var seekMessage: String?
    @Published private(set) var videoError: OfflineVideoError?
    @Published private(set) var rate: Float = 1
    @Published private(set) var finished = false
    @Published private(set) var audioGroup: AVMediaSelectionGroup?
    @Published private(set) var subtitleGroup: AVMediaSelectionGroup?
    @Published private(set) var selectedAudioOption: AVMediaSelectionOption?
    @Published private(set) var selectedSubtitleOption: AVMediaSelectionOption?
    var onProgress: ((Double, Double) -> Void)?

    private let defaults: UserDefaults
    private let observers = OfflinePlaybackObservers()
    private var generation = UUID()
    private var seekController: OfflineSeekController?
    private var itemID: UUID?
    private var wantsPlayback = false
    private var restored = false
    private var seeking = false
    private var resumePoint: Double = 0
    private var checkpoint = PlaybackCheckpoint()
    private var localSavedAt = -Double.infinity
    private var localSavedPosition = -Double.infinity
    private var usesOfflinePackage = false

    func availableOptions(in group: AVMediaSelectionGroup) -> [AVMediaSelectionOption] {
        guard usesOfflinePackage else { return group.options }
        guard let asset = player?.currentItem?.asset as? AVURLAsset, let cache = asset.assetCache else { return [] }
        return cache.mediaSelectionOptions(in: group).filter { $0.isPlayable }
    }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(item: DownloadItem) async {
        teardown()
        let request = UUID(); generation = request; itemID = item.id
        isBuffering = true; error = nil; videoError = nil; finished = false; wantsPlayback = true
        guard let url = item.fileURL else { fail(.missingFile); return }
        do {
            let isHLSPackage = item.transport == .hlsVOD
            let asset: AVURLAsset
            let loadedDuration: Double
            let preferredAudio: AVMediaSelectionOption?
            let validatedAudioGroup: AVMediaSelectionGroup?
            if isHLSPackage {
                let validated: OfflineHLSValidation.Result
                if let reference = item.hlsPackageReference {
                    guard item.owns(reference: reference) else { throw OfflineVideoError.missingFile }
                    validated = try await OfflineHLSValidation.validate(reference: reference, expectedIdentity: reference.identity,
                        quality: item.quality, audioLanguage: item.sourceAudioLanguage ?? "en")
                } else {
                    validated = try await OfflineHLSValidation.validate(url, quality: item.quality,
                        audioLanguage: item.sourceAudioLanguage ?? "en")
                }
                asset = validated.asset; loadedDuration = validated.duration; preferredAudio = validated.audioOption
                validatedAudioGroup = validated.audioGroup
            } else {
                let validated = try await OfflineVideoValidation.validate(url)
                asset = validated.asset; loadedDuration = validated.duration; preferredAudio = nil
                validatedAudioGroup = nil
            }
            try Task.checkCancellation()
            guard generation == request else { return }
            let audio: AVMediaSelectionGroup?
            if let validatedAudioGroup { audio = validatedAudioGroup }
            else { audio = try? await asset.loadMediaSelectionGroup(for: .audible) }
            let subtitles = try? await asset.loadMediaSelectionGroup(for: .legible)
            try Task.checkCancellation()
            guard generation == request else { return }
            try PlaybackAudioSession.activate()
            usesOfflinePackage = isHLSPackage
            duration = loadedDuration; audioGroup = audio; subtitleGroup = subtitles
            let saved = defaults.dictionary(forKey: storageKey(item.id))
            resumePoint = OfflinePlaybackPolicy.resume((saved?["position"] as? NSNumber)?.doubleValue ?? 0, duration: duration)
            let item = AVPlayerItem(asset: asset)
            if let audio, let preferredAudio { item.select(preferredAudio, in: audio) }
            let created = AVPlayer(playerItem: item)
            created.allowsExternalPlayback = true
            player = created; observers.player = created
            seekController = OfflineSeekController(driver: AVPlayerOfflineSeekDriver(player: created)) { [weak self] result in
                guard let self, self.generation == request else { return }
                self.seeking = false
                switch result {
                case .completed(let actual):
                    self.position = OfflinePlaybackPolicy.seek(actual, duration: self.duration)
                    // A paused seek to EOF need not emit a play-to-end event.
                    // Derive the ending state from the actual native playhead.
                    if OfflinePlaybackPolicy.isAtEnd(actual, duration: self.duration) {
                        self.finished = true; self.wantsPlayback = false; self.isPlaying = false
                    }
                case .failed(let actual):
                    if let actual { self.position = OfflinePlaybackPolicy.seek(actual, duration: self.duration) }
                    self.seekMessage = "Couldn’t seek to that point. Try again."
                }
                self.capture(force: true)
                if self.wantsPlayback { self.player?.playImmediately(atRate: self.rate) }
                else { self.player?.pause() }
                self.isBuffering = self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
            if let audio { selectedAudioOption = item.currentMediaSelection.selectedMediaOption(in: audio) }
            if let subtitles { selectedSubtitleOption = item.currentMediaSelection.selectedMediaOption(in: subtitles) }
            observers.observations.append(item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    if observed.status == .readyToPlay { self.prepareToPlay(request: request) }
                    else if observed.status == .failed { self.fail(observed.error.map { OfflineVideoError.classify($0) } ?? .unplayable) }
                }
            })
            observers.observations.append(created.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    self.isPlaying = observed.timeControlStatus == .playing
                    self.isBuffering = self.seeking || !self.isReady || observed.timeControlStatus == .waitingToPlayAtSpecifiedRate
                    if self.isPlaying, observed.rate != self.rate { observed.rate = self.rate }
                    if observed.timeControlStatus == .paused { self.capture(force: true) }
                }
            })
            observers.time = created.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }; self.capture()
                }
            }
            observers.notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request, !self.seeking,
                          let actual = self.player?.currentTime().seconds, actual.isFinite,
                          actual >= self.duration - 0.5 else { return }
                    self.finished = true; self.wantsPlayback = false; self.isPlaying = false
                    self.position = self.duration; self.capture(force: true)
                    if let id = self.itemID { self.defaults.removeObject(forKey: self.storageKey(id)) }
                }
            })
            observers.notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                let problem = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error).map { OfflineVideoError.classify($0) } ?? .unplayable
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }; self.fail(problem)
                }
            })
        } catch is CancellationError {
            if generation == request { teardown() }
        } catch {
            if generation == request { fail(OfflineVideoError.classify(error)) }
        }
    }

    private func prepareToPlay(request: UUID) {
        guard !restored, generation == request, let player else { return }
        restored = true; isReady = true
        if resumePoint > 0 { seek(to: resumePoint) }
        else {
            isBuffering = false
            if wantsPlayback { player.playImmediately(atRate: rate) }
        }
    }

    func togglePlayback() {
        guard let player, isReady else { return }
        if isPlaying || wantsPlayback {
            wantsPlayback = false; player.pause(); capture(force: true)
        } else {
            wantsPlayback = true
            if finished { replay() }
            else if !seeking { player.playImmediately(atRate: rate) }
        }
    }

    func seek(to seconds: Double) {
        guard isReady, seconds.isFinite, let player, player.currentItem != nil, let seekController else { return }
        let target = OfflinePlaybackPolicy.seek(seconds, duration: duration)
        finished = false; seekMessage = nil; isBuffering = true; seeking = true
        player.pause()
        seekController.seek(to: target)
    }

    func skip(by seconds: Double) { guard seconds.isFinite else { return }; seek(to: (seekController?.pendingTarget ?? position) + seconds) }
    func replay() {
        guard isReady else { return }
        wantsPlayback = true; seek(to: 0)
    }
    func setRate(_ value: Float) {
        guard value.isFinite, (0.5...2).contains(value) else { return }
        rate = value
        if isPlaying { player?.rate = value }
    }
    func select(option: AVMediaSelectionOption?, group: AVMediaSelectionGroup) {
        guard group === audioGroup || group === subtitleGroup,
              option.map({ availableOptions(in: group).contains($0) }) ?? group.allowsEmptySelection else { return }
        player?.currentItem?.select(option, in: group)
        if group === audioGroup { selectedAudioOption = option }
        if group === subtitleGroup { selectedSubtitleOption = option }
    }
    func pauseForBackground() { wantsPlayback = false; player?.pause(); capture(force: true) }

    func teardown() {
        capture(force: true)
        generation = UUID(); seekController?.cancel(); seekController = nil
        observers.clear(); player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        isPlaying = false; isReady = false; isBuffering = false; wantsPlayback = false
        restored = false; seeking = false; resumePoint = 0; position = 0; duration = 0; finished = false
        audioGroup = nil; subtitleGroup = nil; selectedAudioOption = nil; selectedSubtitleOption = nil
        checkpoint = PlaybackCheckpoint(); localSavedAt = -Double.infinity; localSavedPosition = -Double.infinity
        itemID = nil
        usesOfflinePackage = false
        seekMessage = nil
    }

    private func capture(force: Bool = false) {
        guard restored, !seeking, let player, let id = itemID, duration.isFinite, duration > 0 else { return }
        let raw = finished ? duration : player.currentTime().seconds
        guard raw.isFinite, raw >= 0 else { return }
        position = OfflinePlaybackPolicy.seek(raw, duration: duration)
        let now = ProcessInfo.processInfo.systemUptime
        if abs(position - localSavedPosition) >= 1, now - localSavedAt >= (force ? 1 : 5) {
            if position >= duration * 0.95 { defaults.removeObject(forKey: storageKey(id)) }
            else { defaults.set(["position": position, "duration": duration], forKey: storageKey(id)) }
            localSavedAt = now; localSavedPosition = position
        }
        if let sample = checkpoint.sample(position: position, duration: duration, now: now, force: force) {
            onProgress?(sample.position, sample.duration)
        }
    }
    private func storageKey(_ id: UUID) -> String { "streamify.ios.offlinePlayback.\(id.uuidString)" }
    private func fail(_ problem: OfflineVideoError) {
        seekController?.cancel(); seeking = false
        wantsPlayback = false; player?.pause(); isPlaying = false; isBuffering = false
        videoError = problem; error = problem.localizedDescription
    }
}
