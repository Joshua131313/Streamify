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
    @StateObject private var volumeController = OfflineVolumeController()
    @StateObject private var seekPreview = OfflineSeekPreviewModel()
    @State private var current: DownloadItem
    @State private var controlsVisible = true
    @State private var locked = false
    @State private var unlockVisible = false
    @State private var fillPicture = false
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var seekThumbInWindow: CGRect?
    @State private var panel: OfflinePlayerPanel?
    @State private var hideTask: Task<Void, Never>?
    @State private var backwardFeedback = OfflineSkipFeedback()
    @State private var forwardFeedback = OfflineSkipFeedback()
    @State private var edgeDrag: OfflineEdgeDrag?
    @State private var edgeRejected = false
    @State private var edgeFeedback: OfflineEdgeFeedback?
    @State private var edgeFeedbackTask: Task<Void, Never>?
    @State private var pinching = false
    @GestureState private var edgeGestureActive = false
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var originalBrightness: CGFloat?
    @State private var importedCues: [OfflineSubtitleCue] = []
    @State private var importedEnabled = false
    @State private var showSubtitleImporter = false
    @State private var subtitleError: String?
    @State private var showRecoveryDownload = false

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

    private var playerCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                OfflineVideoSurface(player: model.player, fill: fillPicture, pictureInPicture: pictureInPicture)
                    .ignoresSafeArea().accessibilityHidden(true)
                videoInteractions(size: geometry.size)
                playbackAvailability(size: geometry.size)
                transportOverlays(size: geometry.size)
                seekPreviewOverlay(in: geometry)
            }
            .foregroundStyle(.white).tint(.white).buttonStyle(HapticPlainButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("offline-player")
        }
    }

    private func videoInteractions(size: CGSize) -> some View {
        Color.clear.contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .updating($edgeGestureActive) { _, active, _ in active = true }
                .onChanged { updateEdgeDrag($0, size: size) }
                .onEnded { _ in finishEdgeDrag() })
            .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture(count: 1)).onEnded { value in
                if locked { revealUnlock(); return }
                switch value {
                case .first(let tap): skip(tap.location.x < size.width / 2 ? -10 : 10)
                case .second: toggleControls()
                }
            })
            .simultaneousGesture(MagnificationGesture().onChanged { _ in
                pinching = true; cancelEdgeDrag()
            }.onEnded { scale in
                pinching = false
                guard !locked else { return }
                if scale > 1.12 { fillPicture = true }
                if scale < 0.88 { fillPicture = false }
            })
            .accessibilityLabel("Offline video")
            .accessibilityAction(named: "Show playback controls") { if locked { revealUnlock() } else { showControls() } }
    }

    @ViewBuilder private func playbackAvailability(size: CGSize) -> some View {
        if let error = model.error {
            ScrollView {
              VStack(spacing: 16) {
                Image(systemName: "exclamationmark.circle").font(.largeTitle)
                Text("Video unavailable").font(.title3.bold())
                Text(error).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                if let suggestion = model.videoError?.recoverySuggestion {
                    Text(suggestion).font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65))
                }
                if current.catalog?.media != nil {
                    Button { showRecoveryDownload = true } label: {
                        Label("Choose another download", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                            .foregroundStyle(.black)
                    }.accessibilityIdentifier("offline-recover-download")
                }
                if let file = current.fileURL, FileManager.default.isReadableFile(atPath: file.path) {
                    ShareLink(item: file, preview: SharePreview(current.title)) {
                        Label("Open in another app", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                    }.accessibilityIdentifier("offline-share-video")
                }
                Button("Close video", action: close).frame(minWidth: 100, minHeight: 44)
              }.padding(28).frame(maxWidth: .infinity)
            }.frame(maxWidth: 440, maxHeight: max(80, size.height - 96))
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20).accessibilityIdentifier("offline-video-error")
        } else if !model.isReady || model.isBuffering {
            ProgressView().tint(.white).scaleEffect(1.3).accessibilityLabel("Loading offline video")
        }
    }

    @ViewBuilder private func transportOverlays(size: CGSize) -> some View {
        if model.error != nil {
            VStack {
                HStack {
                    icon("xmark", label: "Exit offline player", id: "offline-close", size: 20, action: close)
                    Spacer()
                }.padding(.horizontal, 12).padding(.top, 6)
                Spacer()
            }
        } else if controlsVisible && !locked {
            controls(size: size)
                .transition(.opacity)
        }
        sideControls(size: size)
        if let edgeFeedback, model.error == nil, !locked {
            edgeFeedbackView(edgeFeedback)
        }
        if importedEnabled && model.error == nil {
            VStack {
                Spacer()
                Text(OfflineSubtitleTrack.text(at: model.position, cues: importedCues))
                    .font(.system(size: size.width > 600 ? 22 : 18, weight: .medium))
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                    .shadow(color: .black, radius: 2, x: 1, y: 1).shadow(color: .black, radius: 2, x: -1, y: -1)
                    .padding(.horizontal, 32).padding(.bottom, controlsVisible && !locked ? 118 : 28)
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        if locked && unlockVisible && model.error == nil {
            VStack {
                Spacer()
                OfflineHoldUnlockControl(reduceMotion: reduceMotion,
                    onHold: { hideTask?.cancel() },
                    onCancel: { if locked { revealUnlock() } },
                    onUnlock: {
                        guard locked else { return }
                        AppHaptics.tap(.primary); unlock()
                    })
                    .frame(width: 140, height: 100)
            }.padding(.bottom, 20)
        }
        if model.finished && !locked && model.error == nil {
            finishedOverlay
        }
    }

    @ViewBuilder private func seekPreviewOverlay(in geometry: GeometryProxy) -> some View {
        if scrubbing, controlsVisible, !locked, panel == nil, model.error == nil,
           seekPreview.visible, let thumb = seekThumbInWindow {
            OfflineSeekPreviewBubble(model: seekPreview)
                .position(OfflineSeekPreviewMath.position(thumbInWindow: thumb,
                    viewportInWindow: geometry.frame(in: .global), bottomSafeAreaInset: geometry.safeAreaInsets.bottom))
        }
    }

    private var lifecyclePlayer: some View {
        playerCanvas
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
            seekPreview.close(); seekThumbInWindow = nil
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
            hideTask?.cancel(); cancelEdgeDrag()
            seekPreview.close()
            pictureInPicture.stop(); pictureInPicture.onStopped = nil
            model.teardown()
            if let originalBrightness { UIScreen.main.brightness = originalBrightness }
        }
    }

    private var observedPlayer: some View {
        lifecyclePlayer
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                hideTask?.cancel(); cancelEdgeDrag(); pinching = false; unlockVisible = false
                scrubbing = false; seekPreview.hide()
                if !pictureInPicture.active && !pictureInPicture.starting { model.pauseForBackground() }
            } else { showControls() }
        }
        .onChange(of: model.isPlaying) { _, _ in if controlsVisible { scheduleHide() } }
        .onChange(of: model.isReady) { _, ready in
            if ready, importedEnabled, let group = model.subtitleGroup { model.select(option: nil, group: group) }
        }
        .onChange(of: voiceOver) { _, _ in showControls() }
        .onChange(of: edgeGestureActive) { _, active in
            if !active, edgeDrag != nil || edgeRejected { finishEdgeDrag() }
        }
        .onChange(of: locked) { _, _ in cancelEdgeDrag(); seekPreview.hide() }
        .onChange(of: panel) { _, _ in cancelEdgeDrag(); seekPreview.hide() }
        .onChange(of: model.error) { _, error in if error != nil { scrubbing = false; seekPreview.hide() } }
        .onChange(of: showSubtitleImporter) { _, _ in cancelEdgeDrag() }
        .onChange(of: brightness) { _, value in UIScreen.main.brightness = CGFloat(value) }
    }

    private var presentedPlayer: some View {
        observedPlayer
        .sheet(item: $panel, onDismiss: showControls) { selected in
            panelContent(selected).preferredColorScheme(.dark).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRecoveryDownload) {
            if let catalog = current.catalog, let media = catalog.media {
                NavigationStack {
                    MediaDownloadSheet(media: media, season: catalog.season, episode: catalog.episode,
                        episodeTitle: catalog.episodeTitle, replacingDownloadID: current.id)
                }.preferredColorScheme(.dark)
            }
        }
    }

    var body: some View {
        presentedPlayer
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
                OfflineSkipControl(forward: false, feedback: backwardFeedback, reduceMotion: reduceMotion || voiceOver) { skip(-10) }
                icon(model.isPlaying ? "pause.fill" : "play.fill", label: model.isPlaying ? "Pause" : "Play", id: "offline-play-pause", size: 44) {
                    model.togglePlayback(); showControls()
                }
                OfflineSkipControl(forward: true, feedback: forwardFeedback, reduceMotion: reduceMotion || voiceOver) { skip(10) }
            }.disabled(!model.isReady).opacity(model.isReady ? 1 : 0.5)
        }
    }

    private func sideControls(size: CGSize) -> some View {
        let visible = size.width > 600 && size.height > 280 && controlsVisible && !locked && model.error == nil
        return HStack {
            VStack(spacing: 2) {
                Image(systemName: "sun.max").font(.title3).frame(width: 44, height: 40)
                Slider(value: $brightness, in: 0.02...1, onEditingChanged: { editing in
                    if editing { hideTask?.cancel() } else { scheduleHide() }
                })
                    .frame(width: 136, height: 44).rotationEffect(.degrees(-90)).frame(width: 44, height: 136)
                    .accessibilityLabel("Player brightness").accessibilityValue("\(Int((brightness * 100).rounded())) percent")
                    .accessibilityIdentifier("offline-brightness")
            }
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: "speaker.wave.2").font(.title3).frame(width: 44, height: 40)
                OfflineSystemVolume(controller: volumeController)
                    .frame(width: 136, height: 44).rotationEffect(.degrees(-90)).frame(width: 44, height: 136)
                    .accessibilityLabel("Player volume")
            }
        }
        // Keep the public system volume view mounted, including in portrait,
        // so a deliberate edge drag can operate its actual hardware slider.
        .padding(.horizontal, 14).opacity(visible ? 1 : 0.001)
        .allowsHitTesting(visible).accessibilityHidden(!visible)
    }

    private func edgeFeedbackView(_ feedback: OfflineEdgeFeedback) -> some View {
        HStack {
            if feedback.side == .volume { Spacer() }
            VStack(spacing: 7) {
                Image(systemName: feedback.side == .brightness ? "sun.max" : "speaker.wave.2").font(.system(size: 17))
                Text("\(Int((feedback.value * 100).rounded()))%").font(.caption.monospacedDigit())
                ProgressView(value: feedback.value).tint(.white).frame(width: 32)
            }
            .frame(width: 54, height: 88).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(feedback.side == .brightness ? "Brightness" : "Volume")
            .accessibilityValue("\(Int((feedback.value * 100).rounded())) percent")
            .accessibilityIdentifier("offline-edge-feedback")
            if feedback.side == .brightness { Spacer() }
        }.padding(.horizontal, 24).allowsHitTesting(false)
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
                OfflineSeekSlider(
                    value: Binding(get: { scrubbing ? scrubPosition : model.position }, set: { scrubPosition = $0 }),
                    duration: model.duration, enabled: model.isReady && !locked && scenePhase == .active,
                    onEditingChanged: { editing in
                        scrubbing = editing
                        if editing { hideTask?.cancel() }
                        else { seekPreview.hide(); showControls() }
                    },
                    onCommit: { model.seek(to: $0) },
                    onThumbMoved: { rect in
                        seekThumbInWindow = rect
                        guard scrubbing, !locked, scenePhase == .active, controlsVisible,
                              panel == nil, model.error == nil, let file = current.fileURL else { return }
                        seekPreview.show(url: file, seconds: scrubPosition, duration: model.duration)
                    })
                    .frame(minHeight: 44)
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
                                ForEach(model.availableOptions(in: group), id: \.self) { option in
                                    Button { model.select(option: option, group: group) } label: {
                                        trackLabel(option.displayName, selected: model.selectedAudioOption == option)
                                    }
                                }
                            } else { Text("This file has no alternate audio tracks.").foregroundStyle(.secondary) }
                        }
                        Section("Subtitles") {
                            if let group = model.subtitleGroup {
                                Button { disableImportedSubtitles(); model.select(option: nil, group: group) } label: { trackLabel("Off", selected: model.selectedSubtitleOption == nil && !importedEnabled) }
                                ForEach(model.availableOptions(in: group), id: \.self) { option in
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
        #if DEBUG
        // Long playback/control flows keep their assertions independent of
        // simulator accessibility latency. Gesture/timer tests omit this flag.
        if PreviewFixtures.usesStableOfflineControls { return }
        #endif
        guard model.isPlaying, !voiceOver, !scrubbing, edgeDrag == nil, panel == nil, !showSubtitleImporter, !locked else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { controlsVisible = false } }
        }
    }
    private func skip(_ seconds: Int) {
        guard model.isReady, !locked else { return }
        model.skip(by: Double(seconds)); showControls()
        if seconds < 0 { backwardFeedback.record(seconds) }
        else { forwardFeedback.record(seconds) }
        if voiceOver {
            let total = seconds < 0 ? backwardFeedback.total : forwardFeedback.total
            UIAccessibility.post(notification: .announcement, argument: "\(total > 0 ? "+" : "")\(total) seconds")
        }
    }
    private func updateEdgeDrag(_ value: DragGesture.Value, size: CGSize) {
        guard !locked, !voiceOver, !pinching, scenePhase == .active, model.error == nil,
              panel == nil, !showSubtitleImporter, !pictureInPicture.active,
              size.width > 0, size.height > 0, !edgeRejected else { return }
        if edgeDrag == nil {
            guard abs(value.translation.height) > abs(value.translation.width) else {
                edgeRejected = true; return
            }
            let side: OfflineEdgeSide
            let initial: Double
            if value.startLocation.x < size.width * 0.18 {
                side = .brightness; initial = brightness
            } else if value.startLocation.x > size.width * 0.82, let actual = volumeController.volume() {
                side = .volume; initial = actual
            } else { edgeRejected = true; return }
            hideTask?.cancel(); edgeFeedbackTask?.cancel()
            edgeDrag = OfflineEdgeDrag(side: side, initial: initial)
        }
        guard let drag = edgeDrag else { return }
        // Android uses the initial edge level plus 1.5 screen heights of gain.
        let target = drag.initial - Double(value.translation.height / size.height) * 1.5
        let actual: Double
        switch drag.side {
        case .brightness:
            actual = min(1, max(0.02, target)); brightness = actual
        case .volume:
            guard let reported = volumeController.setVolume(target) else { return }
            actual = reported
        }
        edgeFeedback = OfflineEdgeFeedback(side: drag.side, value: actual)
    }
    private func finishEdgeDrag() {
        edgeDrag = nil; edgeRejected = false
        edgeFeedbackTask?.cancel()
        if edgeFeedback != nil {
            edgeFeedbackTask = Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !Task.isCancelled { edgeFeedback = nil }
            }
        }
        if controlsVisible { scheduleHide() }
    }
    private func cancelEdgeDrag() {
        edgeDrag = nil; edgeRejected = false; edgeFeedback = nil
        edgeFeedbackTask?.cancel(); edgeFeedbackTask = nil
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

private enum OfflineEdgeSide: Equatable { case brightness, volume }
private struct OfflineEdgeDrag { let side: OfflineEdgeSide; let initial: Double }
private struct OfflineEdgeFeedback { let side: OfflineEdgeSide; let value: Double }

private struct OfflineSkipFeedback {
    var total = 0
    var startedAt: Date?
    var generation = 0
    mutating func record(_ delta: Int) {
        let now = Date()
        total = startedAt.map { now.timeIntervalSince($0) < 0.85 } == true ? total + delta : delta
        startedAt = now; generation += 1
    }
}

/// The same 305-degree arc, arrow, expanding ripple and cumulative number as
/// Android's SkipControl. Only this control animates; no floating message.
private struct OfflineSkipControl: View {
    let forward: Bool
    let feedback: OfflineSkipFeedback
    let reduceMotion: Bool
    let action: () -> Void
    @State private var active = false

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active || reduceMotion)) { timeline in
                Canvas { context, size in
                    let elapsed = feedback.startedAt.map { timeline.date.timeIntervalSince($0) } ?? 1
                    let fraction = min(1, max(0, elapsed / 0.85))
                    let pulse = active ? (1 + cos(.pi * fraction)) / 2 : 0
                    draw(context: context, size: size, pulse: pulse)
                }
            }.frame(width: 64, height: 64).contentShape(Rectangle())
        }
        .accessibilityLabel(forward ? "Forward 10 seconds" : "Back 10 seconds")
        .accessibilityIdentifier(forward ? "offline-forward-10" : "offline-back-10")
        .task(id: feedback.generation) {
            guard let start = feedback.startedAt else { active = false; return }
            let remaining = max(0, 0.85 - Date().timeIntervalSince(start))
            active = remaining > 0
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            if !Task.isCancelled { active = false }
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, pulse: Double) {
        let unit = min(size.width, size.height) / 96
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let movement = reduceMotion ? 0 : pulse
        let radius = unit * CGFloat(33 + 8 * (1 - movement))
        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(.white.opacity(active ? (reduceMotion ? 0.07 : pulse * 28 / 255) : 0)))
        var arcContext = context
        arcContext.translateBy(x: center.x, y: center.y)
        arcContext.scaleBy(x: forward ? 1 : -1, y: 1)
        arcContext.rotate(by: .degrees(movement * 22))
        var arc = Path()
        arc.addArc(center: .zero, radius: 23 * unit, startAngle: .degrees(-55), endAngle: .degrees(250), clockwise: false)
        arc.move(to: CGPoint(x: 13.19 * unit, y: -27.84 * unit))
        arc.addLine(to: CGPoint(x: 13.19 * unit, y: -18.84 * unit))
        arc.addLine(to: CGPoint(x: 4.19 * unit, y: -18.84 * unit))
        arcContext.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, lineJoin: .round))
        let number = active ? "\(feedback.total > 0 ? "+" : "")\(feedback.total)" : "10"
        context.draw(Text(number).font(.system(size: 18 * unit, weight: .medium)).foregroundColor(.white), at: center)
    }
}
