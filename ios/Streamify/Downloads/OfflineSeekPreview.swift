import SwiftUI
import AVFoundation
import Combine

enum OfflineSeekPreviewMath {
    static func second(position: Double, duration: Double) -> Int? {
        guard position.isFinite, duration.isFinite, duration > 0 else { return nil }
        let bounded = min(max(0, position), max(0, duration - 0.05)).rounded(.down)
        return Int(exactly: bounded)
    }
    static func center(thumbX: CGFloat, viewportWidth: CGFloat, previewWidth: CGFloat = 208) -> CGFloat {
        guard thumbX.isFinite, viewportWidth.isFinite, previewWidth.isFinite,
              viewportWidth > 0, previewWidth > 0 else { return 0 }
        guard viewportWidth >= previewWidth else { return viewportWidth / 2 }
        return min(viewportWidth - previewWidth / 2, max(previewWidth / 2, thumbX))
    }
    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, let value = Int(exactly: max(0, seconds).rounded(.down)) else { return "0:00" }
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

private final class OfflineSeekPreviewResources {
    var asset: AVURLAsset?
    var generator: AVAssetImageGenerator?
    func cancel() { generator?.cancelAllCGImageGeneration() }
    func clear() { cancel(); asset?.cancelLoading(); generator = nil; asset = nil }
    deinit { clear() }
}

/// Conflates thumb updates: one local-frame decode runs at a time, and only the
/// latest requested second may appear. Twelve 320x180 frames bound memory use.
@MainActor
final class OfflineSeekPreviewModel: ObservableObject {
    typealias FrameLoader = (AVAssetImageGenerator, CMTime) async throws -> CGImage
    @Published private(set) var image: UIImage?
    @Published private(set) var visible = false
    @Published private(set) var loading = false
    @Published private(set) var seconds: Double = 0
    private let resources = OfflineSeekPreviewResources()
    private let frameLoader: FrameLoader
    private var source: URL?
    private var generation = UUID()
    private var latest: Int?
    private var pending: Int?
    private var decoding: Int?
    private var frames: [Int: UIImage] = [:]
    private var unavailable = Set<Int>()
    private var cacheOrder: [Int] = []
    private var worker: Task<Void, Never>?

    init(frameLoader: @escaping FrameLoader = { generator, time in
        let result = try await generator.image(at: time)
        return result.image
    }) { self.frameLoader = frameLoader }

    func show(url: URL, seconds: Double, duration: Double) {
        guard url.isFileURL, let second = OfflineSeekPreviewMath.second(position: seconds, duration: duration) else { hide(); return }
        if source != url {
            close(); source = url
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = CGSize(width: 320, height: 180)
            generator.appliesPreferredTrackTransform = true
            // The default time tolerance permits a nearby sync frame, matching
            // Android MediaMetadataRetriever.OPTION_CLOSEST_SYNC.
            resources.asset = asset; resources.generator = generator
        }
        visible = true; self.seconds = Double(second)
        if latest == second, image != nil || decoding == second { return }
        latest = second
        if let cached = frames[second] {
            pending = nil; touchCache(second); image = cached; loading = false
            return
        }
        if unavailable.contains(second) { pending = nil; image = nil; loading = false; return }
        if decoding == second { pending = nil; image = nil; loading = true; return }
        image = nil; loading = true; pending = second
        drain()
    }

    func hide() {
        generation = UUID(); worker?.cancel(); worker = nil
        resources.cancel(); pending = nil; decoding = nil; latest = nil
        visible = false; loading = false; image = nil
    }
    func close() {
        hide(); resources.clear(); source = nil; frames.removeAll(); unavailable.removeAll(); cacheOrder.removeAll()
    }

    private func drain() {
        guard worker == nil, let generator = resources.generator else { return }
        let request = generation, load = frameLoader
        worker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == request, let second = self.pending else { break }
                self.pending = nil; self.decoding = second
                do {
                    let frame = try await load(generator, CMTime(seconds: Double(second), preferredTimescale: 600))
                    guard !Task.isCancelled, self.generation == request else { return }
                    let picture = UIImage(cgImage: frame)
                    self.frames[second] = picture; self.touchCache(second)
                    if self.visible, self.latest == second { self.image = picture; self.loading = false }
                } catch {
                    guard !Task.isCancelled, self.generation == request else { return }
                    self.unavailable.insert(second); self.touchCache(second)
                    if self.visible, self.latest == second { self.image = nil; self.loading = false }
                }
                self.decoding = nil
            }
            guard let self, self.generation == request else { return }
            self.worker = nil
            if self.pending != nil { self.drain() }
        }
    }
    private func touchCache(_ second: Int) {
        cacheOrder.removeAll { $0 == second }; cacheOrder.append(second)
        while cacheOrder.count > 12 {
            let oldest = cacheOrder.removeFirst()
            frames.removeValue(forKey: oldest); unavailable.remove(oldest)
        }
    }
}

/// Android's 208x117 fit-center frame, 6pt radius, black 2pt border and 24pt clock.
struct OfflineSeekPreviewBubble: View {
    @ObservedObject var model: OfflineSeekPreviewModel
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let image = model.image { Image(uiImage: image).resizable().scaledToFit().padding(2) }
                else if model.loading { ProgressView().tint(.white).scaleEffect(0.8) }
                else { Text("Preview unavailable").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
            }
            .frame(width: 208, height: 117).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.black, lineWidth: 2) }
            Text(OfflineSeekPreviewMath.timestamp(model.seconds))
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white).frame(width: 208, height: 24)
                .background(.black.opacity(0.7))
        }
        .frame(width: 208, height: 141).allowsHitTesting(false)
        .accessibilityElement(children: .ignore).accessibilityLabel("Seek preview")
        .accessibilityValue("\(OfflineSeekPreviewMath.timestamp(model.seconds)), \(model.image == nil ? model.loading ? "Loading frame" : "Preview unavailable" : "Video frame")")
        .accessibilityIdentifier("offline-seek-preview")
    }
}
