import SwiftUI

struct CollectionsView: View {
    @State private var search = ""
    @State private var genre = 0
    private let genres: [(Int, String)] = [(0, "All genres"), (28, "Action"), (12, "Adventure"), (18, "Drama"), (14, "Fantasy"), (878, "Science fiction"), (53, "Thriller")]
    private var collections: [FilmCollection] {
        FilmCollection.bundled.filter {
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (genre == 0 || $0.genres.contains(genre))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your next movie marathon.").font(.title.bold())
                Text("Explore familiar worlds, one collection at a time.").foregroundStyle(AppTheme.muted)
                Menu {
                    ForEach(genres, id: \.0) { id, name in
                        Button { genre = id } label: {
                            if genre == id { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                } label: {
                    Label(genres.first { $0.0 == genre }?.1 ?? "All genres", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                        .background(AppTheme.panel, in: Capsule())
                }.tint(.primary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 14)], spacing: 14) {
                    ForEach(collections) { collection in
                        NavigationLink { CollectionDetailView(collection: collection) } label: {
                            CollectionArtwork(collection: collection).frame(height: 180)
                        }.buttonStyle(.plain)
                    }
                }
                if collections.isEmpty {
                    StateMessage(symbol: "rectangle.stack", title: "No collections match", message: "Try another name or genre.", actionTitle: "Clear filters") { search = ""; genre = 0 }
                }
            }.padding(20)
        }
        .background(AppTheme.canvas)
        .navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a collection")
    }
}

struct CollectionArtwork: View {
    let collection: FilmCollection
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Image(collection.assetName).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(collection.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Label("Explore collection", systemImage: "arrow.right").font(.caption2).foregroundStyle(.white.opacity(0.75))
                }.foregroundStyle(.white).padding(16)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct CollectionDetailView: View {
    let collection: FilmCollection
    @EnvironmentObject private var settings: SettingsStore
    @State private var details: CollectionDetails?
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CollectionArtwork(collection: collection).frame(height: 230)
                if let details {
                    Text("\(details.movies.count) movies · Release order").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    if !details.overview.isEmpty { Text(details.overview).foregroundStyle(AppTheme.muted) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 14)], alignment: .leading, spacing: 24) {
                        ForEach(details.movies, id: \.key) { media in
                            NavigationLink { MediaDetailView(media: media) } label: { ExplorePoster(media: media) }.buttonStyle(.plain)
                        }
                    }
                    if details.movies.isEmpty {
                        StateMessage(symbol: "film", title: "No movies yet", message: "Released movies will appear when available in the catalog.")
                    }
                }
                if loading { ProgressView("Loading collection…").frame(maxWidth: .infinity).padding() }
                if let error {
                    StateMessage(symbol: "wifi.exclamationmark", title: "Collection unavailable", message: error, actionTitle: "Retry") { revision += 1 }
                }
            }.padding(20)
        }
        .background(AppTheme.canvas).navigationTitle(collection.name).navigationBarTitleDisplayMode(.inline)
        .task(id: "\(collection.id):\(revision):\(settings.tmdbToken)") {
            loading = true; error = nil
            do {
                let value = try await settings.client.collection(id: collection.id)
                try Task.checkCancellation(); details = value
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}

private struct ExplorePoster: View {
    let media: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(2 / 3, contentMode: .fit)
                .overlay { RemoteArtwork(url: media.posterURL) }.clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text([media.year, media.kind.singular].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
    }
}

struct PersonDetailView: View {
    let id: Int
    @EnvironmentObject private var settings: SettingsStore
    @State private var person: PersonDetails?
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0
    @State private var expanded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let person {
                    VStack(alignment: .leading, spacing: 20) {
                        RemoteArtwork(url: person.profileURL).frame(width: 160, height: 220)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                        Text(person.name).font(.largeTitle.bold())
                        let facts = [person.birthday, person.birthplace].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !facts.isEmpty { Text(facts).font(.subheadline).foregroundStyle(AppTheme.accent) }
                        Text(person.biography.isEmpty ? "No biography available." : person.biography)
                            .foregroundStyle(AppTheme.muted).lineLimit(expanded ? nil : 12).textSelection(.enabled)
                        if !person.biography.isEmpty {
                            Button(expanded ? "Read less" : "Read more") { expanded.toggle() }.font(.subheadline.weight(.semibold)).tint(AppTheme.accent)
                        }
                    }.padding(.horizontal, 20)
                    if !person.credits.isEmpty { DetailMediaRail(title: "Known for", items: person.credits) }
                }
                if loading { ProgressView("Loading profile…").frame(maxWidth: .infinity).padding() }
                if let error {
                    StateMessage(symbol: "person.crop.rectangle", title: "Profile unavailable", message: error, actionTitle: "Retry") { revision += 1 }.padding(.horizontal, 20)
                }
            }.padding(.vertical, 24)
        }
        .background(AppTheme.canvas).navigationTitle("Cast profile").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(id):\(revision):\(settings.tmdbToken)") {
            loading = true; error = nil
            do {
                let value = try await settings.client.person(id: id)
                try Task.checkCancellation(); person = value
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}
