import Foundation

/// Reads the provider's public schedule and advertised embed code only. Player
/// documents, protected APIs and media manifests are never prefetched here.
struct DaddyLiveProvider: Sendable {
    var session: URLSession = .shared
    private static let homepage = URL(string: "https://thedaddy.pk/")!

    struct Channel: Sendable, Equatable {
        let title: String
        let watchURL: URL
    }
    private struct Outcome: Sendable {
        let index: Int
        let url: URL?
        let failed: Bool
    }

    func streams(_ game: SportsGame) async throws -> [SportsStream] {
        try Task.checkCancellation()
        guard game.canWatch else { return [] }
        let home = try await document(Self.homepage, lifetime: 30)
        let channels = Array(Self.channels(in: home, game: game).prefix(12))
        guard !channels.isEmpty else { return [] }
        let fetch: @Sendable (Int) async throws -> Outcome = { index in
            do {
                try Task.checkCancellation()
                let html = try await self.document(channels[index].watchURL, lifetime: 0)
                try Task.checkCancellation()
                let url = Self.embedURL(in: html, relativeTo: channels[index].watchURL)
                return Outcome(index: index, url: url, failed: url == nil)
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .cancelled { throw error }
            catch { try Task.checkCancellation(); return Outcome(index: index, url: nil, failed: true) }
        }
        let outcomes = try await withThrowingTaskGroup(of: Outcome.self, returning: [Outcome].self) { group in
            var next = 0
            while next < min(4, channels.count) {
                let index = next
                group.addTask { try await fetch(index) }
                next += 1
            }
            var values: [Outcome] = []
            while let value = try await group.next() {
                values.append(value)
                if next < channels.count {
                    let index = next
                    group.addTask { try await fetch(index) }
                    next += 1
                }
            }
            return values.sorted { $0.index < $1.index }
        }
        try Task.checkCancellation()
        if outcomes.allSatisfy(\.failed) { throw SportsServiceError.streamsUnavailable }
        var seen = Set<URL>()
        return outcomes.compactMap { outcome in
            guard let url = outcome.url, seen.insert(url).inserted else { return nil }
            let channel = channels[outcome.index]
            return SportsStream(title: "DaddyLive · \(channel.title)", url: url,
                                stableID: "daddy:" + channel.watchURL.absoluteString)
        }
    }

    private func document(_ url: URL, lifetime: TimeInterval) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 8
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Streamify/1.1", forHTTPHeaderField: "User-Agent")
        let data = try await SportsSourceDocumentCache.shared.data(for: request, session: session, lifetime: lifetime)
        guard let html = String(data: data, encoding: .utf8) else { throw SportsServiceError.invalidResponse }
        return html
    }

    /// The sports-day label can precede its after-midnight UK game by one date.
    /// Select the closest matching occurrence, rather than another doubleheader.
    static func channels(in html: String, game: SportsGame, now: Date = Date()) -> [Channel] {
        guard let gameDate = game.date else { return [] }
        let root = DaddyHTML.document(html)
        var candidates: [(difference: TimeInterval, channels: [Channel])] = []
        for day in root.descendants(where: { $0.hasClass("schedule__day") }) {
            guard let heading = day.first(where: { $0.hasClass("schedule__dayTitle") }),
                  let date = scheduleDate(heading.text) else { continue }
            for event in day.descendants(where: { $0.hasClass("schedule__event") }) {
                guard let title = event.first(where: { $0.hasClass("schedule__eventTitle") })?.text,
                      let separator = title.firstIndex(of: ":"),
                      SportsSourceIdentity.leagueMatches(leagueLabel(String(title[..<separator])), game: game),
                      SportsSourceIdentity.teamsMatch(title, game: game),
                      let time = event.first(where: { $0.hasClass("schedule__time") }),
                      let start = eventDate(day: date, clock: time.attributes["data-time"] ?? time.text,
                                            game: game, now: now),
                      let links = event.first(where: { $0.hasClass("schedule__channels") }) else { continue }
                let channels = links.descendants(where: { $0.tag == "a" }).compactMap { anchor -> Channel? in
                    guard let href = anchor.attributes["href"], let url = watchURL(href) else { return nil }
                    let title = anchor.text.isEmpty ? (anchor.attributes["title"] ?? "") : anchor.text
                    guard !title.isEmpty else { return nil }
                    return Channel(title: title, watchURL: url)
                }
                if !channels.isEmpty { candidates.append((abs(start.timeIntervalSince(gameDate)), channels)) }
            }
        }
        guard let closest = candidates.map(\.difference).min() else { return [] }
        var seen = Set<URL>()
        return candidates.filter { $0.difference <= closest + 60 }.flatMap(\.channels)
            .filter { seen.insert($0.watchURL).inserted }
    }

    static func embedURL(in html: String, relativeTo watch: URL) -> URL? {
        let document = DaddyHTML.document(html)
        if let frame = document.first(where: { $0.tag == "iframe" && $0.attributes["id"] == "playerFrame" }),
           let src = frame.attributes["src"], let url = safeURL(src, relativeTo: watch) { return url }
        guard let code = document.first(where: { $0.tag == "textarea" && $0.attributes["id"] == "embedCode" }) else { return nil }
        // Both literal and HTML-escaped iframe markup occur in public embed fields.
        let frame = code.first(where: { $0.tag == "iframe" }) ?? DaddyHTML.document(code.text).first(where: { $0.tag == "iframe" })
        guard let src = frame?.attributes["src"] else { return nil }
        return safeURL(src, relativeTo: watch)
    }

    private static func watchURL(_ href: String) -> URL? {
        guard let url = safeURL(href, relativeTo: homepage), url.host?.lowercased() == homepage.host,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "/watch.php", parts.fragment == nil, parts.port == nil || parts.port == 443,
              let query = parts.queryItems, query.count == 1, query[0].name == "id",
              let id = query[0].value, id.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil else { return nil }
        return url
    }

    private static func safeURL(_ value: String, relativeTo base: URL) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value, relativeTo: base)?.absoluteURL,
              sportsHTTPSURL(url.absoluteString) != nil else { return nil }
        return url
    }

    private static func leagueLabel(_ prefix: String) -> String {
        let pattern = "(?i)\\b(WNBA|NBA|NCAAF|CFB|NFL|NHL|MLB)\\b"
        guard let range = prefix.range(of: pattern, options: .regularExpression) else { return prefix }
        return String(prefix[range])
    }

    private static func scheduleDate(_ heading: String) -> Date? {
        let pattern = #"\b([0-9]{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\s+([0-9]{4})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: heading, range: NSRange(heading.startIndex..., in: heading)) else { return nil }
        let text = heading as NSString
        let value = "\(text.substring(with: match.range(at: 1))) \(text.substring(with: match.range(at: 2))) \(text.substring(with: match.range(at: 3)))"
        for format in ["d MMM yyyy", "d MMMM yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format; formatter.isLenient = false
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func eventDate(day: Date, clock: String, game: SportsGame, now: Date) -> Date? {
        let clock = clock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clock.range(of: #"^(?:[01]?[0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else { return nil }
        let values = clock.split(separator: ":").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let first = calendar.date(bySettingHour: values[0], minute: values[1], second: 0, of: day),
              let following = calendar.date(byAdding: .day, value: 1, to: first), let gameDate = game.date else { return nil }
        return [first, following].filter { SportsSourceIdentity.sourceDateMatches($0, game: game, now: now) }
            .min { abs($0.timeIntervalSince(gameDate)) < abs($1.timeIntervalSince(gameDate)) }
    }
}

/// A bounded, non-executing HTML tree for the provider's published markup. No
/// WebKit HTML importer or protected scripts run during source discovery.
private final class DaddyHTML {
    private enum Content { case text(String), element(DaddyHTML) }
    private static let tagExpression = try? NSRegularExpression(pattern: #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9:-]*)\b(?:[^>"']|"[^"]*"|'[^']*')*>"#, options: [.dotMatchesLineSeparators])
    private static let attributeExpression = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
    private static let entityExpression = try? NSRegularExpression(pattern: #"&(#(?:[xX][0-9A-Fa-f]+|[0-9]+)|[A-Za-z][A-Za-z0-9]+);"#)
    private static let namedEntities = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ", "ndash": "–", "mdash": "—", "rsquo": "’", "lsquo": "‘", "eacute": "é", "Eacute": "É", "aacute": "á", "Aacute": "Á", "uuml": "ü", "Uuml": "Ü", "ntilde": "ñ", "Ntilde": "Ñ"]
    let tag: String
    let attributes: [String: String]
    private var contents: [Content] = []
    init(_ tag: String, attributes: [String: String] = [:]) { self.tag = tag; self.attributes = attributes }
    private var children: [DaddyHTML] { contents.compactMap { if case .element(let node) = $0 { return node }; return nil } }
    var text: String {
        var pending = Array(contents.reversed()), parts: [String] = []
        while let part = pending.popLast() {
            switch part { case .text(let text): parts.append(text); case .element(let node): pending.append(contentsOf: node.contents.reversed()) }
        }
        return Self.decode(parts.joined()).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    func hasClass(_ name: String) -> Bool { (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).contains(Substring(name)) }
    func descendants(where predicate: (DaddyHTML) -> Bool) -> [DaddyHTML] {
        var pending = [self], result: [DaddyHTML] = []
        while let node = pending.popLast() {
            if predicate(node) { result.append(node) }
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
    func first(where predicate: (DaddyHTML) -> Bool) -> DaddyHTML? {
        var pending = [self]
        while let node = pending.popLast() {
            if predicate(node) { return node }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    static func document(_ original: String) -> DaddyHTML {
        let root = DaddyHTML("root")
        guard original.utf8.count <= 2 * 1024 * 1024 else { return root }
        let html = original.replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script\s*>|<style\b[^>]*>.*?</style\s*>|<!--.*?-->"#, with: "", options: .regularExpression)
        guard let tags = tagExpression else { return root }
        let source = html as NSString
        var stack = [root], previous = 0
        let empty: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > previous { stack.last?.contents.append(.text(source.substring(with: NSRange(location: previous, length: match.range.location - previous)))) }
            previous = NSMaxRange(match.range)
            let tag = source.substring(with: match.range(at: 2)).lowercased()
            if match.range(at: 1).length > 0 {
                if let index = stack.lastIndex(where: { $0.tag == tag }), index > 0 { stack.removeSubrange(index...) }
                continue
            }
            let markup = source.substring(with: match.range)
            let node = DaddyHTML(tag, attributes: attributes(markup))
            stack.last?.contents.append(.element(node))
            if !empty.contains(tag), !markup.hasSuffix("/>"), stack.count < 128 { stack.append(node) }
        }
        if previous < source.length { stack.last?.contents.append(.text(source.substring(from: previous))) }
        return root
    }

    private static func attributes(_ markup: String) -> [String: String] {
        guard let expression = attributeExpression else { return [:] }
        let source = markup as NSString
        var result: [String: String] = [:]
        for match in expression.matches(in: markup, range: NSRange(location: 0, length: source.length)) {
            guard let value = (2...4).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            result[source.substring(with: match.range(at: 1)).lowercased()] = decode(source.substring(with: match.range(at: value)))
        }
        return result
    }

    private static func decode(_ source: String) -> String {
        guard source.contains("&"), let expression = entityExpression else { return source }
        let result = NSMutableString(string: source)
        for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            let entity = (source as NSString).substring(with: match.range(at: 1))
            let replacement: String?
            if entity.hasPrefix("#") {
                let hex = entity.lowercased().hasPrefix("#x")
                let digits = String(entity.dropFirst(hex ? 2 : 1))
                replacement = UInt32(digits, radix: hex ? 16 : 10).flatMap { UnicodeScalar($0) }.map { $0.value >= 32 ? String($0) : " " }
            } else { replacement = namedEntities[entity] }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }
}
