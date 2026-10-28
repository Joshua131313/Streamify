import Foundation
import CoreFoundation

/// Uses Matchora's documented public schedule/event API and its own embeds.
/// Channel addresses are never reconstructed, and the normal provider player
/// (including its controls and advertising) remains responsible for playback.
struct MatchoraProvider: Sendable {
    var session: URLSession = .shared
    var now: @Sendable () -> Date = { Date() }
    private static let origin = "https://matchora.to"

    func streams(_ game: SportsGame) async throws -> [SportsStream] {
        guard game.canWatch else { return [] }
        let catalog = try await object("\(Self.origin)/api/v1/schedule?watchable=1", cached: true)
        guard let events = catalog["events"] as? [[String: Any]] else { throw SportsServiceError.invalidResponse }
        let reference = now()
        let candidates = events.filter { Self.matches($0, game: game, now: reference) }
        guard let selected = candidates.min(by: {
            abs((Self.start($0) ?? .distantPast).timeIntervalSince(game.date ?? reference)) <
                abs((Self.start($1) ?? .distantPast).timeIntervalSince(game.date ?? reference))
        }), let id = selected["id"] as? String else { return [] }
        // The schedule may remain warm, but each Watch refreshes its exact event.
        let event = try await object("\(Self.origin)/api/v1/events/\(id)", cached: false)
        guard event["id"] as? String == id, Self.matches(event, game: game, now: now()) else {
            throw SportsServiceError.invalidResponse
        }
        try Task.checkCancellation()
        return Self.sources(event, game: game)
    }

    static func matches(_ event: [String: Any], game: SportsGame, now: Date) -> Bool {
        guard let id = event["id"] as? String, validEventID(id, tennis: game.league == .tennis), event["finished"] as? Bool != true,
              let home = event["home"] as? String, let away = event["away"] as? String,
              SportsSourceIdentity.teamsMatch("\(home) vs \(away)", game: game),
              let start = start(event) else { return false }
        if game.league == .tennis {
            guard let tennis = game.tennis, tennis.source == "espn", !tennis.competitionID.isEmpty,
                  id == "es\(tennis.competitionID)", event.sportsText("sport").lowercased() == "tennis" else { return false }
        } else if !SportsSourceIdentity.leagueMatches(event.sportsText("league"), game: game) { return false }
        return SportsSourceIdentity.sourceDateMatches(start, game: game, now: now)
    }

    static func sources(_ event: [String: Any], game: SportsGame) -> [SportsStream] {
        guard let eventID = event["id"] as? String, validEventID(eventID, tennis: game.league == .tennis) else { return [] }
        let channels = (event["channels"] as? [[String: Any]] ?? []).enumerated().compactMap { index, channel -> Channel? in
            guard channel["dead"] as? Bool != true, let id = channel["id"] as? String,
                  let raw = channel["embed_url"] as? String,
                  let url = embed(raw, kind: "channel", id: id) else { return nil }
            let language = channel.sportsText("lang").trimmingCharacters(in: .whitespacesAndNewlines)
            let english = ["english", "en", "eng"].contains(language.lowercased())
            let name = channel.sportsText("name").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return Channel(id: id, url: url, name: name.isEmpty ? "Channel \(index + 1)" : String(name.prefix(90)),
                language: language, english: english, playing: channel["playing"] as? Bool == true, index: index)
        }.sorted {
            if $0.english != $1.english { return $0.english }
            if $0.playing != $1.playing { return $0.playing }
            return $0.index < $1.index
        }
        var seen = Set<String>()
        var result: [SportsStream] = []
        for channel in channels where seen.insert(channel.id).inserted {
            let language = channel.english || channel.language.isEmpty || channel.language == "Other" ? "" : " · \(channel.language)"
            result.append(SportsStream(title: "Matchora · \(channel.name)\(language)", url: channel.url,
                stableID: "matchora:\(game.id):\(eventID):\(channel.id)"))
            if result.count == 10 { break }
        }
        let count = (event["channel_count"] as? NSNumber)?.intValue ?? 0
        if (!result.isEmpty || count > 0), let raw = event["embed_url"] as? String,
           let fallback = embed(raw, kind: "match", id: eventID) {
            result.append(SportsStream(title: "Matchora · Match player", url: fallback,
                stableID: "matchora:\(game.id):\(eventID):match"))
        }
        return result
    }

    /// Only exact first-party embed paths returned for this match/channel are
    /// usable. Do not trust another event ID, encoded traversal, credential URL,
    /// arbitrary host, or a request for a nonstandard network port.
    static func embed(_ raw: String, kind: String, id: String) -> URL? {
        guard ["match", "channel"].contains(kind), (kind == "match" ? (validID(id) || validEventID(id, tennis: true)) : validID(id)),
              let value = URLComponents(string: raw), value.scheme?.lowercased() == "https",
              value.host?.lowercased() == "matchora.to", value.user == nil, value.password == nil,
              value.port == nil || value.port == 443, value.query == nil, value.fragment == nil,
              value.percentEncodedPath == "/embed/\(kind)/\(id)" else { return nil }
        return value.url
    }

    private struct Channel {
        let id: String
        let url: URL
        let name: String
        let language: String
        let english: Bool
        let playing: Bool
        let index: Int
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 18 && id.utf8.allSatisfy { (48...57).contains($0) }
    }
    private static func validEventID(_ id: String, tennis: Bool) -> Bool {
        tennis ? (id.hasPrefix("es") && validID(String(id.dropFirst(2)))) : validID(id)
    }
    private static func start(_ event: [String: Any]) -> Date? {
        guard let seconds = event["kickoff"] as? NSNumber, CFGetTypeID(seconds) != CFBooleanGetTypeID(),
              seconds.doubleValue.isFinite, seconds.doubleValue > 0, seconds.doubleValue < 10_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }
    private func object(_ address: String, cached: Bool) async throws -> [String: Any] {
        guard let url = URL(string: address) else { throw SportsServiceError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Streamify/1.1", forHTTPHeaderField: "User-Agent")
        do {
            let data = try await SportsSourceDocumentCache.shared.data(for: request, session: session,
                lifetime: cached ? 30 : 0, validateJSON: true)
            try Task.checkCancellation()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SportsServiceError.invalidResponse
            }
            return object
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 3840 {
            throw SportsServiceError.streamProviderUnavailable
        }
    }
}
