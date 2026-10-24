import SwiftUI
import AVKit
import MediaPlayer
import Combine
import UniformTypeIdentifiers

/// The downloaded-file player uses Android's canvas/overlay layout. No navigation
/// header takes space away from the picture, in either device orientation.
struct OfflinePlayerView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @StateObject private var model = OfflinePlaybackModel()
    @StateObject private var pictureInPicture = OfflinePictureInPicture()
    @State private var current: DownloadItem
    @State private var controlsVisible = true
    @State private var locked = false
    @State private var unlockVisible = false
    @State private var fillPicture = false
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var panel: OfflinePlayerPanel?
    @State private var hideTask: Task<Void, Never>?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var seekFeedback: Int?
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var originalBrightness: CGFloat?
    @State private var importedCues: [OfflineSubtitleCue] = []
    @State private var importedEnabled = false
    @State private var showSubtitleImporter = false
    @State private var subtitleError: String?

    init(item: DownloadItem) { _current = State(initialValue: item) }

    private var episodes: [DownloadItem] {
        guard let catalog = current.catalog, catalog.kind == MediaKind.tv.rawValue else { return [] }
        return downloads.items.filter {
            $0.status == .completed && $0.fileURL != nil && $0.catalog?.id == catalog.id && $0.catalog?.kind == catalog.kind
        }.sorted {
            let lhs = $0.catalog!, rhs = $1.catalog!
            return lhs.season == rhs.season ? lhs.episode < rhs.episode : lhs.season < rhs.season
        }
    }
    private var nextEpisode: DownloadItem? {
        guard let catalog = current.catalog else { return nil }
        return episodes.first { $0.catalog?.season == catalog.season && $0.catalog?.episode == catalog.episode + 1 }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                OfflineVideoSurface(player: model.player, fill: fillPicture, pictureInPicture: pictureInPicture)
                    .ignoresSafeArea().accessibilityHidden(true)
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture(count: 1)).onEnded { value in
                        if locked { revealUnlock(); return }
                        switch value {
                        case .first(let tap): skip(tap.location.x < geometry.size.width / 2 ? -10 : 10)
                        case .second: toggleControls()
                        }
                    })
                    .simultaneousGesture(MagnificationGesture().onEnded { scale in
                        guard !locked else { return }
                        if scale > 1.12 { fillPicture = true }
                        if scale < 0.88 { fillPicture = false }
                    })
                    .accessibilityLabel("Offline video")
                    .accessibilityAction(named: "Show playback controls") { if locked { revealUnlock() } else { showControls() } }

                if let error = model.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.circle").font(.largeTitle)
                        Text("Video unavailable").font(.title3.bold())
                        Text(error).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                        Button("Close video", action: close).frame(minWidth: 100, minHeight: 44)
                    }.padding(28).frame(maxWidth: 440).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                } else if !model.isReady || model.isBuffering {
                    ProgressView().tint(.white).scaleEffect(1.3).accessibilityLabel("Loading offline video")
                }

                if controlsVisible && !locked {
                    controls(size: geometry.size)
                        .transition(.opacity)
                }
                if let seekFeedback {
                    Text("\(seekFeedback > 0 ? "+" : "")\(seekFeedback) seconds")
                        .font(.title2.weight(.semibold)).padding(18).background(.black.opacity(0.5), in: Capsule())
                        .offset(x: geometry.size.width * (seekFeedback < 0 ? -0.22 : 0.22))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                if importedEnabled {
                    VStack {
                        Spacer()
                        Text(OfflineSubtitleTrack.text(at: model.position, cues: importedCues))
                            .font(.system(size: geometry.size.width > 600 ? 22 : 18, weight: .medium))
                            .multilineTextAlignment(.center).foregroundStyle(.white)
                            .shadow(color: .black, radius: 2, x: 1, y: 1).shadow(color: .black, radius: 2, x: -1, y: -1)
                            .padding(.horizontal, 32).padding(.bottom, controlsVisible && !locked ? 118 : 28)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
                if locked && unlockVisible {
                    VStack {
                        Spacer()
                        Button {
                            if voiceOver { unlock() } else { revealUnlock() }
                        } label: {
                            Label("Hold to unlock", systemImage: "lock.open")
                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 22).frame(minHeight: 48)
                                .background(.black.opacity(0.75), in: Capsule()).overlay { Capsule().strokeBorder(.white.opacity(0.4)) }
                        }.onLongPressGesture(minimumDuration: 0.65, perform: unlock)
                            .accessibilityLabel("Unlock screen").accessibilityHint("Touch and hold to unlock playback controls")
                            .accessibilityAction { unlock() }.accessibilityIdentifier("offline-unlock")
                    }.padding(.bottom, 24)
                }
                if model.finished && !locked {
                    finishedOverlay
                }
            }
            .foregroundStyle(.white).tint(.white).buttonStyle(.plain)
            .accessibilityElement(children: .contain).accessibilityIdentifier("offline-player")
        }
        .background(.black).preferredColorScheme(.dark).statusBarHidden().persistentSystemOverlays(.hidden)
        .task(id: current.id) {
            let item = current
            // Flush the previous episode while its original callback is still
            // attached; otherwise its final time could be attributed to this one.
            model.teardown()
            model.onProgress = { position, duration in
                guard let catalog = item.catalog, let downloaded = catalog.media else { return }
                let media = library.history.first { $0.media.key == downloaded.key }?.media ?? downloaded
                library.record(media, season: catalog.season, episode: catalog.episode,
                    positionSeconds: position, durationSeconds: duration)
            }
            importedCues = []; importedEnabled = false
            await restoreSubtitles(for: item)
            guard !Task.isCancelled, current.id == item.id else { return }
            await model.load(item: item)
            if scenePhase != .active { model.pauseForBackground() }
            showControls()
        }
        .onAppear {
            if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
            pictureInPicture.onStopped = { if scenePhase != .active { model.pauseForBackground() } }
        }
        .onDisappear {
            hideTask?.cancel(); feedbackTask?.cancel()
            pictureInPicture.stop(); pictureInPicture.onStopped = nil
            model.teardown()
            if let originalBrightness { UIScreen.main.brightness = originalBrightness }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                hideTask?.cancel()
                if !pictureInPicture.active && !pictureInPicture.starting { model.pauseForBackground() }
            } else { showControls() }
        }
        .onChange(of: model.isPlaying) { _, _ in if controlsVisible { scheduleHide() } }
        .onChange(of: model.isReady) { _, ready in
            if ready, importedEnabled, let group = model.subtitleGroup { model.select(option: nil, group: group) }
        }
        .onChange(of: voiceOver) { _, _ in showControls() }
        .onChange(of: brightness) { _, value in UIScreen.main.brightness = CGFloat(value) }
        .sheet(item: $panel, onDismiss: showControls) { selected in
            panelContent(selected).preferredColorScheme(.dark).presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showSubtitleImporter,
            allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText]) { result in
            let itemID = current.id
            Task {
                do {
                    let url = try result.get()
                    let cues = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let file = try FileHandle(forReadingFrom: url)
                        defer { try? file.close() }
                        let data = try file.read(upToCount: 2_000_001) ?? Data()
                        let cues = try OfflineSubtitleTrack.parse(data: data)
                        let destination = try DownloadFiles.directory().appendingPathComponent("captions-\(itemID.uuidString).txt")
                        try data.write(to: destination, options: .atomic)
                        return cues
                    }.value
                    guard current.id == itemID else { return }
                    importedCues = cues; enableImportedSubtitles()
                } catch { subtitleError = error.localizedDescription }
                showControls()
            }
        }
        .alert("Subtitles unavailable", isPresented: Binding(get: { subtitleError != nil }, set: { if !$0 { subtitleError = nil } })) {
            Button("OK") { subtitleError = nil }
        } message: { Text(subtitleError ?? "Choose a UTF-8 SRT or WebVTT file.") }
    }

    private func controls(size: CGSize) -> some View {
        ZStack {
            VStack(spacing: 0) {
                topControls
                    .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 20)
                    .background(LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom))
                Spacer(minLength: 0)
                timeline
                    .padding(.horizontal, size.width > 600 ? 28 : 18).padding(.top, 24).padding(.bottom, 12)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            }
            HStack(spacing: size.width > 600 ? 64 : 36) {
                icon("gobackward.10", label: "Back 10 seconds", id: "offline-back-10", size: 32) { skip(-10) }
                icon(model.isPlaying ? "pause.fill" : "play.fill", label: model.isPlaying ? "Pause" : "Play", id: "offline-play-pause", size: 44) {
                    model.togglePlayback(); showControls()
                }
                icon("goforward.10", label: "Forward 10 seconds", id: "offline-forward-10", size: 32) { skip(10) }
            }.disabled(!model.isReady).opacity(model.isReady ? 1 : 0.5)
            if size.width > 600 && size.height > 280 {
                HStack {
                    VStack(spacing: 2) {
                        Image(systemName: "sun.max").font(.title3).frame(width: 44, height: 40)
                        Slider(value: $brightness, in: 0.02...1, onEditingChanged: { editing in if editing { hideTask?.cancel() } else { scheduleHide() } })
                            .frame(width: 136, height: 44).rotationEffect(.degrees(-90)).frame(width: 44, height: 136)
                            .accessibilityLabel("Player brightness")
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Image(systemName: "speaker.wave.2").font(.title3).frame(width: 44, height: 40)
                        OfflineSystemVolume().frame(width: 136, height: 44).rotationEffect(.degrees(-90)).frame(width: 44, height: 136)
                            .accessibilityLabel("Player volume")
                    }
                }.padding(.horizontal, 14)
            }
        }
    }

    private var topControls: some View {
        HStack(spacing: 4) {
            icon("xmark", label: "Exit offline player", id: "offline-close", size: 20, action: close)
            Image("streamify-logo").resizable().scaledToFit().frame(width: 28, height: 28).padding(.horizontal, 4).accessibilityHidden(true)
            Text(current.title).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            icon("lock", label: "Lock screen", id: "offline-lock", size: 21) {
                hideTask?.cancel(); locked = true; controlsVisible = false; revealUnlock()
            }
            if pictureInPicture.supported {
                icon("pip.enter", label: "Picture in picture", id: "offline-pip", size: 22) { pictureInPicture.start(); showControls() }
                    .disabled(!pictureInPicture.possible)
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Slider(value: Binding(get: { scrubbing ? scrubPosition : min(model.position, max(1, model.duration)) }, set: { scrubPosition = $0 }),
                    in: 0...max(1, model.duration), onEditingChanged: { editing in
                        scrubbing = editing
                        if editing { scrubPosition = model.position; hideTask?.cancel() }
                        else { model.seek(to: scrubPosition); showControls() }
                    })
                    .tint(Color(red: 0.9, green: 0.04, blue: 0.08)).frame(minHeight: 44).disabled(model.duration <= 0)
                    .accessibilityLabel("Playback progress")
                    .accessibilityValue("\(stamp(scrubbing ? scrubPosition : model.position)) of \(stamp(model.duration))")
                    .accessibilityIdentifier("offline-progress")
                Text(stamp(max(0, model.duration - (scrubbing ? scrubPosition : model.position))))
                    .font(.caption.monospacedDigit()).frame(minWidth: 58, alignment: .trailing)
                    .accessibilityLabel("\(stamp(max(0, model.duration - model.position))) remaining")
                    .accessibilityIdentifier("offline-remaining")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { playbackActions }
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 20) { playbackActions } }
            }
        }
    }

    @ViewBuilder private var playbackActions: some View {
        Button { open(.speed) } label: { Text("Speed (\(model.rate.formatted(.number.precision(.fractionLength(0...2))))×)").font(.subheadline).frame(minHeight: 44) }
            .accessibilityIdentifier("offline-speed")
        Button { open(.tracks) } label: { Label("Audio & Subtitles", systemImage: "captions.bubble").font(.subheadline).frame(minHeight: 44) }
            .accessibilityIdentifier("offline-audio-subtitles")
        if current.catalog?.kind == MediaKind.tv.rawValue {
            Button { open(.episodes) } label: { Label("Episodes", systemImage: "rectangle.stack").font(.subheadline).frame(minHeight: 44) }
                .accessibilityIdentifier("offline-episodes")
            Button { if let nextEpisode { play(nextEpisode) } } label: { Label("Next Episode", systemImage: "forward.end").font(.subheadline).frame(minHeight: 44) }
                .disabled(nextEpisode == nil).opacity(nextEpisode == nil ? 0.5 : 1).accessibilityIdentifier("offline-next-episode")
        }
        Button { fillPicture.toggle(); showControls() } label: {
            Image(systemName: fillPicture ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
        }.accessibilityLabel(fillPicture ? "Fit picture" : "Fill screen")
    }

    private var finishedOverlay: some View {
        VStack(spacing: 16) {
            Text(nextEpisode == nil ? "Playback finished" : "Ready for the next episode?").font(.title3.bold())
            if let nextEpisode {
                Text(nextEpisode.catalog?.episodeTitle ?? nextEpisode.title).font(.subheadline).lineLimit(2)
                Button { play(nextEpisode) } label: { Label("Next episode", systemImage: "play.fill").padding(.horizontal, 24).frame(minHeight: 48).background(.white, in: Capsule()).foregroundStyle(.black) }
            }
            Button { model.seek(to: 0); model.togglePlayback(); showControls() } label: { Label("Watch again", systemImage: "arrow.counterclockwise").frame(minHeight: 44) }
            Button("Close video", action: close).frame(minHeight: 44)
        }.padding(28).frame(maxWidth: 420).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 20)).padding(20)
    }

    @ViewBuilder private func panelContent(_ selected: OfflinePlayerPanel) -> some View {
        NavigationStack {
            Group {
                switch selected {
                case .speed:
                    VStack(spacing: 24) {
                        Text("Playback speed").font(.title3.weight(.semibold))
                        HStack {
                            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5], id: \.self) { rate in
                                Button { model.setRate(rate); panel = nil } label: {
                                    VStack(spacing: 14) {
                                        Image(systemName: model.rate == rate ? "circle.inset.filled" : "circle").font(.title3)
                                        Text("\(rate.formatted(.number.precision(.fractionLength(0...2))))×").font(.subheadline)
                                    }.frame(maxWidth: .infinity, minHeight: 72)
                                }.accessibilityLabel("\(rate) times speed").accessibilityAddTraits(model.rate == rate ? .isSelected : [])
                                    .accessibilityIdentifier("offline-rate-\(rate)")
                            }
                        }
                    }.padding(24).frame(maxHeight: .infinity)
                case .tracks:
                    List {
                        Section("Audio") {
                            if let group = model.audioGroup {
                                ForEach(group.options, id: \.self) { option in
                                    Button { model.select(option: option, group: group) } label: {
                                        trackLabel(option.displayName, selected: model.selectedAudioOption == option)
                                    }
                                }
                            } else { Text("This file has no alternate audio tracks.").foregroundStyle(.secondary) }
                        }
                        Section("Subtitles") {
                            if let group = model.subtitleGroup {
                                Button { disableImportedSubtitles(); model.select(option: nil, group: group) } label: { trackLabel("Off", selected: model.selectedSubtitleOption == nil && !importedEnabled) }
                                ForEach(group.options, id: \.self) { option in
                                    Button { disableImportedSubtitles(); model.select(option: option, group: group) } label: {
                                        trackLabel(option.displayName, selected: model.selectedSubtitleOption == option && !importedEnabled)
                                    }
                                }
                            } else { Text("This file has no embedded subtitles.").foregroundStyle(.secondary) }
                            if !importedCues.isEmpty {
                                Button(action: enableImportedSubtitles) { trackLabel("Imported subtitles", selected: importedEnabled) }
                                if model.subtitleGroup == nil {
                                    Button(action: disableImportedSubtitles) { trackLabel("Off", selected: !importedEnabled) }
                                }
                            }
                            Button {
                                panel = nil; hideTask?.cancel()
                                Task { try? await Task.sleep(nanoseconds: 350_000_000); showSubtitleImporter = true }
                            } label: { Label("Import SRT or VTT file", systemImage: "folder").frame(minHeight: 44) }
                        }
                    }
                case .episodes:
                    List(episodes) { item in
                        Button { play(item); panel = nil } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.catalog?.episodeTitle ?? item.title).font(.subheadline.weight(.medium))
                                    if let catalog = item.catalog { Text("Season \(catalog.season) · Episode \(catalog.episode)").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if current.id == item.id { Image(systemName: "speaker.wave.2.fill") }
                            }.frame(minHeight: 44)
                        }
                    }
                }
            }
            .foregroundStyle(.white).tint(.white).background(Color.black)
            .navigationTitle(selected.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { panel = nil }.frame(minHeight: 44) } }
        }
    }

    private func trackLabel(_ title: String, selected: Bool) -> some View {
        HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark") } }.frame(minHeight: 44)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func icon(_ symbol: String, label: String, id: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: size, weight: .regular)).frame(minWidth: 48, minHeight: 56).contentShape(Rectangle()) }
            .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func open(_ value: OfflinePlayerPanel) { hideTask?.cancel(); panel = value }
    private func enableImportedSubtitles() {
        guard !importedCues.isEmpty else { return }
        if let group = model.subtitleGroup { model.select(option: nil, group: group) }
        importedEnabled = true
        UserDefaults.standard.set(true, forKey: "streamify.ios.offlineSubtitles.\(current.id.uuidString)")
    }
    private func disableImportedSubtitles() {
        importedEnabled = false
        UserDefaults.standard.set(false, forKey: "streamify.ios.offlineSubtitles.\(current.id.uuidString)")
    }
    private func restoreSubtitles(for item: DownloadItem) async {
        let cues = await Task.detached(priority: .utility) {
            guard let url = try? DownloadFiles.directory().appendingPathComponent("captions-\(item.id.uuidString).txt"),
                  let file = try? FileHandle(forReadingFrom: url) else { return [OfflineSubtitleCue]() }
            defer { try? file.close() }
            guard let data = try? file.read(upToCount: 2_000_001) else { return [OfflineSubtitleCue]() }
            return (try? OfflineSubtitleTrack.parse(data: data)) ?? []
        }.value
        guard current.id == item.id, !Task.isCancelled else { return }
        importedCues = cues
        importedEnabled = !cues.isEmpty && (UserDefaults.standard.object(forKey: "streamify.ios.offlineSubtitles.\(item.id.uuidString)") as? Bool != false)
    }
    private func play(_ item: DownloadItem) { current = item; controlsVisible = true; scrubbing = false; scrubPosition = 0 }
    private func close() { hideTask?.cancel(); pictureInPicture.stop(); model.teardown(); dismiss() }
    private func unlock() { locked = false; unlockVisible = false; showControls() }
    private func revealUnlock() {
        unlockVisible = true; hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if !Task.isCancelled { unlockVisible = false } }
    }
    private func toggleControls() {
        if controlsVisible { hideTask?.cancel(); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { controlsVisible = false } }
        else { showControls() }
    }
    private func showControls() {
        guard !locked else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { controlsVisible = true }
        scheduleHide()
    }
    private func scheduleHide() {
        hideTask?.cancel()
        guard model.isPlaying, !voiceOver, !scrubbing, panel == nil, !showSubtitleImporter, !locked else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { controlsVisible = false } }
        }
    }
    private func skip(_ seconds: Int) {
        guard model.isReady, !locked else { return }
        model.skip(by: Double(seconds)); showControls(); seekFeedback = seconds
        feedbackTask?.cancel()
        feedbackTask = Task { try? await Task.sleep(nanoseconds: 800_000_000); if !Task.isCancelled { seekFeedback = nil } }
    }
    private func stamp(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

private enum OfflinePlayerPanel: String, Identifiable {
    case speed, tracks, episodes
    var id: String { rawValue }
    var title: String { switch self { case .speed: "Playback speed"; case .tracks: "Audio & Subtitles"; case .episodes: "Downloaded episodes" } }
}

private final class OfflinePlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct OfflineVideoSurface: UIViewRepresentable {
    let player: AVPlayer?
    let fill: Bool
    let pictureInPicture: OfflinePictureInPicture
    func makeUIView(context: Context) -> OfflinePlayerLayerView {
        let view = OfflinePlayerLayerView(); view.backgroundColor = .black; return view
    }
    func updateUIView(_ view: OfflinePlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
        DispatchQueue.main.async { pictureInPicture.attach(view.playerLayer) }
    }
    static func dismantleUIView(_ view: OfflinePlayerLayerView, coordinator: ()) { view.playerLayer.player = nil }
}

@MainActor
private final class OfflinePictureInPicture: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let supported = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var active = false
    @Published private(set) var starting = false
    @Published private(set) var possible = false
    var onStopped: (() -> Void)?
    private var controller: AVPictureInPictureController?
    private var observation: NSKeyValueObservation?
    func attach(_ layer: AVPlayerLayer) {
        guard supported, controller?.playerLayer !== layer else { return }
        observation?.invalidate()
        let created = AVPictureInPictureController(playerLayer: layer)
        controller = created; created?.delegate = self
        created?.canStartPictureInPictureAutomaticallyFromInline = false
        observation = created?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            Task { @MainActor [weak self] in self?.possible = controller.isPictureInPicturePossible }
        }
    }
    func start() { if possible { starting = true; controller?.startPictureInPicture() } }
    func stop() { controller?.stopPictureInPicture(); observation?.invalidate(); observation = nil; controller?.delegate = nil; controller = nil; active = false; starting = false; possible = false }
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        let identity = ObjectIdentifier(pictureInPictureController)
        Task { @MainActor [weak self] in
            guard let self, self.controller.map(ObjectIdentifier.init) == identity else { return }
            self.starting = false; self.active = true
        }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        let identity = ObjectIdentifier(pictureInPictureController)
        Task { @MainActor [weak self] in
            guard let self, self.controller.map(ObjectIdentifier.init) == identity else { return }
            self.starting = false; self.active = false; self.onStopped?()
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let identity = ObjectIdentifier(pictureInPictureController)
        Task { @MainActor [weak self] in
            guard let self, self.controller.map(ObjectIdentifier.init) == identity else { return }
            self.starting = false; self.active = false; self.onStopped?()
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The full-screen view remains mounted throughout PiP. This callback
        // needs no actor-owned state and can acknowledge restoration directly.
        completionHandler(true)
    }
}

private struct OfflineSystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(); view.showsRouteButton = false; view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
