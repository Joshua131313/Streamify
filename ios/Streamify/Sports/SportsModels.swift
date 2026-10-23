import Foundation
import SwiftUI

enum SportsLeague: String, CaseIterable, Identifiable, Codable, Sendable {
    case nfl, nba, wnba, nhl, mlb
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var sport: String {
        switch self { case .nfl: return "football"; case .nba, .wnba: return "basketball"; case .nhl: return "hockey"; case .mlb: return "baseball" }
    }
    var category: String { self == .nfl ? "american-football" : sport }
    var subtitle: String { self == .nfl ? "American football" : sport.capitalized }
    var accent: Color {
        switch self { case .nfl: return Color(red: 0.71, green: 0.65, blue: 0.93)
        case .nba: return Color(red: 0.96, green: 0.64, blue: 0.36)
        case .wnba: return Color(red: 0.98, green: 0.53, blue: 0.45)
        case .nhl: return Color(red: 0.48, green: 0.78, blue: 0.95)
        case .mlb: return Color(red: 0.44, green: 0.79, blue: 0.65) }
    }
    var endpoint: String { "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(rawValue)" }
}

struct SportsTeam: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let abbreviation: String
    let logo: String
    var score = ""
    var record = ""
    var logoURL: URL? { sportsHTTPSURL(logo) }
    func key(in league: SportsLeague) -> String { "\(league.rawValue):\(id)" }
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
    var id: String { "\(league.rawValue):\(eventID)" }
    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
    var canWatch: Bool {
        isLive || (state == "pre" && date.map { (0...3600).contains($0.timeIntervalSinceNow) } == true)
    }
}

struct SportsSchedule: Sendable {
    let games: [SportsGame]
    let failedLeagues: [SportsLeague]
    let partial: Bool
}

struct SportsTeamResult: Identifiable, Hashable {
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
    var id: String { url.absoluteString }
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
