import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var selected: DownloadItem?
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
                ForEach(downloads.items) { item in
                    DownloadRow(item: item, play: { selected = item })
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
            } footer: {
                Text("Movie and episode downloads depend on source availability. Streaming-only titles, anime, and live sports cannot be saved for offline viewing.")
                    .font(.caption).foregroundStyle(AppTheme.muted).padding(.bottom, 16)
            }
        }.listStyle(.plain).listSectionSpacing(8)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden).background(AppTheme.canvas)
            .accessibilityIdentifier("downloads-list")
            .task { downloads.refreshArtwork(token: settings.tmdbToken) }
            .navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
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

private struct DownloadRow: View {
    let item: DownloadItem
    let play: () -> Void
    @EnvironmentObject private var downloads: DownloadStore
    @State private var confirmDelete = false
    @State private var artwork: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: play) {
                    HStack(spacing: 12) {
                        thumbnail
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.catalog?.title ?? item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if let catalog = item.catalog, catalog.kind == MediaKind.tv.rawValue {
                                Text("S\(catalog.season) · E\(catalog.episode)" + (catalog.episodeTitle.map { " · \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                            }
                            if let metadata = metadataText {
                                Text(metadata).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted).lineLimit(1)
                                    .accessibilityIdentifier("download-progress-\(item.id)")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 70).contentShape(Rectangle())
                }.buttonStyle(HapticCardButtonStyle(cornerRadius: 6)).disabled(item.status != .completed)
                    .foregroundStyle(AppTheme.foreground)
                    .accessibilityLabel(item.status == .completed ? "Play offline \(item.title)" : item.title)
                    .accessibilityIdentifier("download-play-\(item.id)")
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6))
                    .contextMenu {
                        // The same native control owns its tap and its hold, so
                        // opening the menu cancels the completed file's play tap.
                        if item.status == .completed { downloadActions }
                    }
                trailingControl
            }
            if let error = item.error {
                Text(error).font(.caption).foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 124)
            }
        }.contentShape(Rectangle())
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6))
            .contextMenu {
                // Disabled transfer buttons cannot own their own context menu.
                if item.status != .completed { downloadActions }
            }
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
