import SwiftUI

struct MediaDetailView: View {
    let media: MediaItem
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var details: MediaDetails?
    @State private var error: String?
    @State private var loading = false
    @State private var revision = 0
    @State private var season = 1
    @State private var episodes: [MediaEpisode] = []
    @State private var episodeError: String?
    @State private var loadingEpisodes = false
    @State private var episodeRevision = 0
    @State private var selection: PlaybackSelection?
    @State private var selectedCast: CastMember?
    @State private var previewVisible = true
    @State private var pageVisible = false
    @State private var downloadPresented = false

    private var title: MediaItem { details?.media ?? media }
    private var previous: WatchEntry? { library.history.first { $0.media.key == media.key } }

    var body: some View {
        GeometryReader { viewport in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero
                    .background { GeometryReader { geometry in
                        Color.clear.preference(key: DetailHeroPositionKey.self, value: geometry.frame(in: .named("detail-scroll")))
                    } }
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(metadata).font(.subheadline).foregroundStyle(AppTheme.muted)
                        if let genres = details?.genres, !genres.isEmpty {
                            Text(genres.map(\.name).joined(separator: " · "))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                        }
                    }
                    VStack(spacing: 12) {
                        Button { play(season: previous?.season ?? season, episode: previous?.episode ?? 1) } label: {
                            Label(watchTitle, systemImage: "play.fill")
                                .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 50)
                        }
                        .buttonStyle(.plain).foregroundStyle(.black).background(.white, in: Capsule())
                        MediaDownloadButton(media: title, season: previous?.season ?? season, episode: previous?.episode ?? 1,
                            onPresentationChanged: { downloadPresented = $0 })
                        HStack(spacing: 12) {
                            Button { library.toggleSaved(title) } label: {
                                Label(library.isSaved(title) ? "Saved" : "My list", systemImage: library.isSaved(title) ? "checkmark" : "plus")
                                    .frame(maxWidth: .infinity).frame(minHeight: 48)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            if let trailer = details?.trailer {
                                Link(destination: trailer) {
                                    Label("Trailer", systemImage: "play.rectangle")
                                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    Text(title.overview.isEmpty ? "No synopsis available." : title.overview)
                        .font(.body).foregroundStyle(AppTheme.muted).textSelection(.enabled)
                }
                .padding(.horizontal, 20)

                if loading { ProgressView("Loading details…").frame(maxWidth: .infinity).padding() }
                if let error {
                    StateMessage(symbol: "wifi.exclamationmark", title: "Couldn’t load details", message: error, actionTitle: "Retry") { revision += 1 }
                        .padding(.horizontal, 20)
                }
                if media.kind != .movie { episodeSection }
                if let cast = details?.cast, !cast.isEmpty { castSection(cast) }
                if let related = details?.related, !related.isEmpty {
                    DetailMediaRail(title: "More like this", items: related)
                }
            }
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: "detail-scroll")
        .onPreferenceChange(DetailHeroPositionKey.self) { frame in
            let visible = max(0, min(frame.maxY, viewport.size.height) - max(0, frame.minY))
            previewVisible = frame.height > 0 && visible > frame.height / 2
        }
        }
        .background(AppTheme.canvas)
        .foregroundStyle(AppTheme.foreground)
        .accessibilityIdentifier("media-detail-page")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.canvas.opacity(0.9), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close details").accessibilityIdentifier("close-media-details")
            }
            ToolbarItem(placement: .principal) {
                Capsule().fill(AppTheme.muted.opacity(0.5)).frame(width: 34, height: 4).accessibilityHidden(true)
            }
        }
        .accessibilityAction(.escape) { dismiss() }
        .onAppear { pageVisible = true }
        .onDisappear { pageVisible = false }
        .task(id: "\(media.key):\(revision):\(settings.tmdbToken)") { await load() }
        .task(id: "\(media.key):\(season):\(episodeRevision):\(settings.tmdbToken)") { await loadEpisodes() }
        .fullScreenCover(item: $selection) { choice in
            MediaPlayerView(media: title, season: choice.season, episode: choice.episode)
        }
        .sheet(item: $selectedCast) { person in
            NavigationStack {
                PersonDetailView(id: person.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { selectedCast = nil } } }
            }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .presentationCornerRadius(24).presentationBackground(AppTheme.canvas)
        }
    }

    private var hero: some View {
        TrailerPreview(url: details?.trailer, poster: title.backdropURL,
            active: pageVisible && previewVisible && selection == nil && selectedCast == nil && !downloadPresented)
    }

    private var metadata: String {
        [title.year, title.kind.singular, title.rating > 0 ? "★ \(title.rating.formatted(.number.precision(.fractionLength(1))))" : "", details?.runtime ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var watchTitle: String {
        guard let previous, media.kind != .movie else { return "Watch" }
        return media.kind == .anime ? "Watch episode \(previous.episode)" : "Watch S\(previous.season) E\(previous.episode)"
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episodes").font(.title2.bold())
                Spacer()
                if let seasons = details?.seasons, !seasons.isEmpty {
                    Menu {
                        ForEach(seasons) { item in
                            Button { season = item.number } label: {
                                if season == item.number { Label(item.name, systemImage: "checkmark") }
                                else { Text(item.name) }
                            }
                        }
                    } label: {
                        StreamifySelectLabel(title: media.kind == .anime ? "All episodes" : "Season \(season)")
                    }.buttonStyle(.plain)
                }
            }
            if loadingEpisodes { ProgressView().frame(maxWidth: .infinity).padding() }
            if let episodeError {
                StateMessage(symbol: "exclamationmark.circle", title: "Episodes unavailable", message: episodeError, actionTitle: "Retry") { episodeRevision += 1 }
            }
            if !loadingEpisodes && episodeError == nil && episodes.isEmpty {
                Text("Episodes for this season will appear when available.").foregroundStyle(AppTheme.muted)
            }
            ForEach(episodes) { episode in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                    Button { play(season: season, episode: episode.number) } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RemoteArtwork(url: episode.stillURL ?? (media.kind == .anime ? title.backdropURL : nil))
                                    .frame(width: 128, height: 76).clipped()
                                Image(systemName: "play.fill").font(.body).foregroundStyle(.white)
                                    .padding(10).background(.black.opacity(0.6), in: Circle())
                            }.clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(episode.number). \(episode.title)").font(.subheadline.weight(.semibold)).lineLimit(3)
                                Text(episode.runtime > 0 ? "\(episode.runtime) min" : episode.airDate)
                                    .font(.caption).foregroundStyle(AppTheme.muted)
                                if previous?.season == season && previous?.episode == episode.number {
                                    Text("Last opened").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if media.kind == .tv {
                        MediaDownloadButton(media: title, season: season, episode: episode.number, episodeTitle: episode.title,
                            compact: true, onPresentationChanged: { downloadPresented = $0 })
                    }
                    }
                    if !episode.overview.isEmpty {
                        Text(episode.overview).font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(4)
                    }
                }
                if episode.number != episodes.last?.number { Divider().overlay(AppTheme.muted.opacity(0.1)) }
            }
        }.padding(.horizontal, 20)
    }

    private func castSection(_ cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The cast").font(.title2.bold()).padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cast) { person in
                        Button { selectedCast = person } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RemoteArtwork(url: person.profileURL).frame(width: 104, height: 136)
                                    .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(person.name).font(.caption.weight(.semibold)).lineLimit(2)
                                Text(person.character).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(2)
                            }.frame(width: 104, alignment: .leading)
                        }.buttonStyle(.plain).disabled(person.id <= 0).accessibilityIdentifier("cast-\(person.id)")
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        do {
            let value = try await settings.client.details(media)
            try Task.checkCancellation()
            details = value
            if season == 1, let previous, value.seasons.contains(where: { $0.number == previous.season }) { season = previous.season }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        if !Task.isCancelled { loading = false }
    }
    @MainActor private func loadEpisodes() async {
        guard media.kind != .movie else { return }
        loadingEpisodes = true; episodeError = nil; episodes = []
        do {
            let value = try await settings.client.episodes(media: media, season: season)
            try Task.checkCancellation(); episodes = value
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { episodeError = error.localizedDescription } }
        if !Task.isCancelled { loadingEpisodes = false }
    }
    private func play(season: Int, episode: Int) {
        selection = PlaybackSelection(season: season, episode: episode)
    }
}

private struct PlaybackSelection: Identifiable {
    let id = UUID()
    let season: Int
    let episode: Int
}

private struct DetailHeroPositionKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct DetailMediaRail: View {
    let title: String
    let items: [MediaItem]
    var body: some View {
        PosterRail(title: title, items: items)
    }
}

struct DetailPoster: View {
    let media: MediaItem
    var width: CGFloat = 112
    var body: some View {
        PosterContent(media: media).frame(width: width, alignment: .leading)
    }
}
