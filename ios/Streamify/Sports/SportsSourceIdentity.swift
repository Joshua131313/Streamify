import Foundation

/// Public provider titles must identify both opponents, the league and the game
/// date. A city fragment or a broadcaster name cannot stand in for a matchup.
enum SportsSourceIdentity {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
            .replacingOccurrences(of: "st. louis", with: "saint louis")
            .replacingOccurrences(of: "st louis", with: "saint louis")
            .replacingOccurrences(of: "\\bla\\b", with: "los angeles", options: .regularExpression)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func leagueMatches(_ label: String, game: SportsGame) -> Bool {
        let aliases: Set<String>
        switch game.league {
        case .nfl: aliases = ["nfl", "nationalfootballleague"]
        case .ncaaf: aliases = ["ncaaf", "cfb", "ncaafootball", "collegefootball", "ncaafbs", "ncaafcs"]
        case .nba: aliases = ["nba", "nationalbasketballassociation"]
        case .wnba: aliases = ["wnba", "womensnationalbasketballassociation"]
        case .nhl: aliases = ["nhl", "nationalhockeyleague", "nhlicehockey"]
        case .mlb: aliases = ["mlb", "majorleaguebaseball"]
        }
        return aliases.contains(normalized(label))
    }

    static func teamsMatch(_ title: String, game: SportsGame) -> Bool {
        let text = title.components(separatedBy: ":").last ?? title
        let sides = text.replacingOccurrences(of: "\\s+(?:vs\\.?|v\\.?|at|versus)\\s+|\\s*@\\s*",
            with: "\n", options: [.regularExpression, .caseInsensitive]).components(separatedBy: "\n")
        guard sides.count == 2 else { return false }
        func teamName(_ value: String) -> String {
            // College listings sometimes publish a school's formal prefix while
            // ESPN's location alias omits it. Only this anchored prefix is optional;
            // "State", "Tech" and the rest of each school's name stay significant.
            guard game.league == .ncaaf else { return normalized(value) }
            return normalized(value.replacingOccurrences(of: "^\\s*university\\s+of\\s+", with: "",
                options: [.regularExpression, .caseInsensitive]))
        }
        func aliases(_ team: SportsTeam) -> Set<String> {
            let full = teamName(team.name)
            return Set(([team.name] + team.streamNames).map(teamName).filter {
                !$0.isEmpty && (game.league == .ncaaf || $0 == full || full.hasSuffix($0))
            })
        }
        func names(_ side: String) -> Set<String> {
            let name = teamName(side)
            var result: Set<String> = [name]
            if game.league == .wnba, name.hasSuffix("w") { result.insert(String(name.dropLast())) }
            return result
        }
        let first = names(sides[0]), second = names(sides[1])
        guard !first.contains(""), !second.contains(""), first.isDisjoint(with: second) else { return false }
        let home = aliases(game.home), away = aliases(game.away)
        return (!first.isDisjoint(with: home) && !second.isDisjoint(with: away)) ||
            (!first.isDisjoint(with: away) && !second.isDisjoint(with: home))
    }

    static func sourceDateMatches(_ start: Date?, game: SportsGame, now: Date = Date()) -> Bool {
        guard let start, let date = game.date else { return false }
        return abs(start.timeIntervalSince(date)) <= 4 * 3600 && abs(start.timeIntervalSince(now)) <= 18 * 3600
    }
}

/// Source discovery has a strict deadline. Unlike shared catalog flights, these
/// requests stay owned by their caller so cancellation stops the network task.
actor SportsSourceDocumentCache {
    static let shared = SportsSourceDocumentCache()
    private struct Entry { let data: Data; let expires: Date; let touched: Date }
    private var entries: [String: Entry] = [:]

    func data(for request: URLRequest, session: URLSession, lifetime: TimeInterval, validateJSON: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        guard let url = request.url, sportsHTTPSURL(url.absoluteString) != nil else { throw SportsServiceError.invalidURL }
        let key = ResponseMemoryCache.key(for: request, session: session)
        let now = Date()
        entries = entries.filter { $0.value.expires > now }
        if let entry = entries[key], lifetime > 0 { return entry.data }
        var prepared = request
        prepared.timeoutInterval = min(8, request.timeoutInterval)
        prepared.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: prepared)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, let final = http.url,
              sportsHTTPSURL(final.absoluteString) != nil else { throw SportsServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw SportsServiceError.unavailable(http.statusCode) }
        guard data.count <= 2 * 1024 * 1024 else { throw SportsServiceError.invalidResponse }
        if validateJSON { try SportsService.validateJSONResponse(data, response: http, requestedURL: url) }
        if lifetime > 0 {
            let completed = Date()
            entries[key] = Entry(data: data, expires: completed.addingTimeInterval(lifetime), touched: completed)
            var bytes = entries.values.reduce(0) { $0 + $1.data.count }
            for oldKey in entries.sorted(by: { $0.value.touched < $1.value.touched }).map(\.key) {
                guard entries.count > 48 || bytes > 8 * 1024 * 1024 else { break }
                if let removed = entries.removeValue(forKey: oldKey) { bytes -= removed.data.count }
            }
        }
        return data
    }
}

struct SportsSourceProviderResult: Sendable {
    let provider: Int
    let streams: [SportsStream]
    let error: Error?
}

actor SportsLegacySourceAvailability {
    static let shared = SportsLegacySourceAvailability()
    private var retryAfter: [String: Date] = [:]

    func allows(_ key: String, now: Date = Date()) -> Bool {
        retryAfter = retryAfter.filter { $0.value > now }
        return retryAfter[key] == nil
    }

    func unavailable(_ key: String, now: Date = Date()) {
        retryAfter[key] = now.addingTimeInterval(30)
    }
}
