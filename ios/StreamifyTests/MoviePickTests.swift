import XCTest
@testable import Streamify

final class MoviePickTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!
    private func movie(_ id: Int, date: String = "2024-05-20", genres: [Int] = [28, 878], kind: MediaKind = .movie) -> MediaItem {
        MediaItem(id: id, kind: kind, title: "Movie \(id)", posterPath: "/poster.jpg", rating: 8, releaseDate: date, genreIDs: genres)
    }
    func testNeverSuggestsOldFutureMissingOrMalformedReleaseDates() {
        let items = [movie(1, date: "1975-01-01"), movie(2, date: "1999-12-31"), movie(3, date: "2000-01-01"),
                     movie(4, date: "2027-01-01"), movie(5, date: ""), movie(6, date: "2025-02-30"), movie(7)]
        XCTAssertEqual(MoviePickPolicy.candidates(items, genre: 28, history: [], now: now).map(\.id), [3, 7])
    }
    func testRecommendationsCannotEscapeSelectedGenreOrReturnWatchedMovie() {
        let history = [WatchEntry(media: movie(1))]
        let pool = [movie(1), movie(2, genres: [35]), movie(3, kind: .tv), movie(4), movie(4)]
        XCTAssertEqual(MoviePickPolicy.candidates(pool, genre: 28, history: history, now: now).map(\.id), [4])
    }
    func testTheActiveProfilesHistoryControlsExclusions() {
        let items = [movie(1), movie(2)]
        XCTAssertEqual(MoviePickPolicy.candidates(items, genre: 28, history: [WatchEntry(media: movie(1))], now: now).map(\.id), [2])
        XCTAssertEqual(MoviePickPolicy.candidates(items, genre: 28, history: [WatchEntry(media: movie(2))], now: now).map(\.id), [1])
    }
    func testHistoryBoostsSimilarGenresWithoutEliminatingDiscovery() {
        let history = [WatchEntry(media: movie(1, genres: [878]))]
        let similar = movie(2, genres: [28, 878]), different = movie(3, genres: [28, 35])
        XCTAssertGreaterThan(MoviePickPolicy.weight(similar, history: history, recommended: []), MoviePickPolicy.weight(different, history: history, recommended: []))
        XCTAssertEqual(MoviePickPolicy.choose([similar, different], history: history, recommended: [], excluding: [], unit: 0)?.id, 2)
        XCTAssertEqual(MoviePickPolicy.choose([similar, different], history: history, recommended: [], excluding: [], unit: 1)?.id, 3)
    }
    func testRerollsDoNotRepeatAndExhaustionIsExplicit() {
        let items = [movie(1), movie(2)]
        XCTAssertEqual(MoviePickPolicy.choose(items, history: [], recommended: [], excluding: ["movie:1"], unit: 0)?.id, 2)
        XCTAssertNil(MoviePickPolicy.choose(items, history: [], recommended: [], excluding: ["movie:1", "movie:2"]))
        XCTAssertNotNil(MoviePickPolicy.choose(items, history: [], recommended: [], excluding: [], unit: .nan))
    }
    func testDiscoveryFiltersUseOriginalReleaseDateAndMinimumQuality() {
        let params = MoviePickPolicy.parameters(genre: 18, now: now)
        XCTAssertEqual(params["primary_release_date.gte"], "2000-01-01")
        XCTAssertEqual(params["primary_release_date.lte"], MoviePickPolicy.dateString(now))
        XCTAssertEqual(params["with_genres"], "18")
        XCTAssertEqual(params["vote_count.gte"], "80")
        XCTAssertEqual(params["vote_average.gte"], "6")
    }
}
