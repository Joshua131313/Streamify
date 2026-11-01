import SwiftUI

struct MoviePickShortcut: View {
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "shuffle").font(.title2).foregroundStyle(AppTheme.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick for me").font(.headline)
                    Text("Choose a genre. Find your next movie.").font(.caption).foregroundStyle(AppTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.headline)
            }.padding(18).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(HapticCardButtonStyle(cornerRadius: 16)).padding(.horizontal, 20)
            .accessibilityIdentifier("home-pick-for-me")
            .sheet(isPresented: $showing) { MoviePickView().streamifyPageSheet() }
    }
}

struct MoviePickView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var genre: CatalogGenre?
    @State private var pool: MoviePickPool?
    @State private var picked: MediaItem?
    @State private var shown = Set<String>()
    @State private var loading = false
    @State private var error: String?
    @State private var request: UUID?
    @State private var watching: MediaItem?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        if let picked {
                            result(picked, artworkHeight: min(360, max(180, geometry.size.height * 0.38)))
                                .id(picked.key).transition(.opacity)
                        } else {
                            genres.padding(.horizontal, 24).padding(.top, 76).padding(.bottom, 20)
                        }
                    }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("movie-pick-content")
                    if let picked {
                        actions(picked, wide: geometry.size.width >= 600)
                    } else {
                        VStack(spacing: 8) {
                            status
                            Button { request = UUID() } label: {
                                Label("Pick for me", systemImage: "shuffle").frame(maxWidth: .infinity)
                            }.buttonStyle(PrimaryButtonStyle()).disabled(genre == nil || loading)
                                .accessibilityIdentifier("movie-pick-draw")
                        }.padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(alignment: .top) { header }
                    .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
                    .accessibilityIdentifier("movie-pick-viewport")
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: request) { if request != nil { await draw() } }
        }.presentationDragIndicator(.visible).presentationDetents([.large])
            .fullScreenCover(item: $watching) { MediaPlayerView(media: $0) }
    }

    private var header: some View {
        HStack {
            Text("Pick for me").font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 40, height: 40)
                    .background(picked == nil ? AppTheme.controlFill : Color.black.opacity(0.35), in: Circle())
            }.buttonStyle(HapticCardButtonStyle(cornerRadius: 20)).accessibilityLabel("Done")
        }.padding(.horizontal, 24).frame(height: 60)
            .foregroundStyle(picked == nil ? AppTheme.foreground : .white)
            .background {
                if picked == nil { AppTheme.canvas }
                else { LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom) }
            }
    }

    private var genres: some View {
        VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What are you in the mood for?").font(.title2.bold())
                            Text("Movies from 2000 onward, with a little inspiration from your watch history. Already watched titles stay out.")
                                .font(.subheadline).foregroundStyle(AppTheme.muted)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                            ForEach(MoviePickPolicy.genres) { item in
                                Button {
                                    request = nil; loading = false; genre = item; pool = nil; shown = []; error = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(item.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        Spacer(minLength: 0)
                                        if genre == item { Image(systemName: "checkmark").font(.caption.bold()) }
                                    }.padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52)
                                        .foregroundStyle(genre == item ? AppTheme.canvas : AppTheme.foreground)
                                        .background(genre == item ? AppTheme.foreground : AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(HapticCardButtonStyle(cornerRadius: 12))
                                    .accessibilityAddTraits(genre == item ? .isSelected : [])
                                    .accessibilityIdentifier("movie-pick-genre-\(item.id)")
                            }
                        }
        }.frame(maxWidth: 712).frame(maxWidth: .infinity)
    }

    private func result(_ media: MediaItem, artworkHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteArtwork(url: media.backdropURL ?? media.posterURL, fallbackURLs: [media.posterURL].compactMap { $0 })
                .frame(height: artworkHeight).clipped()
                .overlay { LinearGradient(stops: [.init(color: .black.opacity(0.12), location: 0), .init(color: .clear, location: 0.35),
                    .init(color: AppTheme.canvas, location: 1)], startPoint: .top, endPoint: .bottom) }
            VStack(alignment: .leading, spacing: 8) {
                Text(genre?.name.uppercased() ?? "YOUR PICK").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(AppTheme.muted)
                Text(media.title).font(.title.bold()).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("movie-pick-result")
                Text("\(media.year) · ★ \(media.rating.formatted(.number.precision(.fractionLength(1))))").font(.subheadline).foregroundStyle(AppTheme.muted)
                Text(media.overview.isEmpty ? "Explore this movie for more details." : media.overview)
                    .font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(3, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("movie-pick-synopsis")
            }.padding(.horizontal, 24).padding(.top, -24).padding(.bottom, 12)
        }.frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private var status: some View {
        HStack(spacing: 8) {
            if loading { ProgressView().controlSize(.small) }
            Text(loading ? "Finding your movie…" : error ?? " ").font(.caption).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(AppTheme.muted).frame(height: 36)
            .accessibilityHidden(!loading && error == nil).accessibilityIdentifier("movie-pick-status")
    }

    private func actions(_ media: MediaItem, wide: Bool) -> some View {
        VStack(spacing: 10) {
            status
            HStack(spacing: 10) {
                Button { watching = media } label: { Label("Watch", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("movie-pick-watch")
                Button { library.toggleSaved(media) } label: {
                    Image(systemName: library.isSaved(media) ? "bookmark.fill" : "bookmark").frame(width: 48, height: 50)
                        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                }.buttonStyle(HapticCardButtonStyle(cornerRadius: AppTheme.buttonCornerRadius))
                    .accessibilityLabel(library.isSaved(media) ? "Saved for later" : "Save for later")
                    .accessibilityIdentifier("movie-pick-save")
                if wide { another }
            }
            if !wide { another }
            HStack(spacing: 12) {
                MediaDetailLink(media: media) {
                    Text("View movie").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }.accessibilityIdentifier("movie-pick-open")
                Button { request = nil; picked = nil; loading = false; error = nil } label: {
                    Text("Change genre").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 40)
                }.buttonStyle(HapticCardButtonStyle(cornerRadius: 12)).accessibilityIdentifier("movie-pick-change")
            }
        }.padding(.horizontal, 24).padding(.bottom, 12).frame(maxWidth: 760).frame(maxWidth: .infinity)
            .background(AppTheme.canvas).accessibilityElement(children: .contain).accessibilityIdentifier("movie-pick-actions")
    }

    private var another: some View {
        Button { request = UUID() } label: { Label("Pick another", systemImage: "shuffle").frame(maxWidth: .infinity) }
            .buttonStyle(SecondaryButtonStyle()).disabled(loading).accessibilityIdentifier("movie-pick-another")
    }

    @MainActor private func draw() async {
        guard let genre else { return }
        guard let currentRequest = request else { return }
        loading = true; error = nil
        defer { if request == currentRequest { loading = false } }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-cinematic-pick") { try await Task.sleep(for: .seconds(2)) }
            #endif
            let current: MoviePickPool
            if let pool { current = pool }
            else { current = try await settings.client.moviePickPool(genre: genre.id, history: library.history) }
            try Task.checkCancellation()
            guard request == currentRequest, self.genre?.id == genre.id else { return }
            pool = current
            guard let choice = MoviePickPolicy.choose(current.items, history: library.history, recommended: current.recommended, excluding: shown) else {
                error = "You’ve seen this batch. Choose another genre for more movies."
                return
            }
            shown.insert(choice.key)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { picked = choice }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = "Couldn’t find a movie just now. \(error.localizedDescription)" } }
    }
}
