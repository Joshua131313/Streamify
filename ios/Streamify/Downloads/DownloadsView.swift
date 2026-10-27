import SwiftUI
import UIKit
import AVKit
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var selected: DownloadItem?
    @State private var selectedSeries: DownloadSeriesGroup?
    @State private var showSeries = false
    @State private var error: String?
    @State private var importing = false
    private var completed: [DownloadItem] { downloads.items.filter { $0.status == .completed } }

    var body: some View {
        List {
            Section {
                Text("On this device · \(completed.count) ready to watch")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                if importing {
                    ProgressView("Importing video…").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                }
                if let error {
                    InlineError(message: error, retry: { self.error = nil; showImporter = true })
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                }
                if let storageError = downloads.storageError {
                    Text(storageError).font(.caption).foregroundStyle(AppTheme.accent)
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                }
                if downloads.items.isEmpty && !importing {
                    StateMessage(symbol: "arrow.down.circle", title: "Your offline collection", message: "Open a movie or show, then tap Download below Watch. Choose an episode and quality; your saved videos appear here for offline viewing.", actionTitle: "Add video link", action: { showAdd = true })
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                }
                ForEach(DownloadLibraryGrouping.entries(in: downloads.items)) { entry in
                    Group {
                        switch entry {
                        case .video(let item):
                            DownloadRow(item: item, play: { selected = item })
                        case .series(let series):
                            DownloadSeriesRow(series: series) { selectedSeries = series; showSeries = true }
                        }
                    }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Take your favorites with you.").font(.subheadline.weight(.semibold))
                    Text("Tap Download on a movie or episode to save it here. You can also add a video link or import from Files.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Label("Add link", systemImage: "link").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                        Button { showImporter = true } label: { Label("Import", systemImage: "folder").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                    }
                }.padding(.top, 12)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
            }
        }.listStyle(.plain).listSectionSpacing(8)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden).background(AppTheme.canvas)
            .accessibilityIdentifier("downloads-list")
            .task { downloads.refreshArtwork(token: settings.tmdbToken) }
            .navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(isPresented: $showSeries) {
                if let selectedSeries { DownloadSeriesView(seriesID: selectedSeries.id, initialTitle: selectedSeries.title) }
            }
            .sheet(isPresented: $showAdd) { NavigationStack { AddDownloadView() } }
            .fullScreenCover(item: $selected) { item in OfflineVideoView(item: item) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    importing = true
                    Task {
                        defer { importing = false }
                        do { try await downloads.importFile(url: url); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                } catch { self.error = error.localizedDescription }
            }
    }
}

private struct DownloadSeriesRow: View {
    let series: DownloadSeriesGroup
    let open: () -> Void
    @EnvironmentObject private var downloads: DownloadStore
    @State private var artwork: UIImage?
    @State private var confirmDelete = false
    @State private var deletionIDs: [UUID] = []

    private var episodeCount: String { "\(series.episodes.count) episode\(series.episodes.count == 1 ? "" : "s")" }
    private var summary: String {
        let size = ByteCountFormatter.string(fromByteCount: series.bytesWritten, countStyle: .file)
        return "\(episodeCount) · " + (series.readyCount == series.episodes.count ? size : "\(series.readyCount)/\(series.episodes.count) ready · \(size)")
    }
    private var artworkKey: String { series.episodes.map { "\($0.id):\($0.posterFileName ?? "")" }.joined(separator: "|") }

    var body: some View {
        Button { AppHaptics.tap(); open() } label: { rowLabel }
            .buttonStyle(CardPressedButtonStyle(cornerRadius: 6, preservesContextMenuSource: true))
            .foregroundStyle(AppTheme.foreground)
            .accessibilityLabel("\(series.title), \(summary), View episodes")
            .accessibilityValue(series.active.isEmpty ? "" : series.progress.map { "\(Int($0 * 100)) percent" } ?? "Downloading. Total size unknown")
            .accessibilityIdentifier("download-series-\(series.id)")
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6))
            .contextMenu {
                Button("View episodes", systemImage: "rectangle.stack", action: open)
                if !series.active.isEmpty { Button("Cancel downloads", systemImage: "stop.fill") { cancelActive() } }
                if !series.retryable.isEmpty { Button("Retry downloads", systemImage: "arrow.clockwise") { retryFailed() } }
                Button("Delete downloads", systemImage: "trash", role: .destructive, action: requestDelete)
            } preview: {
                rowLabel.frame(width: 294).padding(12)
                    .foregroundStyle(AppTheme.foreground)
                    .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: requestDelete) { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.automatic).tint(Color(white: 0.24))
                    .accessibilityIdentifier("download-series-swipe-delete-\(series.id)")
                if !series.active.isEmpty {
                    Button(action: cancelActive) { Label("Cancel downloads", systemImage: "stop.fill") }
                        .buttonStyle(.automatic).tint(Color(white: 0.34))
                } else if !series.retryable.isEmpty {
                    Button(action: retryFailed) { Label("Retry", systemImage: "arrow.clockwise") }
                        .buttonStyle(.automatic).tint(Color(white: 0.34))
                }
            }
            .task(id: artworkKey) {
                artwork = series.episodes.lazy.compactMap { $0.posterFileURL.flatMap { UIImage(contentsOfFile: $0.path) } }.first
            }
            .confirmationDialog("Delete \(deletionIDs.count) episode download\(deletionIDs.count == 1 ? "" : "s") for \(series.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete \(deletionIDs.count) episode\(deletionIDs.count == 1 ? "" : "s")", role: .destructive) {
                    // These records were captured when confirmation opened;
                    // a new episode added while it is open is not deleted.
                    for id in deletionIDs {
                        downloads.remove(id: id)
                        // Preserve the store's real file-removal error instead
                        // of clearing it with a later successful deletion.
                        if downloads.items.contains(where: { $0.id == id }) { break }
                    }
                }.accessibilityIdentifier("download-series-confirm-delete-\(series.id)")
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes these episode downloads from this iPhone.") }
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(AppTheme.foreground.opacity(0.06))
                if let artwork { Image(uiImage: artwork).resizable().scaledToFit() }
                else { Image(systemName: "tv").font(.title3).foregroundStyle(AppTheme.muted) }
            }.frame(width: 112, height: 70).clipShape(RoundedRectangle(cornerRadius: 4)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(series.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(summary).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !series.active.isEmpty {
                DownloadActivityIndicator(progress: series.progress, size: 26, animated: false)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
        }.frame(minHeight: 70).contentShape(Rectangle())
    }

    private func requestDelete() { deletionIDs = series.episodes.map(\.id); confirmDelete = true }
    private func cancelActive() { series.active.forEach { downloads.cancel(id: $0.id) } }
    private func retryFailed() { series.retryable.forEach { downloads.retry(id: $0.id) } }
}

private struct DownloadSeriesView: View {
    let seriesID: Int
    let initialTitle: String
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DownloadItem?
    private var series: DownloadSeriesGroup? { DownloadLibraryGrouping.series(id: seriesID, in: downloads.items) }

    var body: some View {
        List {
            if let series {
                Section {
                    Text("On this device · \(series.readyCount) of \(series.episodes.count) episodes ready to watch")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                    if let error = downloads.storageError {
                        Text(error).font(.caption).foregroundStyle(AppTheme.accent)
                            .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                    }
                }
                ForEach(series.seasons, id: \.self) { season in
                    Section("Season \(season)") {
                        ForEach(series.episodes.filter { max(1, $0.catalog?.season ?? 1) == season }) { item in
                            DownloadRow(item: item, episodePage: true, play: { selected = item })
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                        }
                    }
                }
                Section {
                    MediaDetailLink(media: MediaItem(id: series.id, kind: .tv, title: series.title)) {
                        Text("View more episodes").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(AppTheme.canvas)
                            .background(AppTheme.foreground, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                    }.accessibilityIdentifier("download-series-more-\(seriesID)")
                        .listRowInsets(EdgeInsets(top: 16, leading: 36, bottom: 20, trailing: 36))
                        .listRowBackground(AppTheme.canvas).listRowSeparator(.hidden)
                }
            }
        }.listStyle(.plain).listSectionSpacing(12)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden).background(AppTheme.canvas)
            .navigationTitle(series?.title ?? initialTitle).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("download-series-page-\(seriesID)")
            .fullScreenCover(item: $selected) { item in OfflineVideoView(item: item) }
            .onChange(of: series == nil) { _, empty in if empty { dismiss() } }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    var episodePage = false
    let play: () -> Void
    @EnvironmentObject private var downloads: DownloadStore
    @State private var confirmDelete = false
    @State private var artwork: UIImage?
    @State private var showQuality = false

    var body: some View {
        withTransferContextMenu(row)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Keep native swipe rendering even with the app's haptic button
                // style. Deletion stays a confirmed action, not an optimistic row removal.
                Button { AppHaptics.tap(); confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.automatic).tint(Color(white: 0.24))
                    .accessibilityIdentifier("download-swipe-delete-\(item.id)")
                if item.status == .downloading {
                    Button { AppHaptics.tap(); downloads.cancel(id: item.id) } label: { Label("Cancel download", systemImage: "stop.fill") }
                        .buttonStyle(.automatic).tint(Color(white: 0.34))
                        .accessibilityIdentifier("download-swipe-cancel-\(item.id)")
                } else if canRetry {
                    Button { AppHaptics.tap(); downloads.retry(id: item.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }
                        .buttonStyle(.automatic).tint(Color(white: 0.34))
                        .accessibilityIdentifier("download-swipe-retry-\(item.id)")
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("download-card-\(item.id)")
            .accessibilityValue(artwork == nil ? "Artwork unavailable" : "Artwork saved offline")
            .task(id: item.posterFileName) { artwork = item.posterFileURL.flatMap { UIImage(contentsOfFile: $0.path) } }
            .confirmationDialog("Delete \(item.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { downloads.remove(id: item.id) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the saved video from this iPhone.") }
            .sheet(isPresented: $showQuality) {
                if let catalog = item.catalog, let media = catalog.media {
                    NavigationStack {
                        MediaDownloadSheet(media: media, season: catalog.season, episode: catalog.episode,
                            episodeTitle: catalog.episodeTitle, replacingDownloadID: item.id, previousError: item.error)
                    }
                }
            }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                primaryButton
                trailingControl
            }
            if let error = item.error {
                Text(error).font(.caption).foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 124)
            }
        }.contentShape(Rectangle())
    }

    @ViewBuilder private var primaryButton: some View {
        if item.status == .completed {
            // One native control owns the tap and menu recognizers. A SwiftUI
            // Menu with a primaryAction inside this List row fired playback on
            // release of a hold instead of presenting its actions on iOS26.
            primaryLabel
                .foregroundStyle(AppTheme.foreground)
                .accessibilityHidden(true)
                .overlay {
                    DownloadPrimaryActionsControl(
                        title: item.title, identifier: "download-play-\(item.id)",
                        play: play,
                        chooseQuality: item.catalog?.media == nil ? nil : { showQuality = true },
                        delete: { confirmDelete = true })
                }
        } else {
            Button {} label: { primaryLabel }
                .buttonStyle(CardPressedButtonStyle(cornerRadius: 6))
                .disabled(true)
                .foregroundStyle(AppTheme.foreground)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("download-play-\(item.id)")
        }
    }

    private var primaryLabel: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(rowTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !episodePage, let catalog = item.catalog, catalog.kind == MediaKind.tv.rawValue {
                    Text("S\(catalog.season) · E\(catalog.episode)" + (catalog.episodeTitle.map { " · \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                }
                if let metadata = metadataText {
                    Text(metadata).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted).lineLimit(1)
                        .accessibilityIdentifier("download-progress-\(item.id)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 70).contentShape(Rectangle())
    }

    private var contextPreview: some View {
        primaryLabel.frame(width: 294).padding(12)
            .foregroundStyle(AppTheme.foreground)
            .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func withTransferContextMenu<Content: View>(_ content: Content) -> some View {
        // Disabled transfers need a row context menu. Completed rows use their
        // native primary-action control without an ancestor context menu.
        if item.status == .completed { content }
        else {
            content.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6))
                .contextMenu { downloadActions } preview: { contextPreview }
        }
    }

    private var rowTitle: String {
        guard episodePage, let catalog = item.catalog else { return item.catalog?.title ?? item.title }
        let name = catalog.episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "S\(catalog.season) E\(catalog.episode)" + (name.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? "")
    }

    @ViewBuilder private var trailingControl: some View {
        if item.status == .downloading {
            Button { downloads.cancel(id: item.id) } label: {
                ZStack {
                    DownloadActivityIndicator(progress: item.progress, size: 26, animated: false)
                    Image(systemName: "stop.fill").font(.system(size: 10))
                }.frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.foreground)
                .accessibilityLabel("Cancel download of \(item.title)")
                .accessibilityValue(item.progress.map { "\(Int($0 * 100)) percent" } ?? "Downloading. Total size unknown")
                .accessibilityIdentifier("download-activity-\(item.id)")
        } else {
            Menu { downloadActions } label: {
                Image(systemName: item.status == .completed ? "checkmark.circle" : "ellipsis")
                    .font(.system(size: item.status == .completed ? 23 : 19))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.foregroundStyle(AppTheme.foreground).accessibilityLabel("Actions for \(item.title)")
                .accessibilityValue(item.status == .completed ? "Downloaded" : item.status == .failed ? "Download unavailable" : "Cancelled")
                .accessibilityIdentifier("download-actions-\(item.id)")
        }
    }

    private var canRetry: Bool { item.source != nil && (item.status == .cancelled || item.status == .failed) }

    @ViewBuilder private var downloadActions: some View {
        if item.status == .completed { Button("Play offline", systemImage: "play.fill", action: play) }
        if item.status == .downloading { Button("Cancel download", systemImage: "xmark") { downloads.cancel(id: item.id) } }
        if canRetry { Button("Retry download", systemImage: "arrow.clockwise") { downloads.retry(id: item.id) } }
        if item.status != .downloading, item.catalog?.media != nil {
            Button("Choose quality", systemImage: "slider.horizontal.3") { showQuality = true }
                .accessibilityIdentifier("download-choose-quality-\(item.id)")
        }
        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(AppTheme.foreground.opacity(0.06))
            if let artwork { Image(uiImage: artwork).resizable().scaledToFit().accessibilityHidden(true) }
            else { Image(systemName: "film").font(.title3).foregroundStyle(AppTheme.muted).accessibilityHidden(true) }
            if item.status == .completed {
                Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.65), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }.accessibilityHidden(true)
            }
        }.frame(width: 112, height: 70).clipShape(RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
    }

    private var metadataText: String? {
        switch item.status {
        // The ring carries live progress; repeating a changing percentage or
        // transfer message beneath the title makes these compact rows noisy.
        case .downloading: return item.quality.map { "\($0)p" }
        case .completed: return "\(item.quality.map { "\($0)p · " } ?? "")\(ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file))"
        case .cancelled: return "Cancelled"
        case .failed: return "Download unavailable"
        }
    }
}

/// Keep the system's primary-action/menu distinction in one UIButton. The
/// transparent native surface covers the existing SwiftUI artwork and title;
/// it neither introduces a second row button nor intercepts List swipe actions.
private struct DownloadPrimaryActionsControl: UIViewRepresentable {
    let title: String
    let identifier: String
    let play: () -> Void
    let chooseQuality: (() -> Void)?
    let delete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let coordinator = context.coordinator
        let primary = UIAction { [weak coordinator] _ in coordinator?.activate() }
        let button = UIButton(type: .custom, primaryAction: primary)
        button.showsMenuAsPrimaryAction = false
        button.isAccessibilityElement = true
        button.isPointerInteractionEnabled = true
        button.layer.cornerRadius = 6
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.control = self
        button.accessibilityLabel = "Play offline \(title)"
        button.accessibilityIdentifier = identifier
        button.accessibilityHint = "Touch and hold for download actions."
        var actions: [UIMenuElement] = [
            UIAction(title: "Play offline", image: UIImage(systemName: "play.fill")) { [weak coordinator] _ in
                coordinator?.activate()
            }
        ]
        if chooseQuality != nil {
            actions.append(UIAction(title: "Choose quality", image: UIImage(systemName: "slider.horizontal.3")) { [weak coordinator] _ in
                AppHaptics.tap()
                coordinator?.control.chooseQuality?()
            })
        }
        actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak coordinator] _ in
            AppHaptics.tap()
            coordinator?.control.delete()
        })
        button.menu = UIMenu(children: actions)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 70)
    }

    final class Coordinator {
        var control: DownloadPrimaryActionsControl
        init(_ control: DownloadPrimaryActionsControl) { self.control = control }
        func activate() {
            AppHaptics.tap()
            control.play()
        }
    }
}

private struct AddDownloadView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var title = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Video") {
                TextField("Title (optional)", text: $title)
                TextField("https://example.com/video.mp4", text: $address, axis: .vertical)
                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }.listRowBackground(AppTheme.panel)
            Section {
                Text("Use a direct HTTPS link to an MP4, M4V, or MOV file. Downloads can continue in the background; iOS manages when transfers run.").font(.footnote).foregroundStyle(AppTheme.muted)
            }.listRowBackground(AppTheme.panel)
            if let error { Section { Text(error).foregroundStyle(AppTheme.accent) } }
            Section {
                Button {
                    do { try downloads.add(url: address, title: title); dismiss() }
                    catch { self.error = error.localizedDescription }
                } label: { Label("Start download", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity, minHeight: 32) }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.scrollContentBackground(.hidden).background(AppTheme.canvas)
            .navigationTitle("Add video").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

private struct OfflineVideoView: View {
    let item: DownloadItem
    var body: some View {
        OfflinePlayerView(item: item)
    }
}
