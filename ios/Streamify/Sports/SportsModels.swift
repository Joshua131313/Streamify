import Foundation
import SwiftUI
import ActivityKit

enum SportsLeague: String, CaseIterable, Identifiable, Codable, Sendable {
    case nhl, nba, wnba, nfl
    case ncaaf = "college-football"
    case tennis, mlb
    var id: String { rawValue }
    var title: String { self == .tennis ? "Tennis" : self == .ncaaf ? "NCAAF" : rawValue.uppercased() }
    var sport: String {
        switch self { case .nfl, .ncaaf: return "football"; case .nba, .wnba: return "basketball"; case .nhl: return "hockey"; case .mlb: return "baseball"; case .tennis: return "tennis" }
    }
    var category: String { self == .nfl || self == .ncaaf ? "american-football" : sport }
    var subtitle: String { self == .ncaaf ? "College football" : self == .nfl ? "American football" : sport.capitalized }
    var accent: Color {
        switch self { case .nfl: return Color(red: 0.71, green: 0.65, blue: 0.93)
        case .ncaaf: return Color(red: 0.35, green: 0.66, blue: 0.94)
        case .nba: return Color(red: 0.96, green: 0.64, blue: 0.36)
        case .wnba: return Color(red: 0.98, green: 0.53, blue: 0.45)
        case .nhl: return Color(red: 0.48, green: 0.78, blue: 0.95)
        case .mlb: return Color(red: 0.44, green: 0.79, blue: 0.65)
        case .tennis: return Color(red: 0.70, green: 0.82, blue: 0.38) }
    }
    var endpoint: String { "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(rawValue)" }
    /// ESPN's unfiltered college feed omits games; merge FBS and FCS explicitly.
    var scoreboardParameters: [String] { self == .ncaaf ? ["&groups=80&limit=1000", "&groups=81&limit=1000"] : ["&limit=100"] }
}

enum SportsTennisTour: String, CaseIterable, Hashable, Sendable {
    case atp = "ATP", wta = "WTA", challenger = "Challenger", other = "Other tennis"
}

/// Tournament and per-match scoring are separate from team-sport periods.
/// Missing point/serve data stays absent rather than being inferred from a score.
struct SportsTennisMatch: Hashable, Sendable {
    let tour: SportsTennisTour
    let tournament: String
    let tournamentID: String
    var discipline = "Singles"
    var round = ""
    var awaySets: [String] = []
    var homeSets: [String] = []
    var awayPoint: String? = nil
    var homePoint: String? = nil
    var servingID: String? = nil
    var winnerID: String? = nil
    var source = "espn"
    var competitionID = ""
    var timeConfirmed = true
    var historyURL: String? = nil
    var groupID: String { "\(tour.rawValue):\(tournamentID):\(discipline)" }
    var isDoubles: Bool { discipline.localizedCaseInsensitiveContains("doubles") }
}

struct SportsTeam: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let abbreviation: String
    let logo: String
    var score = ""
    var record = ""
    var streamNames: [String] = []
    var portrait: String? = nil
    var primaryColorHex: String? = nil
    var logoURL: URL? { sportsHTTPSURL(logo) }
    var tennisDisplayName: String {
        let seed = record.replacingOccurrences(of: "Seed ", with: "")
        return Int(seed).map { "\(name) (\($0))" } ?? name
    }
    func key(in league: SportsLeague) -> String { "\(league.rawValue):\(id)" }
}

/// A snapshot from the live feed, never inferred from the most recent scorer.
/// Football progress runs from the offense's own goal (0) to its opponent's (1).
/// It describes field position, not an inferred left/right stadium direction.
struct SportsLiveSituation: Hashable, Sendable {
    var period: Int? = nil
    var clock: String? = nil
    var possessionTeamID: String? = nil
    var downDistance: String? = nil
    var fieldPosition: String? = nil
    var fieldProgress: Double? = nil
    var baseball: SportsBaseballSituation? = nil
    var hockey: SportsHockeySituation? = nil
}

struct SportsHockeySituation: Hashable, Sendable {
    let awaySkaters: Int
    let homeSkaters: Int
    let powerPlayTeamID: String?
    let emptyNetTeamIDs: Set<String>
    let strengthTime: String?
    let observedAt: Date
}

/// Stable card ends: the away team advances right; the home team advances left.
/// The feed's offense-relative distance stays the same when the field is mirrored.
struct SportsFootballFieldPosition {
    let progress: Double
    let advancesRight: Bool
    var ballPosition: Double { advancesRight ? progress : 1 - progress }
    var fillStart: Double { advancesRight ? 0 : ballPosition }
}

enum SportsInningHalf: String, Hashable, Sendable {
    case top = "Top", bottom = "Bottom", middle = "Middle", end = "End"
}

struct SportsBaseballSituation: Hashable, Sendable {
    // Missing feed data is not an empty base. The UI must preserve that distinction.
    var firstOccupied: Bool? = nil
    var secondOccupied: Bool? = nil
    var thirdOccupied: Bool? = nil
    var balls: Int? = nil
    var strikes: Int? = nil
    var outs: Int? = nil
    var inning: Int? = nil
    var half: SportsInningHalf? = nil
    var hasBaseData: Bool { firstOccupied != nil || secondOccupied != nil || thirdOccupied != nil }
}

struct SportsGame: Identifiable, Hashable, Sendable {
    let eventID: String
    let league: SportsLeague
    let date: Date?
    let state: String
    let status: String
    let home: SportsTeam
    let away: SportsTeam
    let venue: String
    let broadcasts: String
    let link: String
    var liveSituation: SportsLiveSituation? = nil
    var tennis: SportsTennisMatch? = nil
    var id: String { "\(league.rawValue):\(eventID)" }
    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
    var possessionTeam: SportsTeam? {
        guard isLive, ["football", "basketball"].contains(league.sport),
              let id = liveSituation?.possessionTeamID else { return nil }
        return [away, home].first { $0.id == id }
    }
    var footballFieldPosition: SportsFootballFieldPosition? {
        guard league.sport == "football", let team = possessionTeam,
              let progress = liveSituation?.fieldProgress, progress.isFinite else { return nil }
        return SportsFootballFieldPosition(progress: min(1, max(0, progress)), advancesRight: team.id == away.id)
    }
    var hockeySummary: String? {
        guard isLive, league == .nhl, let hockey = liveSituation?.hockey else { return nil }
        let power = [away, home].first { $0.id == hockey.powerPlayTeamID }
        let empty = [away, home].filter { hockey.emptyNetTeamIDs.contains($0.id) }
        guard power != nil || !empty.isEmpty || hockey.awaySkaters != 5 || hockey.homeSkaters != 5 else { return nil }
        let first = power?.id == home.id ? hockey.homeSkaters : hockey.awaySkaters
        let second = power?.id == home.id ? hockey.awaySkaters : hockey.homeSkaters
        var pieces = ["\(first) on \(second)"]
        if let power { pieces.append("\(power.abbreviation) PP") }
        for team in empty { pieces.append("\(team.abbreviation) EN") }
        if let timer = hockey.strengthTime, power != nil { pieces.append(timer) }
        return pieces.joined(separator: " ")
    }
    private var finalScores: (away: Double, home: Double)? {
        let detail = status.lowercased()
        guard isFinal, !["cancel", "postpon", "suspend", "no contest", "abandon"].contains(where: detail.contains),
              let awayScore = Double(away.score), let homeScore = Double(home.score),
              awayScore.isFinite, homeScore.isFinite, awayScore >= 0, homeScore >= 0 else { return nil }
        return (awayScore, homeScore)
    }
    var winner: SportsTeam? {
        if let tennis { return isFinal ? [away, home].first { $0.id == tennis.winnerID } : nil }
        guard let scores = finalScores, scores.away != scores.home else { return nil }
        return scores.away > scores.home ? away : home
    }
    var isTied: Bool { finalScores.map { $0.away == $0.home } ?? false }
    var resultLabel: String? {
        if let winner { return "\(winner.abbreviation.isEmpty ? winner.name : winner.abbreviation) won" }
        return isTied ? "Tied game" : nil
    }
    var canWatch: Bool {
        isLive || (state == "pre" && tennis?.timeConfirmed != false && date.map { (0...3600).contains($0.timeIntervalSinceNow) } == true)
    }
}

struct SportsTrackedGameAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var awayScore: String
        var homeScore: String
        var status: String
        var situation: String?
        var updatedAt: Date
        var final: Bool
        var pregame: Bool? = nil
    }
    var league: String
    var eventID: String
    var away: String
    var home: String
    var awayID: String
    var homeID: String
    var awayName: String? = nil
    var homeName: String? = nil
    var awayRecord: String? = nil
    var homeRecord: String? = nil
    var venue: String? = nil
    var start: Date? = nil
    var awayPortrait: Data? = nil
    var homePortrait: Data? = nil
    var gameKey: String { "\(league):\(eventID)" }
    var watchURL: URL {
        var value = URLComponents()
        value.scheme = "streamify"; value.host = "sports"; value.path = "/watch"
        value.queryItems = [URLQueryItem(name: "league", value: league), URLQueryItem(name: "event", value: eventID)]
        return value.url ?? URL(string: "streamify://sports")!
    }
}

struct SportsSchedule: Sendable {
    let games: [SportsGame]
    let failedLeagues: [SportsLeague]
    let partial: Bool
}

struct SportsTeamResult: Identifiable, Hashable, Sendable {
    let league: SportsLeague
    let team: SportsTeam
    var id: String { team.key(in: league) }
}

struct SportsRosterPlayer: Identifiable {
    let id: String
    let name: String
    let number: String
    let position: String
    let height: String
    var photo: String = ""
    var photoURL: URL? { sportsHTTPSURL(photo) }
}

struct SportsTeamProfile {
    let team: SportsTeam
    let location: String
    let venue: String
    let games: [SportsGame]
    let roster: [SportsRosterPlayer]
    let scheduleUnavailable: Bool
    let rosterUnavailable: Bool
}

struct SportsStatRow: Identifiable {
    let id: String
    let label: String
    let away: String
    let home: String
    var period: Int? = nil
}

struct SportsGameCenter {
    let game: SportsGame
    let scoring: [SportsStatRow]
    let statistics: [SportsStatRow]
    let latest: String
    var playByPlay: [SportsPlayPeriod] = []
    var playerStats: [SportsPlayerStatGroup] = []
    var tennisHistory: [TennisHistorySet] = []
}

struct TennisHistorySet: Identifiable, Sendable {
    let number: Int
    let games: [TennisHistoryGame]
    var id: Int { number }
}

struct TennisHistoryGame: Identifiable, Sendable {
    let number: Int
    let score: String
    let server: String?
    let winner: String?
    let isBreak: Bool
    let points: [String]
    var id: Int { number }
}

struct SportsGamePlay: Identifiable {
    let id: String
    let period: Int
    let clock: String
    let text: String
    let awayScore: String
    let homeScore: String
    let teamID: String
    let scoring: Bool
}

struct SportsPlayPeriod: Identifiable {
    let number: Int
    let plays: [SportsGamePlay]
    var id: Int { number }
}

struct SportsPlayerStatLine: Identifiable {
    let id: String
    let name: String
    let number: String
    let position: String
    let photo: String
    let values: [String]
    let didNotPlay: Bool
}

struct SportsPlayerStatGroup: Identifiable {
    let id: String
    let teamID: String
    let title: String
    let labels: [String]
    let descriptions: [String]
    let players: [SportsPlayerStatLine]
}

extension SportsLeague {
    func periodTitle(_ period: Int) -> String {
        if self == .mlb { return "Inning \(period)" }
        let regulation = self == .nhl ? 3 : 4
        if period > regulation { return period == regulation + 1 ? "Overtime" : "Overtime \(period - regulation)" }
        return "\(self == .nhl ? "Period" : "Quarter") \(period)"
    }
}

struct SportsStream: Identifiable, Hashable, Sendable {
    let title: String
    let url: URL
    let alternatives: [SportsStream]
    private let stableID: String?
    var id: String { stableID ?? url.absoluteString }

    init(title: String, url: URL, alternatives: [SportsStream] = [], stableID: String? = nil) {
        self.title = title; self.url = url; self.stableID = stableID
        // Source choices have no nested choices of their own.
        self.alternatives = alternatives.map { SportsStream(title: $0.title, url: $0.url) }
    }

    var availableSources: [SportsStream] {
        var seen = Set<URL>()
        let current = alternatives.contains { $0.url == url } ? [] : [SportsStream(title: title, url: url)]
        return (current + alternatives).filter { sportsHTTPSURL($0.url.absoluteString) != nil && seen.insert($0.url).inserted }
    }
}

/// Remember a server's label, never an expiring event URL. When a channel name
/// changes between games, the same provider remains the preferred fallback.
enum SportsServerPreference {
    static func key(_ title: String) -> String {
        title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    static func source(in sources: [SportsStream], preference: String?) -> SportsStream? {
        guard let preference, !key(preference).isEmpty else { return sources.first }
        let saved = key(preference)
        if let exact = sources.first(where: { key($0.title) == saved }) { return exact }
        if saved.contains("·"), let provider = saved.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces),
           let sameProvider = sources.first(where: { $0.title.contains("·") && key($0.title).components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) == provider }) {
            return sameProvider
        }
        return sources.first
    }
}

func sportsHTTPSURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil else { return nil }
    return url
}

enum SportsServiceError: LocalizedError {
    case invalidURL, unavailable(Int), noSchedule, invalidResponse, streamsUnavailable, streamProviderUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use a valid HTTPS address for the sports backend."
        case .unavailable(let status): return status == 429 ? "The sports service is busy. Wait a moment, then retry." : "The sports service is unavailable (HTTP \(status))."
        case .noSchedule: return "The schedule could not be loaded. Check your connection, then retry."
        case .invalidResponse: return "The sports service returned an unreadable response."
        case .streamsUnavailable: return "Stream sources could not be loaded. Try again shortly."
        case .streamProviderUnavailable: return "The stream provider is currently unavailable. Live scores and schedules are still available. Try again later."
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func sportsText(_ key: String) -> String {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return ""
    }
    func sportsObject(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func sportsObjects(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}
