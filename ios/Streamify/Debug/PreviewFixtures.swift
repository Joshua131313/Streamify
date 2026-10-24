#if DEBUG
import Foundation
import UIKit

/// Deterministic UI data; excluded from release builds.
enum PreviewFixtures {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--ui-fixtures")
    static let usesNativePiPVideo = enabled && ProcessInfo.processInfo.arguments.contains("--ui-native-pip-fixture")
    static let usesDownloadStatus = enabled && ProcessInfo.processInfo.arguments.contains("--ui-download-status-fixture")
    static let downloadStatusIDs: Set<UUID> = [143, 144].map {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!
    }.reduce(into: Set<UUID>()) { $0.insert($1) }
    static func nativePlayerURL(for url: URL) -> URL? {
        guard usesNativePiPVideo, url.scheme == "https", url.host == "fixture.streamify.test",
              ["/native-alpha.mp4", "/native-bravo.mp4"].contains(url.path) else { return nil }
        return Bundle.main.url(forResource: "offline-player", withExtension: "mp4")
    }
    static let token = "ui-fixture"
    static let defaults: UserDefaults = {
        let name = "com.streamify.app.ui-fixtures"
        let result = UserDefaults(suiteName: name)!
        result.removePersistentDomain(forName: name)
        return result
    }()
    static func install() {
        guard enabled else { return }
        URLProtocol.registerClass(FixtureURLProtocol.self)
        URLCache.shared.removeAllCachedResponses()
    }
    @MainActor private static var seeded = false
    @MainActor static func seedLibrary(_ store: LibraryStore) {
        guard enabled, !seeded else { return }
        seeded = true
        for item in [movie, show, anime] { if !store.isSaved(item) { store.toggleSaved(item) } }
        store.record(movie, positionSeconds: 900, durationSeconds: 7200)
        store.record(show, season: 1, episode: 1, positionSeconds: 300, durationSeconds: 2700)
        store.rememberSearch("Horizon")
    }
    @MainActor private static var seededDownloads = false
    @MainActor static func seedDownloads(_ store: DownloadStore) {
        guard enabled, !seededDownloads, let source = Bundle.main.url(forResource: "offline-player", withExtension: "mp4") else { return }
        do {
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
            let directory = try DownloadFiles.directory()
            let fileName = "\(id.uuidString).mp4"
            let destination = directory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
            let posterName = "\(id.uuidString)-artwork-00000000-0000-0000-0000-000000000043.jpg"
            let poster = UIImage(named: "collection-avengers")?.jpegData(compressionQuality: 0.8)
            if let poster { try poster.write(to: directory.appendingPathComponent(posterName), options: .atomic) }
            let size = (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            var item = DownloadItem(id: id, title: "Offline player fixture", source: nil, fileName: fileName,
                createdAt: Date(), status: .completed, bytesWritten: Int64(size), expectedBytes: Int64(size))
            item.quality = 720
            item.catalog = CatalogDownloadDescriptor(id: 900042, kind: movie.kind.rawValue, title: item.title, season: 1, episode: 1, episodeTitle: nil)
            item.catalogKey = "movie:900042"
            item.posterFileName = poster == nil ? nil : posterName
            UserDefaults.standard.removeObject(forKey: "streamify.ios.offlinePlayback.\(id.uuidString)")
            store.installCompletedFixture(item)
            var statuses: [DownloadItem] = []
            if usesDownloadStatus {
                // These are deterministic UI states, not fake network transfers.
                for (suffix, media) in [(143, movie), (144, show)] {
                    let statusID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
                    var status = DownloadItem(id: statusID, title: media.title, source: nil, fileName: nil,
                        createdAt: Date(), status: .downloading, bytesWritten: suffix == 143 ? 25_000_000 : 1_000_000,
                        expectedBytes: suffix == 143 ? 100_000_000 : 0)
                    status.catalog = CatalogDownloadDescriptor(id: media.id, kind: media.kind.rawValue, title: media.title,
                        season: 1, episode: 1, episodeTitle: media.kind == .tv ? "A Call After Midnight" : nil)
                    status.catalogKey = DownloadStore.catalogKey(media: media, season: 1, episode: 1)
                    let artworkName = "\(statusID.uuidString)-artwork-00000000-0000-0000-0000-000000000043.jpg"
                    if let poster { try poster.write(to: directory.appendingPathComponent(artworkName), options: .atomic); status.posterFileName = artworkName }
                    statuses.append(status)
                }
            }
            store.installDownloadStatusFixtures(statuses)
            seededDownloads = true
        } catch { assertionFailure("Offline UI fixture could not be prepared: \(error)") }
    }
    private static let synopsis = "An unexpected discovery brings unlikely friends together on a journey beyond the familiar. Every choice changes the story."
    static let movie = MediaItem(id: 42, kind: .movie, title: "The Last Horizon", overview: synopsis,
        posterPath: "/fixture-avengers.jpg", backdropPath: "/fixture-avengers.jpg", rating: 8.4, releaseDate: "2026-07-12", genreIDs: [28, 878])
    static let show = MediaItem(id: 43, kind: .tv, title: "Midnight Dispatch", overview: synopsis,
        posterPath: "/fixture-matrix.jpg", backdropPath: "/fixture-matrix.jpg", rating: 8.1, releaseDate: "2026-03-08", genreIDs: [18])
    static let anime = MediaItem(id: 44, kind: .anime, title: "Starlight Academy", overview: synopsis,
        posterPath: "https://image.tmdb.org/fixture-harry-potter.jpg", backdropPath: "https://image.tmdb.org/fixture-harry-potter.jpg", rating: 8.6, releaseDate: "2026", genreIDs: [])
    static let playerHTML = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;height:100%;background:#090909;color:#fff;font:16px -apple-system;display:grid;place-items:center}main{text-align:center}b{font-size:48px;color:#e91c39}small{color:#aaa}#playback-session{font-size:10px;color:#aaa}</style></head><body><main><b>▶</b><p>Streamify preview player</p><small>Local UI fixture · no external video loaded</small><p id="playback-session"></p></main><script>document.getElementById('playback-session').textContent='Playback session '+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);</script></body></html>
    """
    static func trailerHTML(token: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["token": token])
        let config = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;background:linear-gradient(135deg,#18131e,#39202e,#10151f);color:white;font:18px -apple-system}main{height:100%;display:grid;place-content:center;text-align:center}small{color:#b9b3bd;font-size:12px}</style></head><body><main><span>THE LAST HORIZON</span><small id="state">Trailer preview</small></main><script>
        const config=\(config);let wanted=false,muted=true,dead=false;
        function report(event,value){if(!dead)window.webkit.messageHandlers.trailer.postMessage({token:config.token,event:event,value:value});}
        window.streamifyTrailer={setWanted(value){wanted=value===true;document.getElementById('state').textContent=wanted?'Playing preview':'Preview paused';report('state',wanted?1:2);},setMuted(value){muted=value===true;report('muted',muted);},replay(){if(wanted)report('state',1);},destroy(){wanted=false;dead=true;}};
        setTimeout(()=>report('ready'),100);
        </script></body></html>
        """
    }
    private static func mediaJSON(_ item: MediaItem) -> [String: Any] {
        ["id": item.id, "media_type": item.kind.rawValue, "title": item.title, "name": item.title,
         "overview": item.overview, "poster_path": item.posterPath, "backdrop_path": item.backdropPath,
         "vote_average": item.rating, "release_date": item.releaseDate, "first_air_date": item.releaseDate,
         "genre_ids": item.genreIDs]
    }
    private static var movies: [[String: Any]] {
        [movie, MediaItem(id: 45, kind: .movie, title: "Beyond the City", overview: synopsis, posterPath: "/fixture-matrix.jpg", backdropPath: "/fixture-matrix.jpg", rating: 7.9, releaseDate: "2025-06-02", genreIDs: [18]),
         MediaItem(id: 46, kind: .movie, title: "Ocean of Stars", overview: synopsis, posterPath: "/fixture-pirates.jpg", backdropPath: "/fixture-pirates.jpg", rating: 8.2, releaseDate: "2024-04-21", genreIDs: [12])].map(mediaJSON)
    }
    private static var shows: [[String: Any]] {
        [show, MediaItem(id: 52, kind: .tv, title: "The Long Weekend", overview: synopsis, posterPath: "/fixture-harry-potter.jpg", backdropPath: "/fixture-harry-potter.jpg", rating: 7.7, releaseDate: "2025-09-02", genreIDs: [18]),
         MediaItem(id: 53, kind: .tv, title: "Northbound", overview: synopsis, posterPath: "/fixture-pirates.jpg", backdropPath: "/fixture-pirates.jpg", rating: 8.3, releaseDate: "2024-12-10", genreIDs: [18])].map(mediaJSON)
    }
    fileprivate static func response(_ request: URLRequest) -> (Int, String, Data) {
        guard let url = request.url else { return (404, "application/json", Data("{}".utf8)) }
        let host = url.host ?? "", path = url.path
        var value: Any = [String: Any]()
        if host == "image.tmdb.org" || host.contains("espncdn.com") {
            let asset = path.contains("matrix") ? "collection-matrix" : path.contains("pirates") ? "collection-pirates" : path.contains("harry") ? "collection-harry-potter" : "collection-avengers"
            if let data = UIImage(named: asset)?.jpegData(compressionQuality: 0.8) { return (200, "image/jpeg", data) }
            return (404, "image/jpeg", Data())
        } else if host == "api.themoviedb.org" {
            let pieces = path.split(separator: "/").map(String.init).filter { $0 != "3" }
            if pieces.first == "genre" { value = ["genres": [["id": 28, "name": "Action"], ["id": 18, "name": "Drama"], ["id": 878, "name": "Science fiction"]]] }
            else if pieces.first == "person" {
                value = ["name": "Alex Morgan", "profile_path": "/fixture-matrix.jpg", "biography": "Alex Morgan is an actor known for thoughtful performances in film and television. Their work spans adventure, drama, and science fiction.", "birthday": "1990-04-12", "place_of_birth": "Toronto, Canada", "combined_credits": ["cast": movies + shows]]
            } else if pieces.first == "collection" { value = ["overview": "Follow the complete adventure in release order.", "parts": movies] }
            else if pieces.contains("season") {
                value = ["episodes": (1...3).map { ["episode_number": $0, "name": ["A Call After Midnight", "The Missing Signal", "A New Horizon"][$0 - 1], "overview": synopsis, "still_path": "/fixture-matrix.jpg", "runtime": 45, "air_date": "2026-03-08"] as [String: Any] }]
            } else if pieces.count == 2, ["movie", "tv"].contains(pieces[0]), Int(pieces[1]) != nil {
                let list = pieces[0] == "movie" ? movies : shows
                var detail = list.first { ($0["id"] as? Int) == Int(pieces[1]) } ?? list[0]
                detail["runtime"] = pieces[0] == "movie" ? 120 : 45
                detail["episode_run_time"] = [45]
                detail["genres"] = [["id": 28, "name": "Action"], ["id": 18, "name": "Drama"]]
                detail["seasons"] = [["season_number": 1, "name": "Season 1", "episode_count": 3], ["season_number": 2, "name": "Season 2", "episode_count": 3]]
                detail["credits"] = ["cast": [["id": 91, "name": "Alex Morgan", "character": "Jordan", "profile_path": "/fixture-matrix.jpg"], ["id": 92, "name": "Taylor Lee", "character": "Sam", "profile_path": "/fixture-pirates.jpg"]]]
                detail["videos"] = ["results": [["site": "YouTube", "type": "Trailer", "key": "fixture0001"]]]
                detail["recommendations"] = ["results": list]
                value = detail
            } else {
                let kind = pieces.contains("tv") ? "tv" : pieces.contains("movie") ? "movie" : "all"
                value = ["page": 1, "total_pages": 1, "results": kind == "tv" ? shows : kind == "movie" ? movies : [movies[0], shows[0], movies[1], shows[1], movies[2]]]
            }
        } else if host == "graphql.anilist.co" {
            let body = requestBody(request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let query = body["query"] as? String ?? ""
            let item: [String: Any] = ["id": 44, "idMal": 444, "title": ["english": anime.title, "romaji": anime.title], "description": synopsis, "coverImage": ["large": anime.posterPath], "bannerImage": anime.backdropPath, "averageScore": 86, "startDate": ["year": 2026, "month": 4, "day": 1], "episodes": 3, "status": "FINISHED", "duration": 24, "genres": ["Adventure", "Fantasy"], "trailer": ["id": "fixture0001", "site": "youtube"]]
            let payload: [String: Any] = query.contains("Page(")
                ? ["Page": ["pageInfo": ["hasNextPage": false], "media": [item]] as [String: Any]] : ["Media": item]
            value = ["data": payload]
        } else if host == "site.api.espn.com" { value = sportsJSON(url) }
        else if host == "streamed.pk" {
            if path == "/api/matches/all" {
                value = ["basketball", "american-football", "hockey", "baseball"].map { category in
                    ["id": "fixture-\(category)", "category": category, "date": 1,
                     "title": "Boston Harbor at Toronto Towers",
                     "teams": ["home": ["name": "Toronto Towers"], "away": ["name": "Boston Harbor"]],
                     "sources": [["source": "alpha", "id": "fixturealpha"], ["source": "bravo", "id": "fixturebravo"]]] as [String: Any]
                }
            } else if path.hasPrefix("/api/stream/") {
                let source = path.contains("/bravo/") ? "bravo" : "alpha"
                let address = usesNativePiPVideo ? "https://fixture.streamify.test/native-\(source).mp4" : "https://fixture.streamify.test/\(source)"
                value = [["embedUrl": address, "streamNo": 1, "language": "English", "hd": true]]
            } else { value = [Any]() }
        }
        else if host == "enc-dec.app" { value = ["result": "fixturetoken"] }
        else if host == "api.github.com" { value = [Any]() }
        else if host == "vidlink.pro", path.hasPrefix("/api/") {
            // Exercise the real stream-only error without starting a background transfer.
            value = ["stream": ["type": "hls", "qualities": [String: Any]()]]
        } else { return (404, "application/json", Data("{\"error\":\"No UI fixture for this request\"}".utf8)) }
        return (200, "application/json", (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8))
    }
    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    private static func sportsJSON(_ url: URL) -> Any {
        let parts = url.path.split(separator: "/").map(String.init)
        let league = ["nba", "wnba", "nfl", "nhl", "mlb", "college-football"].first { parts.contains($0) } ?? "nba"
        func team(_ home: Bool) -> [String: Any] {
            ["id": home ? "200" : "100", "displayName": home ? "Toronto Towers" : "Boston Harbor", "abbreviation": home ? "TOR" : "BOS", "logo": "https://a.espncdn.com/fixture-logo.png", "logos": [["href": "https://a.espncdn.com/fixture-logo.png"]], "location": home ? "Toronto" : "Boston", "record": ["items": [["summary": "8-3"]]], "franchise": ["venue": ["fullName": "Streamify Arena"]]]
        }
        let today = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let date = ISO8601DateFormatter().string(from: today)
        func competitor(_ home: Bool) -> [String: Any] {
            let scores = home ? [28, 25, 26, 26] : [24, 23, 25, 26]
            return ["homeAway": home ? "home" : "away", "team": team(home), "score": home ? "105" : "98", "records": [["summary": "8-3"]], "linescores": scores.map { ["value": $0, "displayValue": String($0)] }]
        }
        let game: [String: Any] = ["id": "\(league)-fixture", "date": date, "competitions": [["date": date, "competitors": [competitor(false), competitor(true)], "status": ["type": ["state": "in", "shortDetail": "4th · 02:18", "description": "In Progress"]], "venue": ["fullName": "Streamify Arena"], "broadcasts": [["names": ["ESPN"]]]]]]
        let final: [String: Any] = ["id": "\(league)-final", "date": date, "competitions": [["date": date, "competitors": [competitor(false), competitor(true)], "status": ["type": ["state": "post", "shortDetail": "Final", "description": "Final"]], "venue": ["fullName": "Streamify Arena"], "broadcasts": [["names": ["ESPN"]]]]]]
        if parts.last == "scoreboard" || parts.last == "schedule" { return ["events": league == "nba" ? [game, final] : [game]] }
        if parts.last == "summary" {
            func stats(_ home: Bool) -> [String: Any] {
                ["team": team(home), "statistics": [["name": "fieldGoals", "label": "Field Goals", "displayValue": home ? "41-80" : "39-83"], ["name": "rebounds", "label": "Rebounds", "displayValue": home ? "46" : "41"]]]
            }
            let event = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "event" })?.value ?? ""
            return ["header": event.hasSuffix("-final") ? final : game, "boxscore": ["teams": [stats(false), stats(true)]], "plays": [["text": "Toronto takes the lead with a three point shot."]]]
        }
        if parts.last == "roster" {
            return ["athletes": [["items": [["id": "1", "displayName": "Jordan Hayes", "jersey": "7", "position": ["abbreviation": "G"], "displayHeight": "6' 3\""], ["id": "2", "displayName": "Sam Rivera", "jersey": "22", "position": ["abbreviation": "F"], "displayHeight": "6' 8\""]]]]]
        }
        if parts.last == "teams" { return ["sports": [["leagues": [["teams": [["team": team(false)], ["team": team(true)]]]]]]] }
        if parts.contains("teams") { return ["team": team(parts.last != "100")] }
        return [:]
    }
}

private final class FixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { PreviewFixtures.enabled }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, contentType, body) = PreviewFixtures.response(request)
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType, "Content-Length": String(body.count), "Cache-Control": "no-store"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
