import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
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
                    Text("Save a direct video link or import a video from Files to watch offline.").font(.subheadline).foregroundStyle(AppTheme.muted)
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Label("Add link", systemImage: "link").frame(maxWidth: .infinity, minHeight: 32) }.buttonStyle(.borderedProminent).tint(AppTheme.accent)
                        Button { showImporter = true } label: { Label("Import", systemImage: "folder").frame(maxWidth: .infinity, minHeight: 32) }.buttonStyle(.bordered)
                    }.padding(.top, 8)
                }
                if importing { ProgressView("Importing video…").frame(maxWidth: .infinity).padding() }
                if let error { InlineError(message: error, retry: { self.error = nil; showImporter = true }) }
                if let storageError = downloads.storageError { Text(storageError).font(.caption).foregroundStyle(AppTheme.accent) }
                if downloads.items.isEmpty && !importing {
                    StateMessage(symbol: "arrow.down.circle", title: "Your offline collection", message: "Add a direct HTTPS MP4, M4V, or MOV link, or import a video from Files. Saved videos appear here and play without an internet connection.", actionTitle: "Add video link", action: { showAdd = true })
                }
                ForEach(downloads.items) { item in DownloadRow(item: item, play: { selected = item }) }
                if !completed.isEmpty {
                    Label("\(completed.count) video\(completed.count == 1 ? "" : "s") ready offline", systemImage: "checkmark.circle").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Text("Downloads support direct video files. Embedded movie and sports providers do not expose downloadable files.").font(.caption).foregroundStyle(AppTheme.muted)
            }.padding(20).padding(.bottom, 24)
        }.background(AppTheme.canvas)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: item.status == .completed ? "play.rectangle.fill" : "arrow.down.circle")
                    .font(.title2).foregroundStyle(item.status == .completed ? AppTheme.accent : AppTheme.muted)
                    .frame(width: 48, height: 58).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                    Text(statusText).font(.caption).foregroundStyle(AppTheme.muted)
                    if let error = item.error { Text(error).font(.caption).foregroundStyle(AppTheme.accent).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    if item.status == .completed { Button("Play", systemImage: "play", action: play) }
                    if item.status == .downloading { Button("Cancel download", systemImage: "xmark") { downloads.cancel(id: item.id) } }
                    if item.source != nil && (item.status == .cancelled || item.status == .failed) { Button("Retry download", systemImage: "arrow.clockwise") { downloads.retry(id: item.id) } }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Actions for \(item.title)")
            }
            if item.status == .downloading {
                if let progress = item.progress { ProgressView(value: progress).tint(AppTheme.accent).accessibilityLabel("Download progress").accessibilityValue("\(Int(progress * 100)) percent") }
                else { ProgressView().tint(AppTheme.accent).accessibilityLabel("Downloading. Total size unknown") }
                HStack {
                    Text(byteProgress).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.muted)
                    Spacer()
                    Button("Cancel") { downloads.cancel(id: item.id) }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            }
            if item.status == .completed {
                Button(action: play) { Label("Play offline", systemImage: "play.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 32) }.buttonStyle(.bordered).tint(AppTheme.accent)
            } else if item.source != nil && (item.status == .failed || item.status == .cancelled) {
                Button { downloads.retry(id: item.id) } label: { Label("Retry", systemImage: "arrow.clockwise").frame(minHeight: 30) }.buttonStyle(.bordered).tint(AppTheme.accent)
            }
        }.padding(17).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .confirmationDialog("Delete \(item.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { downloads.remove(id: item.id) }
            } message: { Text("This removes the saved video from this iPhone.") }
    }

    private var statusText: String {
        switch item.status {
        case .downloading: return "Downloading\(item.progress.map { " · \(Int($0 * 100))%" } ?? "")"
        case .completed: return "Ready offline · \(ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file))"
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
            }
            Section {
                Text("Use a direct HTTPS link to an MP4, M4V, or MOV file. Downloads can continue in the background; iOS manages when transfers run.").font(.footnote).foregroundStyle(AppTheme.muted)
            }
            if let error { Section { Text(error).foregroundStyle(AppTheme.accent) } }
            Section {
                Button {
                    do { try downloads.add(url: address, title: title); dismiss() }
                    catch { self.error = error.localizedDescription }
                } label: { Label("Start download", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity, minHeight: 32) }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.navigationTitle("Add video").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

private struct OfflineVideoView: View {
    let item: DownloadItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close video")
                Text(item.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 8)
            if let error { StateMessage(symbol: "exclamationmark.circle", title: "Video unavailable", message: error).padding() }
            else { VideoPlayer(player: player) }
        }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
            .task {
                guard let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) else { error = "The local video is missing. Download or import it again."; return }
                let asset = AVURLAsset(url: url)
                do {
                    guard try await asset.load(.isPlayable) else { error = "This video format cannot be played on this iPhone."; return }
                    try PlaybackAudioSession.activate()
                    let created = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                    player = created
                    created.play()
                } catch { self.error = error.localizedDescription }
            }
            .onDisappear { player?.pause(); player = nil }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
    }
}
