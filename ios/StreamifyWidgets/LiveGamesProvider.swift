import Foundation
import WidgetKit
import UIKit
import ImageIO

enum LiveGamesState: Equatable, Sendable { case loading, current, partial, unavailable, stale }

struct LiveGamesEntry: TimelineEntry {
    let date: Date
    let updatedAt: Date?
    let games: [SportsGame]
    let liveCount: Int
    let logos: [String: Data]
    let state: LiveGamesState

    static func placeholder(at date: Date = Date()) -> Self {
        Self(date: date, updatedAt: nil, games: [], liveCount: 0, logos: [:], state: .loading)
    }
    func expired() -> Self {
        Self(date: date.addingTimeInterval(SportsWidgetPolicy.maximumAge), updatedAt: updatedAt,
            games: [], liveCount: 0, logos: [:], state: .stale)
    }
}

struct LiveGamesProvider: TimelineProvider {
    func placeholder(in context: Context) -> LiveGamesEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (LiveGamesEntry) -> Void) {
        if context.isPreview { completion(.placeholder()); return }
        Task { completion(await LiveGamesLoader.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveGamesEntry>) -> Void) {
        Task {
            let entry = await LiveGamesLoader.load()
            // The second entry stops old scores claiming to be live if iOS
            // defers the requested reload. Refresh scheduling belongs to iOS.
            completion(Timeline(entries: [entry, entry.expired()],
                policy: .after(entry.date.addingTimeInterval(SportsWidgetPolicy.refreshInterval))))
        }
    }
}

private enum LiveGamesLoader {
    private struct Request: Sendable { let league: SportsLeague; let url: URL }
    private enum FeedResult: Sendable { case loaded([SportsGame]); case failed; case deadline; case cancelled }
    private enum LogoResult: Sendable { case image(String, Data); case failed; case deadline; case cancelled }

    static func load() async -> LiveGamesEntry {
        let started = Date()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let dates = SportsWidgetPolicy.scoreboardDates(now: started, calendar: .current)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        let currentUTC = formatter.string(from: started)
        let priorUTC = formatter.string(from: started.addingTimeInterval(-24 * 3600))
        let priorityDates = [currentUTC, priorUTC].filter(dates.contains) + dates.filter { $0 != currentUTC && $0 != priorUTC }
        // Give every league a current feed before requesting another date or
        // college group. A slow/off-season league cannot monopolize the queue.
        let requests = priorityDates.flatMap { day in
            (0..<2).flatMap { parameterIndex in
                SportsLeague.allCases.compactMap { league -> Request? in
                    guard league.scoreboardParameters.indices.contains(parameterIndex) else { return nil }
                    let parameters = league.scoreboardParameters[parameterIndex]
                    guard let url = URL(string: "\(league.endpoint)/scoreboard?dates=\(day)\(parameters)") else { return nil }
                    return Request(league: league, url: url)
                }
            }
        }
        var games: [SportsGame] = []
        var successful = 0
        await withTaskGroup(of: FeedResult.self) { group in
            var next = 0, finished = 0
            for _ in 0..<min(2, requests.count) {
                let request = requests[next]; next += 1
                group.addTask { await feed(request, session: session) }
            }
            group.addTask {
                do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                catch { return .cancelled }
                return .deadline
            }
            for await result in group {
                switch result {
                case .deadline, .cancelled: group.cancelAll(); return
                case .loaded(let loaded): games += loaded; successful += 1
                case .failed: break
                }
                finished += 1
                if finished == requests.count { group.cancelAll(); return }
                if next < requests.count {
                    let request = requests[next]; next += 1
                    group.addTask { await feed(request, session: session) }
                }
            }
        }
        let live = SportsWidgetPolicy.liveGames(games, now: started, calendar: .current)
        let displayed = Array(live.prefix(4))
        let images = await loadLogos(displayed, session: session)
        let state: LiveGamesState = successful == 0 ? .unavailable : successful < requests.count ? .partial : .current
        let updated = Date()
        return LiveGamesEntry(date: updated, updatedAt: successful == 0 ? nil : updated,
            games: displayed, liveCount: live.count, logos: images, state: state)
    }

    private static func feed(_ request: Request, session: URLSession) async -> FeedResult {
        do {
            let data = try await read(request.url, session: session, maximumBytes: 1_500_000, images: false)
            return .loaded(try SportsWidgetPolicy.parseScoreboard(data, league: request.league))
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
    }

    private static func loadLogos(_ games: [SportsGame], session: URLSession) async -> [String: Data] {
        var seen = Set<String>()
        let addresses = games.flatMap { [$0.away.logo, $0.home.logo] }
            .filter { logoURL($0) != nil && seen.insert($0).inserted }
        guard !addresses.isEmpty else { return [:] }
        var result: [String: Data] = [:]
        await withTaskGroup(of: LogoResult.self) { group in
            var next = 0, finished = 0
            for _ in 0..<min(2, addresses.count) {
                let address = addresses[next]; next += 1
                group.addTask { await logo(address, session: session) }
            }
            group.addTask {
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return .cancelled }
                return .deadline
            }
            for await item in group {
                switch item {
                case .deadline, .cancelled: group.cancelAll(); return
                case .image(let key, let data): result[key] = data
                case .failed: break
                }
                finished += 1
                if finished == addresses.count { group.cancelAll(); return }
                if next < addresses.count {
                    let address = addresses[next]; next += 1
                    group.addTask { await logo(address, session: session) }
                }
            }
        }
        return result
    }

    private static func logo(_ address: String, session: URLSession) async -> LogoResult {
        guard let url = logoURL(address) else { return .failed }
        do {
            let data = try await read(url, session: session, maximumBytes: 128_000, images: true)
            guard let thumbnail = WidgetLogoImages.thumbnail(data) else { return .failed }
            return .image(address, thumbnail)
        } catch { return Task.isCancelled ? .cancelled : .failed }
    }

    private static func logoURL(_ value: String) -> URL? {
        guard let url = sportsHTTPSURL(value), let host = url.host?.lowercased(),
              host == "espncdn.com" || host.hasSuffix(".espncdn.com") else { return nil }
        return url
    }

    private static func read(_ url: URL, session: URLSession, maximumBytes: Int, images: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = images ? 2 : 2.5
        request.setValue(images ? "image/*" : "application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              let final = response.url, final.scheme == "https", final.user == nil, final.password == nil,
              response.expectedContentLength <= Int64(maximumBytes),
              (images ? logoURL(final.absoluteString) != nil && response.mimeType?.hasPrefix("image/") == true : final.host == "site.api.espn.com") else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
            if data.count.isMultiple(of: 4096) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return data
    }
}

enum WidgetLogoImages {
    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image).pngData()
    }
    static let brand: UIImage? = {
        guard let url = Bundle.main.url(forResource: "streamify-logo", withExtension: "png"),
              let data = try? Data(contentsOf: url), let small = thumbnail(data) else { return nil }
        return UIImage(data: small)
    }()
}
