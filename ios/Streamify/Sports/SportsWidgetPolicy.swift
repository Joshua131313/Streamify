import Foundation

/// Shared contracts for the widget and the app, without shared storage or secrets.
enum SportsWidgetPolicy {
    static let kind = "StreamifyLiveGames"
    static let sportsURL = URL(string: "streamify://sports")!
    static let refreshInterval: TimeInterval = 10 * 60
    static let maximumAge: TimeInterval = 15 * 60

    static func watchURL(for game: SportsGame) -> URL? {
        guard validEventID(game.eventID) else { return nil }
        var components = URLComponents()
        components.scheme = "streamify"
        components.host = "sports"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "league", value: game.league.rawValue), URLQueryItem(name: "event", value: game.eventID)]
        return components.url
    }

    static func validEventID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func liveGames(_ games: [SportsGame], now: Date, calendar: Calendar) -> [SportsGame] {
        SportsScheduleDayPolicy.games(games, for: now, now: now, calendar: calendar)
            .filter { $0.isLive && validEventID($0.eventID) }
            .sorted {
                if $0.league != $1.league {
                    return (SportsLeague.allCases.firstIndex(of: $0.league) ?? 0) < (SportsLeague.allCases.firstIndex(of: $1.league) ?? 0)
                }
                return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture)
            }
    }

    /// The previous local day catches overnight live games. The current local
    /// day can cross a UTC boundary, so request every UTC date in that interval.
    static func scoreboardDates(now: Date, calendar: Calendar) -> [String] {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -1, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = "yyyyMMdd"
        var result: [String] = []
        var day = utc.startOfDay(for: first)
        while day < end {
            result.append(formatter.string(from: day))
            guard let next = utc.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Decode only the small set of fields used by a widget. Large ESPN play,
    /// athlete and broadcast trees never become retained dictionaries.
    static func parseScoreboard(_ data: Data, league: SportsLeague) throws -> [SportsGame] {
        let envelope = try JSONDecoder().decode(WidgetScoreboard.self, from: data)
        return (envelope.events ?? []).compactMap { event in
            guard let eventID = event.id?.text, validEventID(eventID),
                  let competition = event.competitions?.first,
                  let home = competition.competitors?.first(where: { $0.homeAway == "home" })?.teamValue,
                  let away = competition.competitors?.first(where: { $0.homeAway == "away" })?.teamValue else { return nil }
            let status = (competition.status ?? event.status)?.type
            return SportsGame(eventID: eventID, league: league,
                date: (event.date ?? competition.date).flatMap(SportsService.parseDate), state: status?.state ?? "",
                status: status?.shortDetail ?? status?.description ?? "", home: home, away: away,
                venue: "", broadcasts: "", link: "")
        }
    }
}

private struct WidgetScoreboard: Decodable { let events: [WidgetScoreEvent]? }
private struct WidgetScoreEvent: Decodable {
    let id: WidgetScoreText?
    let date: String?
    let status: WidgetScoreStatus?
    let competitions: [WidgetScoreCompetition]?
}
private struct WidgetScoreCompetition: Decodable {
    let date: String?
    let status: WidgetScoreStatus?
    let competitors: [WidgetScoreCompetitor]?
}
private struct WidgetScoreStatus: Decodable {
    let type: State?
    struct State: Decodable { let state: String?; let shortDetail: String?; let description: String? }
}
private struct WidgetScoreCompetitor: Decodable {
    let homeAway: String?
    let score: WidgetScoreText?
    let team: Team?
    struct Team: Decodable {
        let id: WidgetScoreText?
        let displayName: String?
        let abbreviation: String?
        let logo: String?
        let logos: [Logo]?
        struct Logo: Decodable { let href: String? }
    }
    var teamValue: SportsTeam? {
        guard let team, let id = team.id?.text, !id.isEmpty,
              let name = team.displayName, !name.isEmpty else { return nil }
        return SportsTeam(id: id, name: name, abbreviation: team.abbreviation ?? "",
            logo: team.logo ?? team.logos?.first?.href ?? "", score: score?.text ?? "")
    }
}
private struct WidgetScoreText: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) { text = string }
        else if let number = try? value.decode(Int.self) { text = String(number) }
        else if let object = try? value.decode([String: String].self), let display = object["displayValue"] { text = display }
        else { text = "" }
    }
}
