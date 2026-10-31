import Foundation
import CoreFoundation

/// The provider's public API returns live variants. Its normal watch page uses
/// each returned pathname on its current official mirror; no tokens are added.
struct StreamFreeProvider: Sendable {
    var session: URLSession = .shared
    var now: @Sendable () -> Date = { Date() }
    private static let origin = "https://streamfree.top"
    private static let officialMirrors: Set<String> = ["streamfree.top", "strmfree.st"]

    func streams(_ game: SportsGame) async throws -> [SportsStream] {
        guard game.canWatch else { return [] }
        let catalog = try await object("\(Self.origin)/api/v1/streams", cached: true)
        guard let events = catalog["streams"] as? [[String: Any]] else { throw SportsServiceError.invalidResponse }
        let reference = now()
        let matches = events.filter { Self.matches($0, game: game, now: reference) }
        guard let selected = matches.min(by: {
            abs((Self.start($0) ?? .distantPast).timeIntervalSince(game.date ?? reference)) <
                abs((Self.start($1) ?? .distantPast).timeIntervalSince(game.date ?? reference))
        }) else { return [] }
        let key = selected.sportsText("stream_key")
        let category = selected.sportsText("category").lowercased()
        // The exact catalog key is validated before entering an API path.
        let response = try await object("\(Self.origin)/api/v1/sources/\(key)", cached: false)
        guard response["stream_key"] as? String == key, let values = response["sources"] as? [Any] else {
            throw SportsServiceError.invalidResponse
        }
        try Task.checkCancellation()
        var seen = Set<URL>()
        return values.compactMap { value in
            let raw = (value as? String) ?? ((value as? [String: Any])?["url"] as? String)
            guard let raw, let source = Self.normalSource(raw, key: key, category: category),
                  seen.insert(source.url).inserted else { return nil }
            let quality = source.quality.map { " · \($0)" } ?? ""
            return SportsStream(title: "StreamFree\(quality) · Source \(source.server)", url: source.url,
                stableID: "streamfree:\(game.id):\(source.url.path)")
        }
    }

    static func matches(_ item: [String: Any], game: SportsGame, now: Date) -> Bool {
        guard let key = item["stream_key"] as? String, validKey(key), item.sportsText("category").lowercased() == game.league.sport,
              SportsSourceIdentity.leagueMatches(item.sportsText("league"), game: game),
              SportsSourceIdentity.teamsMatch(item.sportsText("name"), game: game),
              let start = start(item) else { return false }
        return SportsSourceIdentity.sourceDateMatches(start, game: game, now: now)
    }

    private static func validKey(_ key: String) -> Bool {
        key.utf8.count <= 200 && key.range(of: "^[A-Za-z0-9][A-Za-z0-9-]*$", options: .regularExpression) != nil
    }

    private static func start(_ item: [String: Any]) -> Date? {
        guard let seconds = item["match_timestamp"] as? NSNumber,
              CFGetTypeID(seconds) != CFBooleanGetTypeID(), seconds.doubleValue.isFinite,
              seconds.doubleValue > 0, seconds.doubleValue < 10_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }

    struct Source {
        let url: URL
        let quality: String?
        let server: Int
    }

    /// Matches the visible first-party reloadPlayer() rule: use a returned embed
    /// pathname on streamfree.top. Query/fragment are not forwarded by that rule.
    /// Only the two mirrors published in strmfree.link/api/domains are accepted.
    static func normalSource(_ raw: String, key: String, category: String) -> Source? {
        guard validKey(key), ["basketball", "football", "baseball", "hockey"].contains(category),
              let components = URLComponents(string: raw), components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), officialMirrors.contains(host),
              components.user == nil, components.password == nil, components.port == nil || components.port == 443 else { return nil }
        let path = components.percentEncodedPath
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty, parts[1] == "embed", parts[2] == category,
              parts[3].hasPrefix(key) else { return nil }
        let suffix = String(parts[3].dropFirst(key.count)).lowercased()
        guard let range = suffix.range(of: "^(?:[0-9]{3,4}p|4k)?[2-5]?$", options: .regularExpression),
              range == (suffix.startIndex..<suffix.endIndex) else { return nil }
        let server = suffix.last.flatMap { Int(String($0)) }.flatMap { (2...5).contains($0) ? $0 : nil } ?? 1
        let quality = server == 1 ? suffix : String(suffix.dropLast())
        guard let url = URL(string: origin + path) else { return nil }
        return Source(url: url, quality: quality.isEmpty ? nil : quality, server: server)
    }

    private func object(_ value: String, cached: Bool) async throws -> [String: Any] {
        guard let url = URL(string: value) else { throw SportsServiceError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Streamify/1.1", forHTTPHeaderField: "User-Agent")
        let data = try await SportsSourceDocumentCache.shared.data(for: request, session: session, lifetime: cached ? 30 : 0)
        try Task.checkCancellation()
        return try Self.decode(data)
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        do {
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SportsServiceError.invalidResponse }
            return result
        } catch let error as SportsServiceError { throw error }
        catch {
            let prefix = String(decoding: data.prefix(256), as: UTF8.self).drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
            if prefix.hasPrefix("<") { throw SportsServiceError.streamProviderUnavailable }
            throw SportsServiceError.invalidResponse
        }
    }
}
