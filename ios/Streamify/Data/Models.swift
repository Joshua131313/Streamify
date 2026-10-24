import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case movie, tv, anime
    var id: String { rawValue }
    var title: String {
        switch self { case .movie: return "Movies"; case .tv: return "Shows"; case .anime: return "Anime" }
    }
    var singular: String {
        switch self { case .movie: return "Movie"; case .tv: return "Series"; case .anime: return "Anime" }
    }
}

struct MediaItem: Identifiable, Hashable, Codable {
    let id: Int
    var kind: MediaKind
    var title: String
    var overview: String
    var posterPath: String
    var backdropPath: String
    var rating: Double
    var releaseDate: String
    var genreIDs: [Int]

    init(id: Int, kind: MediaKind, title: String, overview: String = "", posterPath: String = "",
         backdropPath: String = "", rating: Double = 0, releaseDate: String = "", genreIDs: [Int] = []) {
        self.id = id; self.kind = kind; self.title = title; self.overview = overview
        self.posterPath = posterPath; self.backdropPath = backdropPath; self.rating = rating
        self.releaseDate = releaseDate; self.genreIDs = genreIDs
    }
    var key: String { "\(kind.rawValue):\(id)" }
    var year: String { String(releaseDate.prefix(4)) }
    var posterURL: URL? { catalogImageURL(posterPath.isEmpty ? backdropPath : posterPath) }
    var backdropURL: URL? { catalogImageURL(backdropPath.isEmpty ? posterPath : backdropPath, size: "w780") }
    /// Large hero surfaces need the full poster rather than an upscaled rail thumbnail.
    var heroPosterURL: URL? { catalogImageURL(posterPath.isEmpty ? backdropPath : posterPath, size: "original") }
    var heroBackdropURL: URL? { catalogImageURL(backdropPath.isEmpty ? posterPath : backdropPath, size: "original") }
}

func secureURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme?.lowercased() == "https",
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
    return url
}

func catalogImageURL(_ path: String, size: String = "w500") -> URL? {
    guard !path.isEmpty else { return nil }
    if path.hasPrefix("/") { return secureURL("https://image.tmdb.org/t/p/\(size)\(path)") }
    return secureURL(path)
}

struct MediaPage {
    let items: [MediaItem]
    let page: Int
    let totalPages: Int
}

struct CatalogGenre: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
}

struct MediaSeason: Identifiable, Hashable {
    let number: Int
    let name: String
    let count: Int
    var id: Int { number }
}

struct MediaEpisode: Identifiable, Hashable {
    let number: Int
    let title: String
    let overview: String
    let stillPath: String
    let runtime: Int
    let airDate: String
    var id: Int { number }
    var stillURL: URL? { catalogImageURL(stillPath, size: "w500") }

    init(number: Int, title: String, overview: String = "", stillPath: String = "", runtime: Int = 0, airDate: String = "") {
        self.number = number; self.title = title; self.overview = overview
        self.stillPath = stillPath; self.runtime = runtime; self.airDate = airDate
    }
}

struct CastMember: Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String
    var profileURL: URL? { catalogImageURL(profilePath, size: "w185") }
}

struct MediaDetails {
    let media: MediaItem
    let genres: [CatalogGenre]
    let runtime: String
    let seasons: [MediaSeason]
    let cast: [CastMember]
    let related: [MediaItem]
    let trailer: URL?
}

struct FilmCollection: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let backdrop: String
    let genres: [Int]
    let featured: Bool
    var assetName: String {
        "collection-" + URL(fileURLWithPath: backdrop).deletingPathExtension().lastPathComponent
    }
    init(id: Int, name: String, backdrop: String, genres: [Int] = [], featured: Bool = false) {
        self.id = id; self.name = name; self.backdrop = backdrop; self.genres = genres; self.featured = featured
    }
    private enum CodingKeys: String, CodingKey { case id, name, backdrop, genres, featured }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        backdrop = try c.decode(String.self, forKey: .backdrop)
        genres = try c.decodeIfPresent([Int].self, forKey: .genres) ?? []
        featured = try c.decodeIfPresent(Bool.self, forKey: .featured) ?? false
    }
    static var bundled: [FilmCollection] { bundledJSON("collections") ?? [] }
}

struct CollectionDetails {
    let overview: String
    let movies: [MediaItem]
}

struct PersonDetails {
    let name: String
    let profilePath: String
    let biography: String
    let birthday: String
    let birthplace: String
    let credits: [MediaItem]
    var profileURL: URL? { catalogImageURL(profilePath, size: "w342") }
}

struct AnimeIdentity {
    let malID: Int
    let names: [String]
}

struct MediaServer: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let movie: String
    let tv: String
    func url(media: MediaItem, season: Int = 1, episode: Int = 1) -> URL? {
        // AniList identities are not TMDB identities; never send them to movie/TV sources.
        guard media.kind != .anime else { return nil }
        let template = media.kind == .movie ? movie : tv
        return secureURL(template.replacingOccurrences(of: "{id}", with: String(media.id))
            .replacingOccurrences(of: "{season}", with: String(max(1, season)))
            .replacingOccurrences(of: "{episode}", with: String(max(1, episode))))
    }
    static var bundled: [MediaServer] { bundledJSON("media-servers") ?? [] }
}

private func bundledJSON<T: Decodable>(_ name: String) -> T? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

struct WatchEntry: Identifiable, Codable, Hashable {
    let media: MediaItem
    var season: Int = 1
    var episode: Int = 1
    var watchedAt: Date = Date()
    var positionSeconds: Double = 0
    var durationSeconds: Double = 0
    var id: String { media.key }
    var progress: Double { durationSeconds > 0 ? min(1, max(0, positionSeconds / durationSeconds)) : 0 }
    var completed: Bool { durationSeconds > 0 && progress >= 0.95 }
    var resumable: Bool { positionSeconds >= 5 && durationSeconds > 0 && !completed }
}
