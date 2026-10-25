import Foundation
import SwiftUI

enum SportsLeague: String, CaseIterable, Identifiable, Codable, Sendable {
    case nfl
    case ncaaf = "college-football"
    case nba, wnba, nhl, mlb
    var id: String { rawValue }
    var title: String { self == .ncaaf ? "NCAAF" : rawValue.uppercased() }
    var sport: String {
        switch self { case .nfl, .ncaaf: return "football"; case .nba, .wnba: return "basketball"; case .nhl: return "hockey"; case .mlb: return "baseball" }
    }
    var category: String { self == .nfl || self == .ncaaf ? "american-football" : sport }
    var subtitle: String { self == .ncaaf ? "College football" : self == .nfl ? "American football" : sport.capitalized }
    var accent: Color {
        switch self { case .nfl: return Color(red: 0.71, green: 0.65, blue: 0.93)
        case .ncaaf: return Color(red: 0.35, green: 0.66, blue: 0.94)
        case .nba: return Color(red: 0.96, green: 0.64, blue: 0.36)
        case .wnba: return Color(red: 0.98, green: 0.53, blue: 0.45)
        case .nhl: return Color(red: 0.48, green: 0.78, blue: 0.95)
        case .mlb: return Color(red: 0.44, green: 0.79, blue: 0.65) }
    }
    var endpoint: String { "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(rawValue)" }
    /// ESPN's unfiltered college feed omits games; merge FBS and FCS explicitly.
    var scoreboardParameters: [String] { self == .ncaaf ? ["&groups=80&limit=1000", "&groups=81&limit=1000"] : ["&limit=100"] }
}

struct SportsTeam: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let abbreviation: String
    let logo: String
    var score = ""
    var record = ""
    var streamNames: [String] = []
    var logoURL: URL? { sportsHTTPSURL(logo) }
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
    var id: String { "\(league.rawValue):\(eventID)" }
    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
    var possessionTeam: SportsTeam? {
        guard isLive, let id = liveSituation?.possessionTeamID else { return nil }
        return [away, home].first { $0.id == id }
    }
    private var finalScores: (away: Double, home: Double)? {
        let detail = status.lowercased()
        guard isFinal, !["cancel", "postpon", "suspend", "no contest", "abandon"].contains(where: detail.contains),
              let awayScore = Double(away.score), let homeScore = Double(home.score),
              awayScore.isFinite, homeScore.isFinite, awayScore >= 0, homeScore >= 0 else { return nil }
        return (awayScore, homeScore)
    }
    var winner: SportsTeam? {
        guard let scores = finalScores, scores.away != scores.home else { return nil }
        return scores.away > scores.home ? away : home
    }
    var isTied: Bool { finalScores.map { $0.away == $0.home } ?? false }
    var resultLabel: String? {
        if let winner { return "\(winner.abbreviation.isEmpty ? winner.name : winner.abbreviation) won" }
        return isTied ? "Tied game" : nil
    }
    var canWatch: Bool {
        isLive || (state == "pre" && date.map { (0...3600).contains($0.timeIntervalSinceNow) } == true)
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
}

struct SportsGameCenter {
    let game: SportsGame
    let scoring: [SportsStatRow]
    let statistics: [SportsStatRow]
    let latest: String
}

struct SportsStream: Identifiable, Hashable {
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

func sportsHTTPSURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil else { return nil }
    return url
}

enum SportsServiceError: LocalizedError {
    case invalidURL, unavailable(Int), noSchedule, invalidResponse, streamsUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use a valid HTTPS address for the sports backend."
        case .unavailable(let status): return status == 429 ? "The sports service is busy. Wait a moment, then retry." : "The sports service is unavailable (HTTP \(status))."
        case .noSchedule: return "The schedule could not be loaded. Check your connection, then retry."
        case .invalidResponse: return "The sports service returned an unreadable response."
        case .streamsUnavailable: return "Stream sources could not be loaded. Try again shortly."
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
