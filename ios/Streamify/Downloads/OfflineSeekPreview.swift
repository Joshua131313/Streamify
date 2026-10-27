import SwiftUI
import AVFoundation
import Combine

enum OfflineSeekPreviewMath {
    static let imageSize = CGSize(width: 208, height: 117)
    static let timestampHeight: CGFloat = 24
    static let bottomInset: CGFloat = 100
    static let thumbGap: CGFloat = 8
    static let size = CGSize(width: imageSize.width, height: imageSize.height + timestampHeight)

    static func second(position: Double, duration: Double) -> Int? {
        guard position.isFinite, duration.isFinite, duration > 0 else { return nil }
        let bounded = min(max(0, position), max(0, duration - 0.05)).rounded(.down)
        return Int(exactly: bounded)
    }
    static func center(thumbX: CGFloat, viewportWidth: CGFloat, previewWidth: CGFloat = size.width) -> CGFloat {
        guard thumbX.isFinite, viewportWidth.isFinite, previewWidth.isFinite,
              viewportWidth > 0, previewWidth > 0 else { return 0 }
        guard viewportWidth >= previewWidth else { return viewportWidth / 2 }
        return min(viewportWidth - previewWidth / 2, max(previewWidth / 2, thumbX))
    }
    /// UIKit reports the live thumb in window coordinates. Android follows that
    /// horizontal anchor and prefers Android's 100dp canvas-bottom inset. iOS's
    /// higher timeline needs a guard so the timestamp cannot cover its live thumb.
    static func position(thumbInWindow: CGRect, viewportInWindow: CGRect, bottomSafeAreaInset: CGFloat = 0) -> CGPoint {
        guard thumbInWindow.midX.isFinite, thumbInWindow.minY.isFinite,
              viewportInWindow.minX.isFinite, viewportInWindow.minY.isFinite,
              viewportInWindow.width.isFinite, viewportInWindow.height.isFinite,
              bottomSafeAreaInset.isFinite,
              viewportInWindow.width > 0, viewportInWindow.height > 0 else { return .zero }
        let preferredBottom = viewportInWindow.height + max(0, bottomSafeAreaInset) - bottomInset
        let aboveThumb = thumbInWindow.minY - viewportInWindow.minY - thumbGap
        return CGPoint(
            x: center(thumbX: thumbInWindow.midX - viewportInWindow.minX,
                viewportWidth: viewportInWindow.width),
            // A compact window can have less room than Android's bottom inset.
            // Keep the thumbnail below the viewport's safe top in that case.
            y: max(size.height / 2, min(preferredBottom, aboveThumb) - size.height / 2))
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
    var packageDecoder: OfflineHLSSeekFrameDecoder?
    var ownsAsset = false
    func cancel() { generator?.cancelAllCGImageGeneration(); packageDecoder?.cancel() }
    func clear() {
        cancel(); packageDecoder?.close()
        if ownsAsset { asset?.cancelLoading() }
        generator = nil; packageDecoder = nil; asset = nil; ownsAsset = false
    }
    deinit { clear() }
}

/// Conflates thumb updates: one local-frame decode runs at a time, and only the
/// latest requested second may appear. Twelve 320x180 frames bound memory use.
@MainActor
final class OfflineSeekPreviewModel: ObservableObject {
    typealias FrameLoader = (AVAssetImageGenerator, CMTime) async throws -> CGImage
    typealias PackageFrameLoader = (AVURLAsset, CMTime) async throws -> CGImage
    @Published private(set) var image: UIImage?
    @Published private(set) var visible = false
    @Published private(set) var loading = false
    @Published private(set) var seconds: Double = 0
    private let resources = OfflineSeekPreviewResources()
    private let frameLoader: FrameLoader
    private let packageFrameLoader: PackageFrameLoader?
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
    }) { self.frameLoader = frameLoader; packageFrameLoader = nil }

    /// Separate overload preserves the existing MP4 trailing-closure injection.
    init(frameLoader: @escaping FrameLoader, packageFrameLoader: @escaping PackageFrameLoader) {
        self.frameLoader = frameLoader; self.packageFrameLoader = packageFrameLoader
    }

    func show(url: URL, seconds: Double, duration: Double) {
        show(asset: AVURLAsset(url: url), ownsAsset: true, seconds: seconds, duration: duration)
    }

    /// The real player passes its validated local asset. In particular, preserve
    /// the system-owned package URL/access context and its loaded cache metadata.
    func show(asset: AVURLAsset, seconds: Double, duration: Double) {
        show(asset: asset, ownsAsset: false, seconds: seconds, duration: duration)
    }

    private func show(asset: AVURLAsset, ownsAsset: Bool, seconds: Double, duration: Double) {
        let url = asset.url
        guard url.isFileURL, let second = OfflineSeekPreviewMath.second(position: seconds, duration: duration) else { hide(); return }
        if source != url {
            close(); source = url
            resources.asset = asset; resources.ownsAsset = ownsAsset
            if url.pathExtension.lowercased() == "movpkg" {
                resources.packageDecoder = try? OfflineHLSSeekFrameDecoder(asset: asset)
            } else {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.maximumSize = CGSize(width: 320, height: 180)
                generator.appliesPreferredTrackTransform = true
                // Retain the existing MP4 sync-frame path and injection.
                resources.generator = generator
            }
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
        guard worker == nil, let asset = resources.asset else { return }
        let request = generation, load = frameLoader, loadPackage = packageFrameLoader
        let generator = resources.generator, decoder = resources.packageDecoder
        let package = asset.url.pathExtension.lowercased() == "movpkg"
        worker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == request, let second = self.pending else { break }
                self.pending = nil; self.decoding = second
                do {
                    let time = CMTime(seconds: Double(second), preferredTimescale: 600)
                    let frame: CGImage
                    if package {
                        if let loadPackage { frame = try await loadPackage(asset, time) }
                        else if let decoder { frame = try await decoder.image(at: time) }
                        else { throw OfflineHLSSeekFrameDecoder.Failure.unavailableLocalPackage }
                    } else if let generator { frame = try await load(generator, time) }
                    else { throw OfflineHLSSeekFrameDecoder.Failure.frameUnavailable }
                    guard !Task.isCancelled, self.generation == request else { return }
                    let picture = UIImage(cgImage: frame)
                    self.frames[second] = picture; self.touchCache(second)
                    if self.visible, self.latest == second { self.image = picture; self.loading = false }
                } catch {
                    guard !Task.isCancelled, self.generation == request else { return }
                    // A native package decoder can be interrupted while its
                    // local seek warms up. Do not permanently black-list that
                    // second; a later thumb update may retry it.
                    if !package { self.unavailable.insert(second) }
                    self.touchCache(second)
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

/// Android's fit-center frame and separate, unbacked timestamp. Its image alone
/// has a 6pt radius and black 2pt padding/border; the preview has no shadow.
struct OfflineSeekPreviewBubble: View {
    @ObservedObject var model: OfflineSeekPreviewModel
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let image = model.image { Image(uiImage: image).resizable().scaledToFit().padding(2) }
            }
            .frame(width: OfflineSeekPreviewMath.imageSize.width, height: OfflineSeekPreviewMath.imageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .circular).strokeBorder(.black, lineWidth: 2) }
            Text(OfflineSeekPreviewMath.timestamp(model.seconds))
                .font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: OfflineSeekPreviewMath.size.width, height: OfflineSeekPreviewMath.timestampHeight)
        }
        .frame(width: OfflineSeekPreviewMath.size.width, height: OfflineSeekPreviewMath.size.height).allowsHitTesting(false)
        .accessibilityElement(children: .ignore).accessibilityLabel("Seek preview")
        .accessibilityValue("\(OfflineSeekPreviewMath.timestamp(model.seconds)), \(model.image == nil ? model.loading ? "Loading frame" : "Preview unavailable" : "Video frame")")
        .accessibilityIdentifier("offline-seek-preview")
    }
}
