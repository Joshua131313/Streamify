import SwiftUI

struct MediaPlayerView: View {
    let media: MediaItem
    private let origin: MediaPlaybackOrigin?
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var season: Int
    @State private var episode: Int
    @State private var serverID = ""
    @AppStorage("streamify.ios.animeSource") private var animeSourceID = "323-sub"
    @State private var direct = false
    @State private var reload = 0
    @State private var url: URL?
    @State private var referer: URL?
    @State private var error: String?
    @State private var details: MediaDetails?
    @State private var showEpisodes = false

    init(media: MediaItem, season: Int = 1, episode: Int = 1, origin: MediaPlaybackOrigin? = nil) {
        self.media = media
        self.origin = origin
        _season = State(initialValue: max(1, season))
        _episode = State(initialValue: max(1, episode))
    }
    private var activeServer: MediaServer? {
        let id = serverID.isEmpty ? settings.serverID : serverID
        return settings.servers.first { $0.id == id } ?? settings.servers.first
    }
    private var animeSource: AnimePlaybackSource {
        AnimePlaybackSource.all.first { $0.id == animeSourceID } ?? AnimePlaybackSource.all[0]
    }
    private var sourceLabel: String { media.kind == .anime ? animeSource.label : (activeServer?.label ?? "Choose source") }
    private var loadID: String { "\(media.key):\(season):\(episode):\(media.kind == .anime ? animeSourceID : (activeServer?.id ?? "")):\(reload)" }
    private var next: (season: Int, episode: Int)? {
        guard media.kind != .movie, let details,
              let current = details.seasons.first(where: { $0.number == season }) else { return nil }
        if episode < current.count { return (season, episode + 1) }
        if let following = details.seasons.filter({ $0.number > season && $0.count > 0 }).sorted(by: { $0.number < $1.number }).first {
            return (following.number, 1)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close player")
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title).font(.headline).lineLimit(1)
                    if media.kind != .movie {
                        Text(media.kind == .anime ? "Episode \(episode)" : "Season \(season) · Episode \(episode)")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            }.padding(.horizontal, 8).frame(minHeight: 58)

            ZStack {
                Color.black
                if let url {
                    let identity = PlaybackIdentity(mediaKey: media.key, season: season, episode: episode)
                    let session = loadID
                    let resume = identity.resumeSeconds(from: library.history.first { $0.id == media.key })
                    ProviderPlaybackSurface(url: url, reload: reload, direct: direct, referer: referer,
                        resumeSeconds: resume, onProgress: { position, duration in
                            // A detached old player must never overwrite the newly selected episode.
                            guard session == loadID, identity.season == season, identity.episode == episode else { return }
                            library.record(media, season: identity.season, episode: identity.episode,
                                positionSeconds: position, durationSeconds: duration)
                        }, autoplay: true).id(loadID)
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "play.slash").font(.largeTitle)
                        Text("Source unavailable").font(.title3.bold())
                        Text(error).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
                        Button("Retry") { reload += 1 }.buttonStyle(PrimaryButtonStyle())
                    }.padding(28).frame(maxWidth: 440)
                } else {
                    VStack(spacing: 14) { ProgressView().tint(.white); Text("Finding your source…").font(.subheadline) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Menu {
                        if media.kind == .anime {
                            ForEach(AnimePlaybackSource.all) { source in
                                Button { animeSourceID = source.id } label: {
                                    if animeSourceID == source.id { Label(source.label, systemImage: "checkmark") }
                                    else { Text(source.label) }
                                }
                            }
                        } else {
                            ForEach(settings.servers) { source in
                                Button { serverID = source.id } label: {
                                    if activeServer?.id == source.id { Label(source.label, systemImage: "checkmark") }
                                    else { Text(source.label) }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(sourceLabel).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.caption2)
                        }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44).streamifyControlSurface()
                    }.buttonStyle(HapticPlainButtonStyle())
                    Button { reload += 1 } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44).streamifyControlSurface() }.accessibilityLabel("Reload player")
                    Button { direct.toggle() } label: { Image(systemName: direct ? "rectangle.inset.filled" : "rectangle.on.rectangle").frame(width: 44, height: 44).streamifyControlSurface() }
                        .accessibilityLabel(direct ? "Switch to embed mode" : "Switch to direct mode")
                    if let url {
                        Button { openURL(url) } label: { Image(systemName: "safari").frame(width: 44, height: 44).streamifyControlSurface() }.accessibilityLabel("Open source in Safari")
                    }
                }
                MediaDownloadButton(media: media, season: season, episode: episode)
                if media.kind != .movie {
                    HStack(spacing: 12) {
                        Button { showEpisodes = true } label: {
                            Label("Episodes", systemImage: "list.bullet").frame(maxWidth: .infinity).frame(minHeight: 44)
                        }.buttonStyle(SecondaryButtonStyle())
                        if let next {
                            Button { season = next.season; episode = next.episode } label: {
                                Label("Next episode", systemImage: "forward.end.fill").frame(maxWidth: .infinity).frame(minHeight: 44)
                            }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                Text("\(direct ? "Direct" : "Embed") mode · Source availability varies. AirPlay depends on the source.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .mediaPlayerCardDismissal(origin: origin, sessionKey: loadID, enabled: !showEpisodes) { dismiss() }
        .presentationBackground(.clear)
        .task(id: loadID) { await loadSource() }
        .task {
            do { details = try await settings.client.details(media) } catch { /* Playback can still use the chosen source. */ }
        }
        .sheet(isPresented: $showEpisodes) {
            PlayerEpisodePicker(media: media, seasons: details?.seasons ?? [], selectedSeason: season, selectedEpisode: episode) { selectedSeason, selectedEpisode in
                season = selectedSeason; episode = selectedEpisode; showEpisodes = false
            }
        }
    }

    @MainActor private func loadSource() async {
        let request = loadID
        let requestedSeason = season
        let requestedEpisode = episode
        url = nil; referer = nil; error = nil
        do {
            let resolved: URL
            var resolvedReferer: URL?
            if media.kind == .anime {
                let anime = try await AnikotoResolver.shared.resolve(media: media, episode: requestedEpisode, source: animeSource, client: settings.client)
                resolved = anime.url; resolvedReferer = anime.referer
            } else if let address = activeServer?.url(media: media, season: requestedSeason, episode: requestedEpisode) { resolved = address }
            else { throw AnimePlaybackError.unavailable("No video providers are configured. Check that media-servers.json is included in the app resources.") }
            try Task.checkCancellation()
            guard request == loadID else { return }
            referer = resolvedReferer; url = resolved
            // Opening a provider is history, not proof that the provider's video played.
            library.record(media, season: requestedSeason, episode: requestedEpisode)
        } catch is CancellationError { return }
        catch { if !Task.isCancelled && request == loadID { self.error = error.localizedDescription } }
    }
}

private struct PlayerEpisodePicker: View {
    let media: MediaItem
    let seasons: [MediaSeason]
    let selectedSeason: Int
    let selectedEpisode: Int
    let select: (Int, Int) -> Void
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var season: Int
    @State private var episodes: [MediaEpisode] = []
    @State private var error: String?
    @State private var loading = false
    @State private var revision = 0

    init(media: MediaItem, seasons: [MediaSeason], selectedSeason: Int, selectedEpisode: Int, select: @escaping (Int, Int) -> Void) {
        self.media = media; self.seasons = seasons; self.selectedSeason = selectedSeason
        self.selectedEpisode = selectedEpisode; self.select = select
        _season = State(initialValue: selectedSeason)
    }

    private var seasonName: String {
        seasons.first { $0.number == season }?.name ?? "Season \(season)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(media.title).font(.title3.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        if !seasons.isEmpty { seasonMenu }
                    }
                    LazyVStack(spacing: 10) {
                        if loading {
                            ProgressView("Loading episodes…")
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                        if let error {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(error).font(.subheadline).foregroundStyle(AppTheme.muted)
                                Button("Retry") { revision += 1 }.buttonStyle(SecondaryButtonStyle())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                        }
                        ForEach(episodes) { episode in episodeRow(episode) }
                        if !loading && error == nil && episodes.isEmpty {
                            Text("No episodes are available for this season.")
                                .font(.subheadline).foregroundStyle(AppTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
            }
            .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
            .navigationTitle("Episodes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(season):\(revision)") {
                loading = true; error = nil; episodes = []
                do {
                    let value = try await settings.client.episodes(media: media, season: season)
                    try Task.checkCancellation(); episodes = value
                } catch is CancellationError { return }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                if !Task.isCancelled { loading = false }
            }
        }.preferredColorScheme(.dark).tint(AppTheme.foreground)
            .presentationDragIndicator(.visible).presentationCornerRadius(24)
    }

    private var seasonMenu: some View {
        Menu {
            ForEach(seasons) { item in
                Button { season = item.number } label: {
                    if item.number == season { Label(item.name, systemImage: "checkmark") }
                    else { Text(item.name) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack").foregroundStyle(AppTheme.muted)
                Text(seasonName).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let count = seasons.first(where: { $0.number == season })?.count, count > 0 {
                    Text("\(count) episodes").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }.padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 50)
                .streamifyControlSurface(cornerRadius: 12)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(HapticPlainButtonStyle())
            .accessibilityLabel(seasonName)
            .accessibilityHint("Choose a season")
            .accessibilityIdentifier("player-episode-season-picker")
    }

    private func episodeRow(_ episode: MediaEpisode) -> some View {
        let selected = selectedSeason == season && selectedEpisode == episode.number
        return Button { select(season, episode.number) } label: {
            HStack(alignment: .top, spacing: 12) {
                RemoteArtwork(url: episode.stillURL ?? media.backdropURL)
                    .frame(width: 104, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        if selected {
                            Image(systemName: "play.fill").font(.caption.weight(.semibold))
                                .foregroundStyle(.white).frame(width: 28, height: 28)
                                .background(.black.opacity(0.65), in: Circle())
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(episode.number). \(episode.title)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.foreground)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if episode.runtime > 0 || !episode.airDate.isEmpty {
                        Text(episode.runtime > 0 ? "\(episode.runtime) min" : episode.airDate)
                            .font(.caption2).foregroundStyle(AppTheme.muted)
                    }
                    if !episode.overview.isEmpty {
                        Text(episode.overview).font(.caption).foregroundStyle(AppTheme.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(selected ? AppTheme.foreground.opacity(0.28) : AppTheme.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(HapticPlainButtonStyle())
            .accessibilityValue(selected ? "Current episode" : "")
            .accessibilityIdentifier("player-episode-choice-\(season)-\(episode.number)")
    }
}
