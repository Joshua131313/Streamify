import Foundation

/// Public catalogue candidates can be cached; the draw always uses the active
/// profile's current history and never relaxes the chosen genre or date range.
enum MoviePickPolicy {
    static let genres: [CatalogGenre] = [
        .init(id: 28, name: "Action"), .init(id: 12, name: "Adventure"),
        .init(id: 16, name: "Animation"), .init(id: 35, name: "Comedy"),
        .init(id: 80, name: "Crime"), .init(id: 99, name: "Documentary"),
        .init(id: 18, name: "Drama"), .init(id: 10751, name: "Family"),
        .init(id: 14, name: "Fantasy"), .init(id: 36, name: "History"),
        .init(id: 27, name: "Horror"), .init(id: 10402, name: "Music"),
        .init(id: 9648, name: "Mystery"), .init(id: 10749, name: "Romance"),
        .init(id: 878, name: "Science fiction"), .init(id: 53, name: "Thriller"),
        .init(id: 10752, name: "War"), .init(id: 37, name: "Western")
    ]

    static func dateString(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }

    static func parameters(genre: Int, now: Date) -> [String: String] {
        ["with_genres": String(genre), "primary_release_date.gte": "2000-01-01",
         "primary_release_date.lte": dateString(now), "vote_count.gte": "80",
         "vote_average.gte": "6", "sort_by": "popularity.desc"]
    }

    static func candidates(_ items: [MediaItem], genre: Int, history: [WatchEntry], now: Date) -> [MediaItem] {
        let watched = Set(history.map { $0.media.key })
        let today = dateString(now)
        var seen = Set<String>()
        return items.filter { item in
            let date = item.releaseDate
            guard item.kind == .movie, item.genreIDs.contains(genre), !watched.contains(item.key),
                  date.count == 10, date >= "2000-01-01", date <= today,
                  item.rating >= 6, item.posterURL != nil, !item.title.isEmpty else { return false }
            // Reject malformed/missing release dates as well as old re-releases.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else { return false }
            return seen.insert(item.key).inserted
        }
    }

    static func weight(_ item: MediaItem, history: [WatchEntry], recommended: Set<String>) -> Double {
        var affinity: [Int: Double] = [:]
        for (index, entry) in history.sorted(by: { $0.watchedAt > $1.watchedAt }).prefix(30).enumerated() {
            let genres = entry.media.genreIDs.flatMap { id -> [Int] in
                switch id { case 10759: return [28, 12]; case 10765: return [878, 14]; default: return [id] }
            }
            for genre in Set(genres) { affinity[genre, default: 0] += 1 / Double(index + 1) }
        }
        let similarity = item.genreIDs.reduce(0.0) { $0 + (affinity[$1] ?? 0) }
        return 1 + min(3, similarity) + (recommended.contains(item.key) ? 2 : 0) + max(0, item.rating - 6) * 0.15
    }

    /// A bounded weighted draw keeps exploration possible even with a long history.
    static func choose(_ items: [MediaItem], history: [WatchEntry], recommended: Set<String>,
                       excluding: Set<String>, unit: Double = Double.random(in: 0..<1)) -> MediaItem? {
        let remaining = items.filter { !excluding.contains($0.key) }
        guard !remaining.isEmpty else { return nil }
        let weights = remaining.map { weight($0, history: history, recommended: recommended) }
        var draw = min(max(unit.isFinite ? unit : 0, 0), Double(1).nextDown) * weights.reduce(0, +)
        for (item, weight) in zip(remaining, weights) {
            if draw < weight { return item }
            draw -= weight
        }
        return remaining.last
    }
}

struct MoviePickPool {
    let items: [MediaItem]
    let recommended: Set<String>
}

extension TMDBClient {
    func moviePickPool(genre: Int, history: [WatchEntry], now: Date = Date()) async throws -> MoviePickPool {
        let parameters = MoviePickPolicy.parameters(genre: genre, now: now)
        let first = try await catalog(path: "discover/movie", kind: .movie, parameters: parameters)
        try Task.checkCancellation()
        var items = first.items
        var recommended = Set<String>()
        if first.totalPages > 1 {
            let page = Int.random(in: 2...min(8, first.totalPages))
            if let extra = try? await catalog(path: "discover/movie", kind: .movie, page: page, parameters: parameters) {
                items += extra.items
            }
        }
        for entry in history.filter({ $0.media.kind == .movie }).sorted(by: { $0.watchedAt > $1.watchedAt }).prefix(2) {
            try Task.checkCancellation()
            if let page = try? await catalog(path: "movie/\(entry.media.id)/recommendations", kind: .movie) {
                items += page.items
                recommended.formUnion(page.items.map(\.key))
            }
        }
        try Task.checkCancellation()
        return MoviePickPool(items: MoviePickPolicy.candidates(items, genre: genre, history: history, now: now), recommended: recommended)
    }
}
