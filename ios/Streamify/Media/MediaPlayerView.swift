import SwiftUI

struct MediaPlayerView: View {
    let media: MediaItem
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

    init(media: MediaItem, season: Int = 1, episode: Int = 1) {
        self.media = media
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
                    ProviderPlaybackSurface(url: url, reload: reload, direct: direct, referer: referer).id(loadID)
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "play.slash").font(.largeTitle)
                        Text("Source unavailable").font(.title3.bold())
                        Text(error).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
                        Button("Retry") { reload += 1 }.buttonStyle(.borderedProminent).tint(AppTheme.accent)
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
                        Label(sourceLabel, systemImage: "server.rack").lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                    }
                    Button { reload += 1 } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Reload player")
                    Button { direct.toggle() } label: { Image(systemName: direct ? "rectangle.inset.filled" : "rectangle.on.rectangle").frame(width: 44, height: 44) }
                        .accessibilityLabel(direct ? "Switch to embed mode" : "Switch to direct mode")
                    if let url {
                        Button { openURL(url) } label: { Image(systemName: "safari").frame(width: 44, height: 44) }.accessibilityLabel("Open source in Safari")
                    }
                }
                if media.kind != .movie {
                    HStack(spacing: 12) {
                        Button { showEpisodes = true } label: {
                            Label("Episodes", systemImage: "list.bullet").frame(maxWidth: .infinity).frame(minHeight: 44)
                        }.background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        if let next {
                            Button { season = next.season; episode = next.episode } label: {
                                Label("Next episode", systemImage: "forward.end.fill").frame(maxWidth: .infinity).frame(minHeight: 44)
                            }.background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                Text("\(direct ? "Direct" : "Embed") mode · Source availability varies. AirPlay depends on the source.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
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
        url = nil; referer = nil; error = nil
        do {
            let resolved: URL
            if media.kind == .anime {
                let anime = try await AnikotoResolver.shared.resolve(media: media, episode: episode, source: animeSource, client: settings.client)
                resolved = anime.url; referer = anime.referer
            } else if let address = activeServer?.url(media: media, season: season, episode: episode) { resolved = address }
            else { throw AnimePlaybackError.unavailable("No video providers are configured. Check that media-servers.json is included in the app resources.") }
            try Task.checkCancellation()
            url = resolved
            // Opening a provider is history, not proof that the provider's video played.
            library.record(media, season: season, episode: episode)
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
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
    var body: some View {
        NavigationStack {
            List {
                if !seasons.isEmpty {
                    Picker("Season", selection: $season) {
                        ForEach(seasons) { item in Text(item.name).tag(item.number) }
                    }.tint(AppTheme.accent)
                }
                if loading { ProgressView("Loading episodes…") }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(AppTheme.muted)
                        Button("Retry") { revision += 1 }
                    }
                }
                ForEach(episodes) { episode in
                    Button { select(season, episode.number) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(episode.number). \(episode.title)").foregroundStyle(.primary)
                                if !episode.overview.isEmpty { Text(episode.overview).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2) }
                            }
                            Spacer()
                            if selectedSeason == season && selectedEpisode == episode.number { Image(systemName: "play.fill").foregroundStyle(AppTheme.accent) }
                        }.frame(minHeight: 44)
                    }
                }
                if !loading && error == nil && episodes.isEmpty { Text("No episodes are available for this season.").foregroundStyle(AppTheme.muted) }
            }
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
        }.preferredColorScheme(.dark)
    }
}
