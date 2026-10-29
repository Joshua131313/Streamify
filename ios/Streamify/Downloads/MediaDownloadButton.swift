import SwiftUI

/// The same movie/episode action is shared by details and the player.
struct MediaDownloadButton: View {
    let media: MediaItem
    var season: Int = 1
    var episode: Int = 1
    var episodeTitle: String? = nil
    var compact = false
    var onPresentationChanged: ((Bool) -> Void)? = nil
    var onRequestDownload: (() -> Void)? = nil
    @EnvironmentObject private var downloads: DownloadStore
    @State private var showOptions = false
    @State private var showDownloads = false

    private var item: DownloadItem? { downloads.item(media: media, season: season, episode: episode) }
    private var iconOnly: Bool { compact || item?.status == .downloading }
    private var label: String {
        switch item?.status {
        case .completed: return "Downloaded"
        case .downloading: return "Downloading"
        case .failed: return "Retry download"
        case .cancelled: return "Download again"
        case nil: return media.kind == .tv ? "Download S\(season) E\(episode)" : "Download"
        }
    }
    private var symbol: String {
        switch item?.status {
        case .completed: return "checkmark.circle"
        case .failed, .cancelled: return "arrow.clockwise"
        default: return "arrow.down.circle"
        }
    }

    var body: some View {
        if media.kind != .anime {
            Button {
                if let onRequestDownload { onRequestDownload(); return }
                if item?.status == .downloading || item?.status == .completed { showDownloads = true }
                else { showOptions = true }
            } label: {
                HStack(spacing: 10) {
                    if item?.status == .downloading {
                        ZStack {
                            DownloadActivityIndicator(progress: item?.progress, size: 26, animated: false)
                            // This action opens Downloads, so retain a download
                            // arrow instead of suggesting that tapping cancels.
                            Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
                        }.accessibilityHidden(true)
                    }
                    else { Image(systemName: symbol).font(compact ? .title3 : .body) }
                    if !iconOnly { Text(label).lineLimit(2).multilineTextAlignment(.center) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.foreground)
                .frame(maxWidth: iconOnly ? nil : .infinity, minHeight: iconOnly ? 44 : 50)
                .frame(width: iconOnly ? 44 : nil)
                .background(iconOnly ? Color.clear : AppTheme.controlFill, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                .overlay { RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius).strokeBorder(iconOnly ? Color.clear : AppTheme.border, lineWidth: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityLabel(compact ? "\(label) · Episode \(episode)" : label)
            .accessibilityValue(item?.status == .downloading
                ? item?.progress.map { "\(Int($0 * 100)) percent" } ?? "Downloading. Total size unknown"
                : "")
            .accessibilityIdentifier("download-\(DownloadStore.catalogKey(media: media, season: season, episode: episode))")
            .sheet(isPresented: $showOptions) {
                NavigationStack {
                    MediaDownloadSheet(media: media, season: season, episode: episode, episodeTitle: episodeTitle,
                        previousError: item?.status == .failed ? item?.error : nil)
                }
            }
            .sheet(isPresented: $showDownloads) { NavigationStack { DownloadsView() } }
            .onChange(of: showOptions || showDownloads) { _, visible in onPresentationChanged?(visible) }
        }
    }
}

struct MediaDownloadSheet: View {
    let media: MediaItem
    let season: Int
    let episode: Int
    let episodeTitle: String?
    /// Explicit recovery keeps the previous file until its replacement is verified.
    var replacingDownloadID: UUID? = nil
    var previousError: String? = nil
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("streamify.ios.downloadQuality") private var quality = 1080
    @State private var resolving = false
    @State private var added = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private let qualities = [1080, 720, 480, 360]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteArtwork(url: media.posterURL).frame(width: 68, height: 102)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(media.title).font(.title3.bold())
                        Text(media.kind == .tv ? "Season \(season) · Episode \(episode)" : "Movie")
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                        if let episodeTitle, !episodeTitle.isEmpty { Text(episodeTitle).font(.caption).foregroundStyle(AppTheme.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if added {
                    Label("Added to downloads", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(AppTheme.foreground)
                    Text("Your video is downloading. You can follow its progress and play it offline in Downloads.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                    NavigationLink { DownloadsView() } label: { Label("View downloads", systemImage: "arrow.down.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("view-downloads")
                } else {
                    if let previousError, !previousError.isEmpty, error == nil, !resolving {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Last download couldn’t finish", systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold))
                            Text(previousError).font(.caption).foregroundStyle(AppTheme.muted)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("download-previous-error")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Download quality").font(.headline)
                        ForEach(qualities, id: \.self) { value in
                            Button { quality = value } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(String(value))p").font(.subheadline.weight(.semibold))
                                        Text(value == 1080 ? "Best quality" : "Smaller download").font(.caption).foregroundStyle(AppTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: quality == value ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(quality == value ? AppTheme.foreground : AppTheme.muted)
                                }.padding(14).streamifyControlSurface()
                            }.buttonStyle(HapticPlainButtonStyle()).disabled(resolving)
                                .accessibilityLabel("\(String(value))p download quality")
                                .accessibilityAddTraits(quality == value ? .isSelected : [])
                        }
                        Text("Downloads the resolution you choose. If that quality is unavailable or incompatible, choose another resolution. Some titles are available for streaming only.")
                            .font(.footnote).foregroundStyle(AppTheme.muted)
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(AppTheme.accent).accessibilityIdentifier("download-error") }
                    Button(action: start) {
                        HStack(spacing: 10) {
                            if resolving { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.down.circle.fill") }
                            Text(resolving ? "Finding download…" : "Start download")
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(resolving).accessibilityIdentifier("start-media-download")
                }
            }.padding(20).streamifyReadableWidth()
        }
        .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
        .navigationTitle("Download").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear { if !qualities.contains(quality) { quality = 1080 } }
        .onDisappear { task?.cancel() }
    }

    private func start() {
        guard !resolving else { return }
        resolving = true; error = nil
        task = Task { @MainActor in
            defer { resolving = false }
            do {
                let source = try await CatalogDownloadResolver().resolve(media: media, season: season, episode: episode, maximumQuality: quality)
                try Task.checkCancellation()
                try downloads.add(resolved: source, media: media, season: season, episode: episode,
                    episodeTitle: episodeTitle, replacingDownloadID: replacingDownloadID)
                added = true
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
