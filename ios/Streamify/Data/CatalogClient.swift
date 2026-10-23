import Foundation

enum CatalogError: LocalizedError {
    case missingToken, invalidResponse, service(String), http(Int)
    var errorDescription: String? {
        switch self {
        case .missingToken: return "Add your TMDB API key or read access token in Settings to browse movies and shows."
        case .invalidResponse: return "The catalog returned an unreadable response. Please retry."
        case .service(let message): return message
        case .http(let status):
            switch status {
            case 401, 403: return "The catalog could not authorize this request. Check your TMDB key in Settings."
            case 404: return "This title is no longer available in the catalog."
            case 429: return "The catalog is busy. Please wait a moment and retry."
            default: return "The catalog could not respond (\(status)). Please retry."
            }
        }
    }
}

struct TMDBClient {
    let token: String
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token; self.session = session
    }

    func catalog(path: String, kind: MediaKind? = nil, page: Int = 1, query: String = "",
                 parameters: [String: String] = [:]) async throws -> MediaPage {
        if kind == .anime {
            return try await AnimeCatalogClient.shared.catalog(page: page, search: query,
                topRated: path.contains("top_rated"), genre: parameters["genre"])
        }
        var parameters = parameters
        parameters["page"] = String(max(1, min(500, page)))
        if !query.isEmpty { parameters["query"] = query }
        let json = try await request(path: path, parameters: parameters)
        return MediaPage(items: json.objects("results").compactMap { Self.media($0, kind: kind) },
                         page: max(1, json.integer("page")), totalPages: min(500, max(1, json.integer("total_pages"))))
    }

    func details(_ media: MediaItem) async throws -> MediaDetails {
        if media.kind == .anime { return try await AnimeCatalogClient.shared.details(id: media.id) }
        let json = try await request(path: "\(media.kind.rawValue)/\(media.id)",
                                     parameters: ["append_to_response": "credits,recommendations,videos"])
        let runtime = json.integer("runtime") > 0 ? json.integer("runtime") : (json["episode_run_time"] as? [Int])?.first ?? 0
        let trailer = json.object("videos").objects("results").first {
            $0.string("site") == "YouTube" && $0.string("type") == "Trailer"
        }?.string("key")
        let trailerURL = trailer.flatMap { key -> URL? in
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
            return secureURL("https://www.youtube.com/watch?v=\(key)")
        }
        return MediaDetails(media: Self.media(json, kind: media.kind) ?? media,
            genres: json.objects("genres").map { CatalogGenre(id: $0.integer("id"), name: $0.string("name")) },
            runtime: runtime > 0 ? "\(runtime) min" : "",
            seasons: json.objects("seasons").filter { $0.integer("season_number") > 0 }.map {
                MediaSeason(number: $0.integer("season_number"), name: $0.string("name"), count: $0.integer("episode_count"))
            }, cast: json.object("credits").objects("cast").prefix(20).map {
                CastMember(id: $0.integer("id"), name: $0.string("name"), character: $0.string("character"), profilePath: $0.string("profile_path"))
            }, related: json.object("recommendations").objects("results").compactMap { Self.media($0, kind: media.kind) }, trailer: trailerURL)
    }

    func episodes(media: MediaItem, season: Int) async throws -> [MediaEpisode] {
        if media.kind == .anime { return try await AnimeCatalogClient.shared.episodes(id: media.id) }
        guard media.kind == .tv else { return [] }
        return try await request(path: "tv/\(media.id)/season/\(max(0, season))").objects("episodes").map {
            MediaEpisode(number: $0.integer("episode_number"), title: $0.string("name"), overview: $0.string("overview"),
                         stillPath: $0.string("still_path"), runtime: $0.integer("runtime"), airDate: $0.string("air_date"))
        }
    }

    func genres(kind: MediaKind) async throws -> [CatalogGenre] {
        if kind == .anime { return [] }
        return try await request(path: "genre/\(kind.rawValue)/list").objects("genres").map {
            CatalogGenre(id: $0.integer("id"), name: $0.string("name"))
        }
    }

    func collection(id: Int) async throws -> CollectionDetails {
        let json = try await request(path: "collection/\(id)")
        return CollectionDetails(overview: json.string("overview"), movies: json.objects("parts")
            .compactMap { Self.media($0, kind: .movie) }.sorted {
                ($0.releaseDate.isEmpty ? "9999" : $0.releaseDate) < ($1.releaseDate.isEmpty ? "9999" : $1.releaseDate)
            })
    }

    func person(id: Int) async throws -> PersonDetails {
        let json = try await request(path: "person/\(id)", parameters: ["append_to_response": "combined_credits"])
        var seen = Set<String>()
        let credits = json.object("combined_credits").objects("cast").compactMap { Self.media($0) }
            .filter { seen.insert($0.key).inserted }.sorted { $0.rating > $1.rating }
        return PersonDetails(name: json.string("name"), profilePath: json.string("profile_path"),
            biography: json.string("biography"), birthday: json.string("birthday"), birthplace: json.string("place_of_birth"), credits: credits)
    }

    func animeIdentity(id: Int) async throws -> AnimeIdentity {
        try await AnimeCatalogClient.shared.identity(id: id)
    }

    private func request(path: String, parameters: [String: String] = [:]) async throws -> CatalogJSON {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { throw CatalogError.missingToken }
        guard !path.isEmpty, !path.contains(".."), !path.contains(":") else { throw CatalogError.invalidResponse }
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        var values = parameters.filter { !$0.value.isEmpty }
        values["language"] = "en-US"; values["include_adult"] = "false"
        let bearer = cleanToken.hasPrefix("eyJ")
        if !bearer { values["api_key"] = cleanToken }
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw CatalogError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bearer { request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization") }
        return try await catalogJSON(request, session: session)
    }

    static func media(_ json: CatalogJSON, kind: MediaKind? = nil) -> MediaItem? {
        guard let resolvedKind = kind ?? MediaKind(rawValue: json.string("media_type")), resolvedKind != .anime,
              json.integer("id") > 0 else { return nil }
        let title = json.string("title").isEmpty ? json.string("name") : json.string("title")
        guard !title.isEmpty else { return nil }
        let genreIDs = json["genre_ids"] as? [Int] ?? json.objects("genres").map { $0.integer("id") }
        return MediaItem(id: json.integer("id"), kind: resolvedKind, title: title, overview: json.string("overview"),
            posterPath: json.string("poster_path"), backdropPath: json.string("backdrop_path"), rating: json.decimal("vote_average"),
            releaseDate: json.string("release_date").isEmpty ? json.string("first_air_date") : json.string("release_date"), genreIDs: genreIDs)
    }
}

typealias CatalogJSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String { self[key] as? String ?? "" }
    func integer(_ key: String) -> Int { (self[key] as? NSNumber)?.intValue ?? Int(string(key)) ?? 0 }
    func decimal(_ key: String) -> Double { (self[key] as? NSNumber)?.doubleValue ?? 0 }
    func object(_ key: String) -> CatalogJSON { self[key] as? CatalogJSON ?? [:] }
    func objects(_ key: String) -> [CatalogJSON] { self[key] as? [CatalogJSON] ?? [] }
}

func catalogJSON(_ request: URLRequest, session: URLSession = .shared) async throws -> CatalogJSON {
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw CatalogError.http(http.statusCode) }
    guard let json = try JSONSerialization.jsonObject(with: data) as? CatalogJSON else { throw CatalogError.invalidResponse }
    return json
}

/// AniList IDs stay in a separate namespace from TMDB throughout the app.
actor AnimeCatalogClient {
    static let shared = AnimeCatalogClient()
    private let fields = "id idMal title { english romaji } description(asHtml:false) coverImage { large } bannerImage averageScore startDate { year month day } episodes status nextAiringEpisode { episode } duration genres trailer { id site }"
    private var cache: [String: (date: Date, value: CatalogJSON)] = [:]
    private var nextRequestAt = Date.distantPast

    func catalog(page: Int, search: String, topRated: Bool, genre: String?) async throws -> MediaPage {
        let sort = topRated ? "SCORE_DESC" : "POPULARITY_DESC"
        let query = "query($page:Int,$search:String,$genre:String){Page(page:$page,perPage:24){pageInfo{hasNextPage} media(type:ANIME,isAdult:false,search:$search,genre:$genre,sort:\(sort)){\(fields)}}}"
        let data = try await request(query: query, variables: ["page": max(1, page), "search": search.isEmpty ? NSNull() : search as Any,
            "genre": genre.map { $0 as Any } ?? NSNull()]).object("Page")
        let hasNext = data.object("pageInfo")["hasNextPage"] as? Bool ?? false
        return MediaPage(items: data.objects("media").compactMap(Self.media), page: max(1, page), totalPages: max(1, page) + (hasNext ? 1 : 0))
    }

    func details(id: Int) async throws -> MediaDetails {
        let json = try await title(id: id)
        guard let media = Self.media(json) else { throw CatalogError.invalidResponse }
        let genreNames = json["genres"] as? [String] ?? []
        let genres = genreNames.enumerated().map { CatalogGenre(id: $0.offset + 1, name: $0.element) }
        let trailer = json.object("trailer")
        let key = trailer.string("id")
        let trailerURL = trailer.string("site").lowercased() == "youtube" && !key.isEmpty && key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            ? secureURL("https://www.youtube.com/watch?v=\(key)") : nil
        let runtime = json.integer("duration")
        return MediaDetails(media: media, genres: genres, runtime: runtime > 0 ? "\(runtime) min" : "",
            seasons: [MediaSeason(number: 1, name: "Episodes", count: Self.episodeCount(json))], cast: [], related: [], trailer: trailerURL)
    }

    func episodes(id: Int) async throws -> [MediaEpisode] {
        let json = try await title(id: id)
        let count = Self.episodeCount(json)
        guard count > 0 else { return [] }
        return (1...count).map { MediaEpisode(number: $0, title: "Episode \($0)", runtime: json.integer("duration")) }
    }

    func identity(id: Int) async throws -> AnimeIdentity {
        let json = try await title(id: id)
        let names = json.object("title")
        return AnimeIdentity(malID: json.integer("idMal"), names: [names.string("english"), names.string("romaji")].filter { !$0.isEmpty })
    }

    private func title(id: Int) async throws -> CatalogJSON {
        try await request(query: "query($id:Int){Media(id:$id,type:ANIME,isAdult:false){\(fields)}}", variables: ["id": id]).object("Media")
    }

    private func request(query: String, variables: CatalogJSON) async throws -> CatalogJSON {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables], options: .sortedKeys)
        let cacheKey = body.base64EncodedString()
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.date) < 300 { return entry.value }
        let delay = max(0, nextRequestAt.timeIntervalSinceNow)
        nextRequestAt = max(Date(), nextRequestAt).addingTimeInterval(2.1)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!, timeoutInterval: 25)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let json = try await catalogJSON(request)
        guard json["errors"] == nil else { throw CatalogError.service("The anime catalog could not complete this request. Please retry.") }
        let data = json.object("data")
        guard !data.isEmpty else { throw CatalogError.invalidResponse }
        if cache.count >= 80 { cache.removeAll(keepingCapacity: true) }
        cache[cacheKey] = (Date(), data)
        return data
    }

    private static func media(_ json: CatalogJSON) -> MediaItem? {
        guard json.integer("id") > 0 else { return nil }
        let title = json.object("title")
        let name = title.string("english").isEmpty ? title.string("romaji") : title.string("english")
        let year = json.object("startDate").integer("year")
        return MediaItem(id: json.integer("id"), kind: .anime, title: name,
            overview: json.string("description").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
            posterPath: json.object("coverImage").string("large"), backdropPath: json.string("bannerImage"),
            rating: json.decimal("averageScore") / 10, releaseDate: year > 0 ? String(year) : "")
    }

    private static func episodeCount(_ json: CatalogJSON) -> Int {
        if json.string("status") == "NOT_YET_RELEASED" { return 0 }
        let next = json.object("nextAiringEpisode").integer("episode")
        return min(3000, max(0, next > 0 ? next - 1 : json.integer("episodes")))
    }
}
