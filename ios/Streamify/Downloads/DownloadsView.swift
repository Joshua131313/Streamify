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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Take your favorites with you.").font(.title2.bold())
                    Text("Tap Download on a movie or episode to save it here. You can also add a video link or import from Files.").font(.subheadline).foregroundStyle(AppTheme.muted)
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Label("Add link", systemImage: "link").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
                        Button { showImporter = true } label: { Label("Import", systemImage: "folder").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                    }.padding(.top, 8)
                }
                if importing { ProgressView("Importing video…").frame(maxWidth: .infinity).padding() }
                if let error { InlineError(message: error, retry: { self.error = nil; showImporter = true }) }
                if let storageError = downloads.storageError { Text(storageError).font(.caption).foregroundStyle(AppTheme.accent) }
                if downloads.items.isEmpty && !importing {
                    StateMessage(symbol: "arrow.down.circle", title: "Your offline collection", message: "Open a movie or show, then tap Download below Watch. Choose an episode and quality; your saved videos appear here for offline viewing.", actionTitle: "Add video link", action: { showAdd = true })
                }
                ForEach(downloads.items) { item in DownloadRow(item: item, play: { selected = item }) }
                if !completed.isEmpty {
                    Label("\(completed.count) video\(completed.count == 1 ? "" : "s") ready offline", systemImage: "checkmark.circle").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Text("Movie and episode downloads depend on source availability. Streaming-only titles, anime, and live sports cannot be saved for offline viewing.").font(.caption).foregroundStyle(AppTheme.muted)
            }.padding(20).padding(.bottom, 24)
        }.background(AppTheme.canvas)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: play) {
                    HStack(spacing: 12) {
                        thumbnail
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.catalog?.title ?? item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if let catalog = item.catalog, catalog.kind == MediaKind.tv.rawValue {
                                Text("S\(catalog.season) · E\(catalog.episode)" + (catalog.episodeTitle.map { " · \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                            }
                            Text(statusText).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted).lineLimit(2)
                            if item.status == .downloading {
                                if let progress = item.progress {
                                    ProgressView(value: progress).tint(AppTheme.accent)
                                        .accessibilityLabel("Download progress").accessibilityValue("\(Int(progress * 100)) percent")
                                } else { ProgressView().tint(AppTheme.foreground).accessibilityLabel("Downloading. Total size unknown") }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(item.status != .completed)
                    .foregroundStyle(AppTheme.foreground)
                    .accessibilityLabel("Play offline \(item.title)")
                    .accessibilityIdentifier("download-play-\(item.id)")
                Menu {
                    if item.status == .completed { Button("Play offline", systemImage: "play.fill", action: play) }
                    if item.status == .downloading { Button("Cancel download", systemImage: "xmark") { downloads.cancel(id: item.id) } }
                    if item.source != nil && (item.status == .cancelled || item.status == .failed) { Button("Retry download", systemImage: "arrow.clockwise") { downloads.retry(id: item.id) } }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44)
                }.foregroundStyle(AppTheme.foreground).accessibilityLabel("Actions for \(item.title)")
            }
            if let error = item.error { Text(error).font(.caption).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true) }
            if item.source != nil && (item.status == .failed || item.status == .cancelled) {
                Button { downloads.retry(id: item.id) } label: { Label("Retry download", systemImage: "arrow.clockwise").frame(minHeight: 44) }
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.foreground)
            }
        }.padding(.vertical, 10).padding(.horizontal, 10).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("download-card-\(item.id)")
            .accessibilityValue(artwork == nil ? "Artwork unavailable" : "Artwork saved offline")
            .task(id: item.posterFileName) { artwork = item.posterFileURL.flatMap { UIImage(contentsOfFile: $0.path) } }
            .confirmationDialog("Delete \(item.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { downloads.remove(id: item.id) }
            } message: { Text("This removes the saved video from this iPhone.") }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(AppTheme.foreground.opacity(0.06))
            if let artwork { Image(uiImage: artwork).resizable().scaledToFit().accessibilityHidden(true) }
            else {
                VStack(spacing: 5) {
                    Image(systemName: "film").font(.title3)
                    Text(item.catalog == nil ? "VIDEO FILE" : "SAVED VIDEO").font(.system(size: 8, weight: .semibold))
                }.foregroundStyle(AppTheme.muted).accessibilityHidden(true)
            }
            if item.status == .completed {
                Image(systemName: "play.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.65), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }.accessibilityHidden(true)
            }
        }.frame(width: 112, height: 70).clipShape(RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
    }

    private var statusText: String {
        switch item.status {
        case .downloading: return "Downloading\(item.progress.map { " · \(Int($0 * 100))%" } ?? "") · \(byteProgress)"
        case .completed: return "\(item.quality.map { "\($0)p · " } ?? "")\(ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file)) · Downloaded"
        case .cancelled: return "Cancelled"
        case .failed: return "Download unavailable"
        }
    }
    private var byteProgress: String {
        let current = ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file)
        return item.expectedBytes > 0 ? "\(current) of \(ByteCountFormatter.string(fromByteCount: item.expectedBytes, countStyle: .file))" : current
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
