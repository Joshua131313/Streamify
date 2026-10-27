import AVFoundation
import Foundation

struct HLSDownloadIdentity: Hashable, Codable, Sendable {
    let id: UUID
    let attempt: UUID
    let taskIdentifier: Int

    var taskDescription: String { "\(id.uuidString)|\(attempt.uuidString)" }
    fileprivate var attemptKey: String { taskDescription }

    static func parse(_ description: String?, taskIdentifier: Int) -> Self? {
        guard let description else { return nil }
        let parts = description.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
              let attempt = UUID(uuidString: String(parts[1])) else { return nil }
        return Self(id: id, attempt: attempt, taskIdentifier: taskIdentifier)
    }
}

struct HLSDownloadedVariant: Codable, Hashable, Sendable {
    let width: Int
    let height: Int

    fileprivate init?(_ variant: AVAssetVariant) {
        guard let size = variant.videoAttributes?.presentationSize,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 65_535, size.height <= 65_535 else { return nil }
        width = Int(size.width.rounded()); height = Int(size.height.rounded())
    }

    init(width: Int, height: Int) { self.width = width; self.height = height }

    func matches(quality: Int) -> Bool {
        (try? OfflineVideoValidation.requireQuality(quality, width: width, height: height)) != nil
    }
}

/// A value snapshot never carries an AVFoundation object across delegate/actor
/// boundaries. Native completion still requires separate offline validation.
struct HLSDownloadSnapshot: Sendable {
    enum Event: String, Sendable {
        case prepared, restored, destination, selection, progress, packageFinished
        case completed, cancelled, failed
    }
    let identity: HLSDownloadIdentity
    let sequence: UInt64
    let event: Event
    let packageURL: URL?
    let packageReference: HLSOwnedPackageReference?
    let selectedVariants: [HLSDownloadedVariant]
    let selectedAudioLanguage: String?
    let fractionCompleted: Double?
    let didFinishPackage: Bool
    let error: HLSDownloadFailure?

    init(identity: HLSDownloadIdentity, sequence: UInt64, event: Event, packageURL: URL?,
         packageReference: HLSOwnedPackageReference? = nil, selectedVariants: [HLSDownloadedVariant],
         selectedAudioLanguage: String?, fractionCompleted: Double?, didFinishPackage: Bool,
         error: HLSDownloadFailure?) {
        self.identity = identity; self.sequence = sequence; self.event = event
        self.packageURL = packageURL; self.packageReference = packageReference
        self.selectedVariants = selectedVariants; self.selectedAudioLanguage = selectedAudioLanguage
        self.fractionCompleted = fractionCompleted; self.didFinishPackage = didFinishPackage; self.error = error
    }
}

struct HLSDownloadFailure: Error, LocalizedError, Codable, Equatable, Sendable {
    let domain: String
    let code: Int
    let message: String
    var errorDescription: String? { message }

    init(_ error: Error) {
        let value = error as NSError
        domain = value.domain; code = value.code
        message = value.localizedDescription.replacingOccurrences(of: #"https?://\S+"#,
            with: "[source URL]", options: .regularExpression)
    }
}

enum HLSDownloadSessionError: LocalizedError {
    case invalidSource, qualityUnavailable, audioUnavailable, metadataTimedOut, alreadyRunning
    case incompletePackage, unsafePackage, unexpectedSelection

    var errorDescription: String? {
        switch self {
        case .invalidSource: return "This source is not a verified, secure HLS video download."
        case .qualityUnavailable: return "This source does not offer the selected download resolution."
        case .audioUnavailable: return "This source does not offer playable audio in the selected language."
        case .metadataTimedOut: return "The download source took too long to respond. Try again."
        case .alreadyRunning: return "A download attempt is already active for this item."
        case .incompletePackage: return "The HLS download did not finish its video and audio package."
        case .unsafePackage: return "The system did not provide a valid local video package."
        case .unexpectedSelection: return "The download selected a different resolution or audio language."
        }
    }
}

/// Persist these values from snapshots. A new launch restores the actual
/// native task by id, attempt AND native identifier, never id alone.
struct HLSDownloadRestoreRecord: Sendable {
    let identity: HLSDownloadIdentity
    let quality: Int
    let audioLanguage: String
    var packageURL: URL? = nil
    var packageReference: HLSOwnedPackageReference? = nil
    var selectedVariants: [HLSDownloadedVariant] = []
    var selectedAudioLanguage: String? = nil
    var didFinishPackage = false
}

@MainActor
protocol HLSDownloadSessionObserver: AnyObject {
    /// Synchronous so early destination/identity persistence completes before
    /// the background-events completion barrier can be released.
    func hlsDownloadSessionOwner(_ owner: HLSDownloadSessionOwner, didReceive snapshot: HLSDownloadSnapshot)
}

/// Native HLS backend. It neither resolves providers nor changes the
/// download library. Apple retains packages at the returned system location.
@MainActor
final class HLSDownloadSessionOwner {
    nonisolated static let sessionIdentifier = "com.streamify.ios.hls-downloads.v1"
    weak var observer: HLSDownloadSessionObserver?

    private var tasks: [String: AVAssetDownloadTask] = [:]
    private var preparing: [String: AVURLAsset] = [:]
    private var lastSequences: [HLSDownloadIdentity: UInt64] = [:]
    /// Cancellation may arrive while getAllTasks is suspended and before an
    /// existing native task has been adopted into this process's task map.
    private var cancelledIdentities = Set<HLSDownloadIdentity>()
    private var completionHolds = Set<UUID>()
    private var completionHandlers: [() -> Void] = []
    private var backgroundEventsFinished = false
    private var restorationRequiredForBackgroundEvents = false
    private var restorationCount = 0
    private let identifier: String
    private let shouldRemovePartialPackage: @MainActor (HLSOwnedPackageReference) -> Bool

    private lazy var delegate: HLSAssetDownloadDelegate = {
        let removalPolicy = shouldRemovePartialPackage
        return HLSAssetDownloadDelegate(deliver: { [weak self] snapshot in
            self?.receive(snapshot)
        }, eventsFinished: { [weak self] in
            self?.backgroundEventsFinished = true
        }, deliveryFinished: { [weak self] in self?.finishBackgroundEventsIfPossible() },
        removePartialPackage: { reference, identity in
            guard reference.identity == identity, removalPolicy(reference) else { return }
            var owned = reference
            try? owned.remove(expectedIdentity: identity)
        })
    }()

    private lazy var session: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let queue = OperationQueue()
        queue.name = "com.streamify.hls.delegate"
        queue.maxConcurrentOperationCount = 1
        return AVAssetDownloadURLSession(configuration: configuration,
            assetDownloadDelegate: delegate, delegateQueue: queue)
    }()

    init(observer: HLSDownloadSessionObserver? = nil,
         shouldRemovePartialPackage: @escaping @MainActor (HLSOwnedPackageReference) -> Bool = { _ in true },
         sessionIdentifier: String = HLSDownloadSessionOwner.sessionIdentifier) {
        self.observer = observer; identifier = sessionIdentifier
        self.shouldRemovePartialPackage = shouldRemovePartialPackage
    }

    var activeIdentities: Set<HLSDownloadIdentity> {
        Set(tasks.values.compactMap { HLSDownloadIdentity.parse($0.taskDescription, taskIdentifier: $0.taskIdentifier) })
    }
    func isPreparing(id: UUID, attempt: UUID) -> Bool {
        preparing["\(id.uuidString)|\(attempt.uuidString)"] != nil
    }
    /// CoreMedia may leave URLSession's byte counter at zero for HLS. Zero is
    /// unknown, not evidence that the download made no network requests.
    func observedBytes(identity: HLSDownloadIdentity) -> Int64 {
        guard let task = tasks[identity.attemptKey], task.taskIdentifier == identity.taskIdentifier else { return 0 }
        return max(0, task.countOfBytesReceived)
    }

    /// Emits .prepared synchronously with the actual native identifier before
    /// resuming. Callers must persist that identity in their observer callback.
    @discardableResult
    func start(id: UUID, attempt: UUID, source: HLSDownloadSource, title: String,
               metadataTimeout: TimeInterval = 12) async throws -> HLSDownloadIdentity {
        guard Self.isSecure(source.masterURL), source.isVOD,
              [360, 480, 720, 1080].contains(source.quality), !source.audioLanguage.isEmpty else {
            throw HLSDownloadSessionError.invalidSource
        }
        // The resolver verifies every selected VOD manifest before creating
        // this descriptor. Ordinary identity AES-128 is handled by Apple;
        // unknown/DRM protection is never represented as a verified source.
        switch source.protection { case .clearOrIdentityAES128: break }
        let key = "\(id.uuidString)|\(attempt.uuidString)"
        guard !tasks.keys.contains(where: { $0.hasPrefix(id.uuidString + "|") }),
              !preparing.keys.contains(where: { $0.hasPrefix(id.uuidString + "|") }) else {
            throw HLSDownloadSessionError.alreadyRunning
        }
        let asset = AVURLAsset(url: source.masterURL)
        preparing[key] = asset
        defer {
            if preparing[key] === asset { preparing[key] = nil }
            finishBackgroundEventsIfPossible()
        }
        let metadata = try await Self.metadata(asset, quality: source.quality,
            language: source.audioLanguage, timeout: metadataTimeout)
        try Task.checkCancellation()
        guard preparing[key] === asset else { throw CancellationError() }
        let configuration = AVAssetDownloadConfiguration(asset: asset, title: title)
        guard let size = metadata.variant.videoAttributes?.presentationSize,
              size.width > 0, size.height > 0 else { throw HLSDownloadSessionError.unexpectedSelection }
        // A qualifier tied to the loaded variant object fails before media
        // transfer on the verified runtime. Typed size predicates retain exact
        // resolution using its public presentation dimensions instead.
        let exactSize = NSCompoundPredicate(andPredicateWithSubpredicates: [
            AVAssetVariantQualifier.predicate(forPresentationWidth: size.width, operatorType: .equalTo),
            AVAssetVariantQualifier.predicate(forPresentationHeight: size.height, operatorType: .equalTo)
        ])
        configuration.primaryContentConfiguration.variantQualifiers = [AVAssetVariantQualifier(predicate: exactSize)]
        configuration.primaryContentConfiguration.mediaSelections = [metadata.selection]
        let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
        let identity = HLSDownloadIdentity(id: id, attempt: attempt, taskIdentifier: task.taskIdentifier)
        task.taskDescription = identity.taskDescription
        tasks[key] = task
        let snapshot = delegate.register(HLSDownloadRestoreRecord(identity: identity,
            quality: source.quality, audioLanguage: source.audioLanguage), audioGroup: metadata.audioGroup, event: .prepared)
        receive(snapshot)
        // Observer persistence may synchronously cancel this attempt.
        if tasks[key] === task, !delegate.isCancelled(identity) { task.resume() }
        return identity
    }

    /// Reconnect only persisted attempts. Unknown or superseded native tasks
    /// are cancelled; their late callbacks cannot overwrite a newer attempt.
    func restoreTasks(records: [HLSDownloadRestoreRecord], metadataTimeout: TimeInterval = 12) async {
        restorationCount += 1
        restorationRequiredForBackgroundEvents = false
        defer { restorationCount -= 1; finishBackgroundEventsIfPossible() }
        let nativeTasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        let expected = Dictionary(records.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        for case let task as AVAssetDownloadTask in nativeTasks {
            guard let identity = HLSDownloadIdentity.parse(task.taskDescription, taskIdentifier: task.taskIdentifier) else {
                delegate.abandon(task); task.cancel(); continue
            }
            if cancelledIdentities.contains(identity) {
                delegate.abandon(task); task.cancel(); continue
            }
            // getAllTasks suspends this actor. A freshly started task may now
            // exist even though the caller's persisted-record snapshot was
            // captured earlier. Never classify our current task as orphaned.
            if tasks[identity.attemptKey]?.taskIdentifier == identity.taskIdentifier { continue }
            guard let record = expected[identity], [360, 480, 720, 1080].contains(record.quality),
                  !record.audioLanguage.isEmpty else {
                delegate.abandon(task); task.cancel(); continue
            }
            tasks[identity.attemptKey] = task
            let restored = delegate.register(record, audioGroup: nil, event: .restored)
            receive(restored)
            if [.failed, .cancelled].contains(restored.event) { task.cancel(); continue }
            do {
                let group = try await Self.audioGroup(task.urlAsset, language: record.audioLanguage, timeout: metadataTimeout)
                guard !cancelledIdentities.contains(identity), tasks[identity.attemptKey] === task,
                      delegate.canResume(identity) else { continue }
                if !delegate.bindAudioGroup(group, identity: identity) { task.cancel(); continue }
                // The process may have stopped after persisting .prepared
                // and before resume(). Metadata must be rechecked first,
                // then this exact still-current suspended task can resume.
                if !cancelledIdentities.contains(identity), tasks[identity.attemptKey] === task,
                   delegate.canResume(identity), task.state == .suspended {
                    task.resume()
                }
            } catch {
                delegate.fail(identity, error: error)
                task.cancel()
            }
        }
    }

    /// Cancellation never deletes an already completed package. Explicit
    /// library deletion uses removeOwnedPackage after the caller's own checks.
    func cancel(_ identity: HLSDownloadIdentity, removePartialPackage: Bool = true) {
        cancelledIdentities.insert(identity)
        delegate.cancel(identity, removePartialPackage: removePartialPackage)
        guard let task = tasks[identity.attemptKey], task.taskIdentifier == identity.taskIdentifier else { return }
        task.cancel()
        tasks[identity.attemptKey] = nil
    }

    func cancelPreparation(id: UUID, attempt: UUID) {
        let key = "\(id.uuidString)|\(attempt.uuidString)"
        preparing.removeValue(forKey: key)?.cancelLoading()
        finishBackgroundEventsIfPossible()
    }

    /// Only a reference registered for this exact native task is eligible.
    /// Preserve the system's URL/access context, including /.nofollow paths.
    func removeOwnedPackage(identity: HLSDownloadIdentity, packageURL: URL) throws {
        guard var reference = delegate.registeredReference(packageURL, identity: identity) else {
            throw HLSDownloadSessionError.unsafePackage
        }
        try reference.remove(expectedIdentity: identity)
    }

    func registerBackgroundCompletion(_ completion: @escaping () -> Void) {
        if completionHandlers.isEmpty { backgroundEventsFinished = false }
        // The app delegate must reconnect persisted attempts after registering
        // its closure. Do not finish if delegate events beat that actor hop.
        restorationRequiredForBackgroundEvents = true
        completionHandlers.append(completion)
        _ = session
    }

    /// Hold independently while the caller validates or persists a completed
    /// package. No progressive-download session's completion closure is used.
    func beginCompletionBarrier() -> UUID {
        let token = UUID(); completionHolds.insert(token); return token
    }
    func endCompletionBarrier(_ token: UUID) {
        completionHolds.remove(token); finishBackgroundEventsIfPossible()
    }

    private func receive(_ snapshot: HLSDownloadSnapshot) {
        if cancelledIdentities.contains(snapshot.identity),
           ![.cancelled, .failed].contains(snapshot.event) { return }
        guard snapshot.sequence > (lastSequences[snapshot.identity] ?? 0) else { return }
        lastSequences[snapshot.identity] = snapshot.sequence
        switch snapshot.event {
        case .completed, .cancelled, .failed:
            if tasks[snapshot.identity.attemptKey]?.taskIdentifier == snapshot.identity.taskIdentifier {
                tasks[snapshot.identity.attemptKey] = nil
            }
        default: break
        }
        observer?.hlsDownloadSessionOwner(self, didReceive: snapshot)
    }

    private func finishBackgroundEventsIfPossible() {
        guard backgroundEventsFinished, preparing.isEmpty, restorationCount == 0,
              !restorationRequiredForBackgroundEvents, completionHolds.isEmpty,
              !delegate.hasPendingDeliveries, !completionHandlers.isEmpty else { return }
        backgroundEventsFinished = false
        let handlers = completionHandlers; completionHandlers.removeAll()
        handlers.forEach { $0() }
    }

    private struct Metadata: @unchecked Sendable {
        let variant: AVAssetVariant
        let audioGroup: AVMediaSelectionGroup
        let selection: AVMutableMediaSelection
    }

    private static func metadata(_ asset: AVURLAsset, quality: Int, language: String,
                                 timeout: TimeInterval) async throws -> Metadata {
        try await bounded(asset: asset, timeout: timeout) {
            let (playable, duration) = try await asset.load(.isPlayable, .duration)
            guard playable, duration.seconds.isFinite, duration.seconds > 0 else { throw HLSDownloadSessionError.invalidSource }
            let variants = try await asset.load(.variants)
            guard let variant = variants.filter({ HLSDownloadedVariant($0)?.matches(quality: quality) == true })
                .max(by: { ($0.peakBitRate ?? 0) < ($1.peakBitRate ?? 0) }) else { throw HLSDownloadSessionError.qualityUnavailable }
            let preferred = try await asset.load(.preferredMediaSelection)
            guard let group = try await asset.loadMediaSelectionGroup(for: .audible),
                  let option = group.options.first(where: { $0.isPlayable && OfflineHLSValidation.isRequestedLanguage($0, language: language) }),
                  let selection = preferred.mutableCopy() as? AVMutableMediaSelection else {
                throw HLSDownloadSessionError.audioUnavailable
            }
            selection.select(option, in: group)
            return Metadata(variant: variant, audioGroup: group, selection: selection)
        }
    }

    private static func audioGroup(_ asset: AVURLAsset, language: String, timeout: TimeInterval) async throws -> AVMediaSelectionGroup {
        try await bounded(asset: asset, timeout: timeout) {
            guard let group = try await asset.loadMediaSelectionGroup(for: .audible),
                  group.options.contains(where: { $0.isPlayable && OfflineHLSValidation.isRequestedLanguage($0, language: language) }) else {
                throw HLSDownloadSessionError.audioUnavailable
            }
            return group
        }
    }

    private static func bounded<Value>(asset: AVURLAsset, timeout: TimeInterval,
                                       operation: @escaping () async throws -> Value) async throws -> Value {
        let seconds = timeout.isFinite ? min(60, max(0.1, timeout)) : 12
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    asset.cancelLoading()
                    throw HLSDownloadSessionError.metadataTimedOut
                }
                defer { group.cancelAll() }
                guard let value = try await group.next() else { throw CancellationError() }
                try Task.checkCancellation()
                return value
            }
        } onCancel: { asset.cancelLoading() }
    }

    private static func isSecure(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
            && url.fragment == nil && (url.port == nil || url.port == 443)
    }
}

/// All callbacks are serialized by the session's delegate queue. State also
/// uses a lock because registration/cancellation originates on the main actor.
private final class HLSAssetDownloadDelegate: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    private struct State {
        let identity: HLSDownloadIdentity
        var registered = false
        var quality: Int?
        var language = ""
        var audioGroup: AVMediaSelectionGroup?
        var resolvedSelection: AVMediaSelection?
        var selectedLanguage: String?
        var variants: [HLSDownloadedVariant] = []
        var location: URL?
        var packageReference: HLSOwnedPackageReference?
        var fraction: Double?
        var didFinish = false
        var transportComplete = false
        var terminalSent = false
        var cancelled = false
        var removePartialOnCancel = true
        var discardPartial = false
        var failure: HLSDownloadFailure?
        var sequence: UInt64 = 0
    }
    private let lock = NSLock()
    private var states: [HLSDownloadIdentity: State] = [:]
    private var pendingDeliveries = 0
    private let deliver: @MainActor (HLSDownloadSnapshot) -> Void
    private let eventsFinished: @MainActor () -> Void
    private let deliveryFinished: @MainActor () -> Void
    private let removePartialPackage: @MainActor (HLSOwnedPackageReference, HLSDownloadIdentity) -> Void

    init(deliver: @escaping @MainActor (HLSDownloadSnapshot) -> Void,
         eventsFinished: @escaping @MainActor () -> Void, deliveryFinished: @escaping @MainActor () -> Void,
         removePartialPackage: @escaping @MainActor (HLSOwnedPackageReference, HLSDownloadIdentity) -> Void) {
        self.deliver = deliver; self.eventsFinished = eventsFinished; self.deliveryFinished = deliveryFinished
        self.removePartialPackage = removePartialPackage
    }

    var hasPendingDeliveries: Bool { lock.lock(); defer { lock.unlock() }; return pendingDeliveries > 0 }

    func register(_ record: HLSDownloadRestoreRecord, audioGroup: AVMediaSelectionGroup?,
                  event: HLSDownloadSnapshot.Event) -> HLSDownloadSnapshot {
        // Decoded provisional external URLs have no authority. Only a valid
        // durable bookmark for this exact identity may restore access without
        // a fresh destination callback. Never call nativeCallback on metadata.
        var restoredReference: HLSOwnedPackageReference?
        var restoredLocation: URL?
        if var reference = record.packageReference, reference.identity == record.identity, reference.isDurable,
           let location = try? reference.resolve(expectedIdentity: record.identity) {
            restoredReference = reference; restoredLocation = location
        }
        let legacyLocation = record.packageURL.flatMap { location -> URL? in
            (try? HLSDownloadedPackages.relativePath(of: location)) == nil ? nil : location
        }
        lock.lock(); defer { lock.unlock() }
        var state = states[record.identity] ?? State(identity: record.identity)
        state.registered = true; state.quality = record.quality; state.language = record.audioLanguage
        state.audioGroup = audioGroup
        if state.packageReference == nil, let restoredReference {
            state.packageReference = restoredReference; state.location = restoredLocation
        } else if state.location == nil {
            // Backward-compatible contained paths may be retained as hints,
            // but do not gain native-callback or external deletion authority.
            state.location = legacyLocation
        }
        if state.variants.isEmpty { state.variants = record.selectedVariants }
        if state.selectedLanguage == nil { state.selectedLanguage = record.selectedAudioLanguage }
        state.didFinish = state.didFinish || record.didFinishPackage
        let actualEvent: HLSDownloadSnapshot.Event = state.terminalSent
            ? (state.cancelled ? .cancelled : (state.failure == nil ? .completed : .failed)) : event
        let snapshot = Self.snapshot(&state, event: actualEvent)
        states[record.identity] = state
        return snapshot
    }

    @discardableResult
    func bindAudioGroup(_ group: AVMediaSelectionGroup, identity: HLSDownloadIdentity) -> Bool {
        update(identity, event: .selection) { state in
            state.audioGroup = group
            if let selection = state.resolvedSelection {
                state.selectedLanguage = Self.language(selection, group: group)
            }
        }
        guard selectionIsValidIfKnown(identity) else {
            fail(identity, error: HLSDownloadSessionError.unexpectedSelection)
            return false
        }
        finalize(identity)
        return true
    }

    func isCancelled(_ identity: HLSDownloadIdentity) -> Bool {
        lock.lock(); defer { lock.unlock() }; return states[identity]?.cancelled ?? true
    }
    func canResume(_ identity: HLSDownloadIdentity) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let state = states[identity] else { return false }
        return !state.cancelled && !state.terminalSent
    }
    func registeredReference(_ url: URL, identity: HLSDownloadIdentity) -> HLSOwnedPackageReference? {
        lock.lock(); defer { lock.unlock() }
        guard let location = states[identity]?.location,
              location == url, let reference = states[identity]?.packageReference,
              reference.identity == identity else { return nil }
        return reference
    }
    func cancel(_ identity: HLSDownloadIdentity, removePartialPackage: Bool) {
        lock.lock()
        guard var state = states[identity], !state.terminalSent else { lock.unlock(); return }
        state.cancelled = true; state.removePartialOnCancel = removePartialPackage
        state.discardPartial = removePartialPackage; state.terminalSent = true
        let reference = removePartialPackage ? state.packageReference : nil
        let snapshot = Self.snapshot(&state, event: .cancelled)
        states[identity] = state; lock.unlock()
        removeOwnedPartial(reference, identity: identity); enqueue(snapshot)
    }
    func fail(_ identity: HLSDownloadIdentity, error: Error) {
        lock.lock()
        guard var state = states[identity], !state.terminalSent else { lock.unlock(); return }
        state.failure = HLSDownloadFailure(error); state.terminalSent = true; state.discardPartial = true
        let snapshot = state.registered ? Self.snapshot(&state, event: .failed) : nil
        states[identity] = state; lock.unlock()
        removeOwnedPartial(state.packageReference, identity: identity)
        if let snapshot { enqueue(snapshot) }
    }
    func abandon(_ task: AVAssetDownloadTask) {
        guard let identity = HLSDownloadIdentity.parse(task.taskDescription, taskIdentifier: task.taskIdentifier) else { return }
        lock.lock()
        var state = states[identity] ?? State(identity: identity)
        // Cancelling a late task listing must not erase a package whose
        // native completion has already been accepted.
        if state.terminalSent && !state.cancelled && state.failure == nil { lock.unlock(); return }
        state.cancelled = true; state.terminalSent = true; state.discardPartial = true
        let reference = state.packageReference; states[identity] = state
        lock.unlock(); removeOwnedPartial(reference, identity: identity)
    }

    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, willDownloadTo location: URL) {
        destination(task, location: location, didFinish: false)
    }
    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        destination(task, location: location, didFinish: true)
    }
    private func destination(_ task: AVAssetDownloadTask, location: URL, didFinish: Bool) {
        guard let identity = capture(task) else { return }
        lock.lock()
        guard var state = states[identity], !state.terminalSent || state.discardPartial else { lock.unlock(); return }
        do {
            if var reference = state.packageReference {
                try reference.reassociateNativeCallback(location: location, identity: identity)
                state.packageReference = reference
            } else {
                state.packageReference = try HLSOwnedPackageReference.nativeCallback(location: location, identity: identity)
            }
        } catch {
            lock.unlock()
            fail(identity, error: error); task.cancel(); return
        }
        // Retain the exact system-supplied URL, never a stripped/reconstructed
        // app-home path. The reference certifies ownership, not completion.
        state.location = location; state.didFinish = state.didFinish || didFinish
        let snapshot = state.registered && !state.terminalSent
            ? Self.snapshot(&state, event: didFinish ? .packageFinished : .destination) : nil
        states[identity] = state; lock.unlock()
        if state.discardPartial { removeOwnedPartial(state.packageReference, identity: identity) }
        if let snapshot { enqueue(snapshot) }
    }
    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, willDownloadVariants variants: [AVAssetVariant]) {
        guard let identity = capture(task) else { return }
        update(identity, event: .selection) { $0.variants = variants.compactMap(HLSDownloadedVariant.init) }
        if !selectionIsValidIfKnown(identity) {
            fail(identity, error: HLSDownloadSessionError.unexpectedSelection); task.cancel()
        }
    }
    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, didResolve selection: AVMediaSelection) {
        guard let identity = capture(task) else { return }
        update(identity, event: .selection) { state in
            state.resolvedSelection = selection
            if let group = state.audioGroup { state.selectedLanguage = Self.language(selection, group: group) }
        }
        if !selectionIsValidIfKnown(identity) {
            fail(identity, error: HLSDownloadSessionError.unexpectedSelection); task.cancel()
        }
    }
    func urlSession(_ session: URLSession, assetDownloadTask task: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded ranges: [NSValue], timeRangeExpectedToLoad expected: CMTimeRange) {
        guard let identity = capture(task) else { return }
        let fraction = HLSDownloadProgress.fraction(loaded: ranges.map(\.timeRangeValue), expected: expected)
        update(identity, event: .progress) { $0.fraction = fraction }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let task = task as? AVAssetDownloadTask, let identity = capture(task) else { return }
        if let error {
            if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                cancel(identity, removePartialPackage: true)
            } else { fail(identity, error: error) }
            return
        }
        lock.lock()
        if var state = states[identity] { state.transportComplete = true; states[identity] = state }
        lock.unlock()
        finalize(identity)
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        enqueueAction { [eventsFinished] in eventsFinished() }
    }

    private func capture(_ task: AVAssetDownloadTask) -> HLSDownloadIdentity? {
        guard let identity = HLSDownloadIdentity.parse(task.taskDescription, taskIdentifier: task.taskIdentifier) else { return nil }
        lock.lock(); if states[identity] == nil { states[identity] = State(identity: identity) }; lock.unlock()
        return identity
    }
    private func update(_ identity: HLSDownloadIdentity, event: HLSDownloadSnapshot.Event, allowTerminal: Bool = false,
                        action: (inout State) -> Void) {
        lock.lock()
        guard var state = states[identity], allowTerminal || !state.terminalSent else { lock.unlock(); return }
        action(&state)
        let snapshot = state.registered ? Self.snapshot(&state, event: event) : nil
        states[identity] = state; lock.unlock()
        if let snapshot { enqueue(snapshot) }
    }
    private func finalize(_ identity: HLSDownloadIdentity) {
        lock.lock()
        guard var state = states[identity], state.registered, state.transportComplete,
              !state.terminalSent, let quality = state.quality, state.audioGroup != nil else { lock.unlock(); return }
        let validSelection = !state.variants.isEmpty && state.variants.allSatisfy { $0.matches(quality: quality) }
            && Self.matchesLanguage(state.selectedLanguage, requested: state.language)
        if !state.didFinish || state.location == nil { state.failure = HLSDownloadFailure(HLSDownloadSessionError.incompletePackage) }
        else if state.packageReference == nil { state.failure = HLSDownloadFailure(HLSDownloadSessionError.unsafePackage) }
        else if !validSelection { state.failure = HLSDownloadFailure(HLSDownloadSessionError.unexpectedSelection) }
        state.discardPartial = state.failure != nil
        state.terminalSent = true
        let snapshot = Self.snapshot(&state, event: state.failure == nil ? .completed : .failed)
        states[identity] = state; lock.unlock()
        if state.discardPartial { removeOwnedPartial(state.packageReference, identity: identity) }
        enqueue(snapshot)
    }
    private func selectionIsValidIfKnown(_ identity: HLSDownloadIdentity) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let state = states[identity], state.registered else { return true }
        if let quality = state.quality, !state.variants.isEmpty,
           !state.variants.allSatisfy({ $0.matches(quality: quality) }) { return false }
        if state.audioGroup != nil, state.resolvedSelection != nil,
           !Self.matchesLanguage(state.selectedLanguage, requested: state.language) { return false }
        return true
    }
    private static func snapshot(_ state: inout State, event: HLSDownloadSnapshot.Event) -> HLSDownloadSnapshot {
        state.sequence &+= 1
        return HLSDownloadSnapshot(identity: state.identity, sequence: state.sequence, event: event,
            packageURL: state.location, packageReference: state.packageReference,
            selectedVariants: state.variants, selectedAudioLanguage: state.selectedLanguage,
            fractionCompleted: state.fraction, didFinishPackage: state.didFinish, error: state.failure)
    }
    private static func language(_ selection: AVMediaSelection, group: AVMediaSelectionGroup) -> String? {
        guard let option = selection.selectedMediaOption(in: group), option.isPlayable else { return nil }
        return option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
    }
    private static func matchesLanguage(_ actual: String?, requested: String) -> Bool {
        guard let actual, !actual.isEmpty, !requested.isEmpty else { return false }
        return actual.lowercased().prefix(2) == requested.lowercased().prefix(2)
    }
    private func removeOwnedPartial(_ value: HLSOwnedPackageReference?, identity: HLSDownloadIdentity) {
        guard let reference = value, reference.identity == identity else { return }
        // Library retention policy is main-actor state. Count and enqueue
        // BEFORE hopping so a background completion cannot outrun the guard
        // or physical deletion. Unknown/aliased retained packages may veto it.
        enqueueAction { [removePartialPackage] in removePartialPackage(reference, identity) }
    }
    private func enqueue(_ snapshot: HLSDownloadSnapshot) {
        enqueueAction { [deliver] in deliver(snapshot) }
    }
    /// Count before hopping executors. Even if a future actor-hop mechanism
    /// reorders tasks, completion cannot outrun pending observer persistence.
    private func enqueueAction(_ action: @escaping @MainActor () -> Void) {
        lock.lock(); pendingDeliveries += 1; lock.unlock()
        DispatchQueue.main.async { [self] in
            action()
            lock.lock(); pendingDeliveries -= 1; lock.unlock()
            deliveryFinished()
        }
    }
}
