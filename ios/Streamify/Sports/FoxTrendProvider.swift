import Foundation
import CoreFoundation

/// Follow the public schedule -> exact event -> advertised feed -> embed chain.
/// Advertising wrappers are never opened during discovery; only their published
/// player URLs are returned to the existing popup-blocking sports player.
struct FoxTrendProvider: Sendable {
    var session: URLSession = .shared
    var now: @Sendable () -> Date = { Date() }
    static let schedule = URL(string: "https://crackstreams.st/")!

    func streams(_ game: SportsGame) async throws -> [SportsStream] {
        guard game.league == .ncaaf, game.canWatch else { return [] }
        let html = try await document(Self.schedule, lifetime: 30)
        guard let path = try Self.eventPath(in: html, game: game, now: now()),
              let eventURL = URL(string: "https://crackstreams.st" + path) else { return [] }
        let event = try await document(eventURL, lifetime: 0)
        guard let watch = Self.watchPages(in: event, eventPath: path, game: game).first else { return [] }
        let player = try await document(watch, lifetime: 0)
        try Task.checkCancellation()
        return Self.embeds(in: player, eventPath: path, game: game)
    }

    private func document(_ url: URL, lifetime: TimeInterval) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 6
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Streamify/1.1", forHTTPHeaderField: "User-Agent")
        let data = try await SportsSourceDocumentCache.shared.data(for: request, session: session, lifetime: lifetime)
        guard let html = String(data: data, encoding: .utf8) else { throw SportsServiceError.invalidResponse }
        return html
    }

    static func eventPath(in html: String, game: SportsGame, now: Date) throws -> String? {
        guard game.league == .ncaaf, html.utf8.count <= 2 * 1024 * 1024, let start = game.date else { return nil }
        let pattern = #"(?is)<script\b(?=[^>]*\bid\s*=\s*["']searchIndex["'])(?=[^>]*\btype\s*=\s*["']application/json["'])[^>]*>(.*?)</script\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { throw SportsServiceError.invalidResponse }
        guard let rows = try JSONSerialization.jsonObject(with: Data(html[range].utf8)) as? [[String: Any]] else {
            throw SportsServiceError.invalidResponse
        }
        return rows.compactMap { row -> (String, TimeInterval)? in
            guard let number = row["w"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue > 0, number.doubleValue < 10_000_000_000_000,
                  let ended = row["e"] as? NSNumber, CFGetTypeID(ended) != CFBooleanGetTypeID(), ended.intValue == 0,
                  SportsSourceIdentity.leagueMatches(row.sportsText("g"), game: game),
                  teamsMatch(row.sportsText("t"), game: game),
                  let path = row["u"] as? String, validEventPath(path) else { return nil }
            let date = Date(timeIntervalSince1970: number.doubleValue / 1000)
            guard SportsSourceIdentity.sourceDateMatches(date, game: game, now: now) else { return nil }
            return (path, abs(date.timeIntervalSince(start)))
        }.min { $0.1 < $1.1 }?.0
    }

    static func watchPages(in html: String, eventPath: String, game: SportsGame) -> [URL] {
        guard validEventPath(eventPath), html.utf8.count <= 2 * 1024 * 1024 else { return [] }
        let root = DaddyHTML.document(html)
        guard let header = root.first(where: { $0.tag == "section" && $0.attributes["id"] == "evHead" }),
              let title = header.first(where: { $0.tag == "h1" })?.text, teamsMatch(title, game: game),
              let league = header.first(where: { $0.hasClass("eh-lg") })?.first(where: { $0.tag == "span" })?.text,
              SportsSourceIdentity.leagueMatches(league, game: game),
              root.first(where: { $0.hasClass("sl-done") }) == nil else { return [] }
        var seen = Set<URL>()
        return Array(root.descendants(where: { $0.tag == "a" && $0.hasClass("sl-row") }).compactMap { row in
            guard let url = watchURL(row.attributes["href"] ?? "", eventPath: eventPath), seen.insert(url).inserted else { return nil }
            return url
        }.prefix(8))
    }

    static func embeds(in html: String, eventPath: String, game: SportsGame) -> [SportsStream] {
        guard validEventPath(eventPath), html.utf8.count <= 2 * 1024 * 1024 else { return [] }
        let root = DaddyHTML.document(html)
        guard let title = root.first(where: { $0.tag == "h1" })?.text, teamsMatch(title, game: game) else { return [] }
        var seen = Set<URL>()
        return Array(root.descendants(where: { $0.tag == "a" && $0.hasClass("sr") }).compactMap { row in
            guard let href = row.attributes["href"],
                  let advertised = URL(string: href, relativeTo: URL(string: "https://fxtrend.st")!)?.absoluteURL,
                  watchURL(advertised.absoluteString, eventPath: eventPath) != nil,
                  let raw = row.attributes["data-e"], let embed = embedURL(raw),
                  let name = row.first(where: { $0.hasClass("sl") })?.text, !name.isEmpty, seen.insert(embed).inserted else { return nil }
            return SportsStream(title: "FoxTrend · " + String(name.prefix(80)), url: embed,
                stableID: "foxtrend:" + advertised.path)
        }.prefix(8))
    }

    private static func teamsMatch(_ title: String, game: SportsGame) -> Bool {
        let title = title.hasSuffix(" Live Stream") ? String(title.dropLast(" Live Stream".count)) : title
        return SportsSourceIdentity.teamsMatch(title, game: game)
    }

    private static func validEventPath(_ path: String) -> Bool {
        path.range(of: #"^/event/[a-z0-9][a-z0-9-]{0,200}$"#, options: .regularExpression) != nil
    }

    private static func watchURL(_ raw: String, eventPath: String) -> URL? {
        guard validEventPath(eventPath), let url = sportsHTTPSURL(raw),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.host == "fxtrend.st",
              parts.port == nil || parts.port == 443, parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.range(of: "^" + NSRegularExpression.escapedPattern(for: eventPath) + #"/main/[1-9][0-9]?$"#,
                  options: .regularExpression) != nil else { return nil }
        return url
    }

    private static func embedURL(_ raw: String) -> URL? {
        guard let url = sportsHTTPSURL(raw), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.host == "trendy48.site", parts.port == nil || parts.port == 443, parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.range(of: #"^/(?:embed/[A-Za-z0-9-]{1,160}|aura/[0-9]{1,18})$"#,
                  options: .regularExpression) != nil else { return nil }
        return url
    }
}
