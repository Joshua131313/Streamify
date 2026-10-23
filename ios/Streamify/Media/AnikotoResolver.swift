import Foundation

enum AnimePlaybackError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}

struct AnimePlaybackSource: Identifiable {
    let server: String
    let language: String
    var id: String { "\(server)-\(language)" }
    var label: String {
        let name = ["323": "HD-1", "e54": "Vidstream-2", "1a7": "Vidstream-1"][server] ?? server
        return "\(name) · \(language.uppercased())"
    }
    static let all: [AnimePlaybackSource] = ["sub", "dub"].flatMap { language in
        ["323", "e54", "1a7"].map { AnimePlaybackSource(server: $0, language: language) }
    }
}

struct ResolvedAnimePlayback {
    let url: URL
    let referer: URL
}

/// Matches the AniList title's MAL identity before resolving an episode, just like Android.
actor AnikotoResolver {
    static let shared = AnikotoResolver()
    private struct Match { let path: String; let id: String; let malID: Int }
    private struct Episode { let number: Int; let malID: Int; let servers: String }
    private var matches: [Int: Match] = [:]
    private let base = "https://anikoto.cz"

    func resolve(media: MediaItem, episode: Int, source: AnimePlaybackSource, client: TMDBClient) async throws -> ResolvedAnimePlayback {
        guard media.kind == .anime, episode > 0, ["sub", "dub"].contains(source.language) else {
            throw AnimePlaybackError.unavailable("Choose an anime episode and source.")
        }
        let match = try await match(media: media, client: client)
        let list = try await episodeList(id: match.id)
        guard let selected = list.first(where: { $0.number == episode && $0.malID == match.malID }) else {
            throw AnimePlaybackError.unavailable("Episode \(episode) is not available on Anikoto yet.")
        }
        let html = try await result(path: "/ajax/server/list", query: ["servers": selected.servers]) as? String ?? ""
        guard let token = Self.serverToken(html, language: source.language, server: source.server) else {
            throw AnimePlaybackError.unavailable("This \(source.language.uppercased()) source is unavailable for episode \(episode). Choose another source.")
        }
        let response = try await result(path: "/ajax/server", query: ["get": token]) as? [String: Any]
        guard let value = response?["url"] as? String, var components = URLComponents(string: value), secureURL(value) != nil else {
            throw AnimePlaybackError.unavailable("The anime source returned an unsupported player address.")
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "autostart", value: "true")); components.queryItems = items
        guard let url = components.url, let referer = secureURL(base + match.path + "/ep-\(episode)") else {
            throw AnimePlaybackError.unavailable("The player address is invalid.")
        }
        return ResolvedAnimePlayback(url: url, referer: referer)
    }

    private func match(media: MediaItem, client: TMDBClient) async throws -> Match {
        if let cached = matches[media.id] { return cached }
        let identity = try await client.animeIdentity(id: media.id)
        guard identity.malID > 0 else { throw AnimePlaybackError.unavailable("This anime does not have a verified Anikoto title mapping yet.") }
        var visited = Set<String>()
        var names = [String]()
        for name in [media.title] + identity.names where !name.isEmpty && !names.contains(name) { names.append(name) }
        for name in names.prefix(2) {
            let search = try await result(path: "/ajax/anime/search", query: ["keyword": name]) as? [String: Any]
            let html = search?["html"] as? String ?? ""
            for path in Self.searchPaths(html) where visited.insert(path).inserted {
                try Task.checkCancellation()
                let page = try await get(path: path)
                let tags = Self.tags(page)
                guard let tag = tags.first(where: { Self.classes($0.attributes["class"]).contains("watch-wrap") }),
                      let id = tag.attributes["data-id"], !id.isEmpty, id.allSatisfy(\.isNumber) else { continue }
                let episodes = try await episodeList(id: id)
                if episodes.contains(where: { $0.malID == identity.malID }) {
                    let match = Match(path: path, id: id, malID: identity.malID)
                    matches[media.id] = match
                    return match
                }
            }
        }
        throw AnimePlaybackError.unavailable("No release with a matching catalog identity was found on Anikoto. Try another anime.")
    }
    private func episodeList(id: String) async throws -> [Episode] {
        let html = try await result(path: "/ajax/episode/list/\(id)") as? String ?? ""
        return Self.tags(html).compactMap { tag in
            guard tag.name == "a", let number = Int(tag.attributes["data-num"] ?? ""),
                  let servers = tag.attributes["data-ids"], !servers.isEmpty else { return nil }
            return Episode(number: number, malID: Int(tag.attributes["data-mal"] ?? "") ?? 0, servers: servers)
        }
    }
    private func result(path: String, query: [String: String] = [:]) async throws -> Any {
        let html = try await get(path: path, query: query)
        guard let data = html.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["status"] as? Int) == 200, let result = object["result"] else {
            throw AnimePlaybackError.unavailable("Anikoto could not find this episode or source. Please retry.")
        }
        return result
    }
    private func get(path: String, query: [String: String] = [:]) async throws -> String {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), var components = URLComponents(string: base + path) else {
            throw AnimePlaybackError.unavailable("The anime address is invalid.")
        }
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url, url.host == "anikoto.cz", secureURL(url.absoluteString) != nil else {
            throw AnimePlaybackError.unavailable("The anime address is invalid.")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 Streamify-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(base + "/", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw AnimePlaybackError.unavailable("Anikoto is temporarily unavailable. Please retry or choose a different source.")
        }
        guard let value = String(data: data, encoding: .utf8) else { throw AnimePlaybackError.unavailable("Anikoto returned an unreadable response.") }
        return value
    }

    // Only the public attributes needed for title/episode identity are parsed. No scripts are evaluated.
    private struct Tag { let name: String; let attributes: [String: String]; let range: NSRange }
    private static func tags(_ html: String) -> [Tag] {
        guard let expression = try? NSRegularExpression(pattern: #"<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let attributes = try? NSRegularExpression(pattern: #"([a-zA-Z_:][a-zA-Z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [] }
        let string = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: string.length)).map { match in
            let text = string.substring(with: match.range(at: 2)) as NSString
            var values: [String: String] = [:]
            for attribute in attributes.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let key = text.substring(with: attribute.range(at: 1)).lowercased()
                let range = (2...4).map { attribute.range(at: $0) }.first { $0.location != NSNotFound }
                if let range { values[key] = unescape(text.substring(with: range)) }
            }
            return Tag(name: string.substring(with: match.range(at: 1)).lowercased(), attributes: values, range: match.range)
        }
    }
    private static func classes(_ text: String?) -> [String] { (text ?? "").split(whereSeparator: \.isWhitespace).map(String.init) }
    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
    static func searchPaths(_ html: String) -> [String] {
        var paths = [String]()
        for tag in tags(html) where tag.name == "a" && classes(tag.attributes["class"]).contains("item") {
            guard let href = tag.attributes["href"], let url = URL(string: href, relativeTo: URL(string: "https://anikoto.cz"))?.absoluteURL,
                  url.scheme == "https", url.host == "anikoto.cz", url.user == nil, url.password == nil, url.port == nil,
                  url.path.range(of: #"^/watch/[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else { continue }
            if !paths.contains(url.path) { paths.append(url.path) }
        }
        return Array(paths.prefix(6))
    }
    static func serverToken(_ html: String, language: String, server: String) -> String? {
        guard ["sub", "dub"].contains(language) else { return nil }
        let all = tags(html)
        let blocks = all.filter { classes($0.attributes["class"]).contains("type") && $0.attributes["data-type"] != nil }
        guard let index = blocks.firstIndex(where: { $0.attributes["data-type"] == language }) else { return nil }
        let start = NSMaxRange(blocks[index].range)
        let end = index + 1 < blocks.count ? blocks[index + 1].range.location : (html as NSString).length
        guard end >= start else { return nil }
        let block = (html as NSString).substring(with: NSRange(location: start, length: end - start))
        return tags(block).first { $0.name == "li" && $0.attributes["data-sv-id"] == server }?.attributes["data-link-id"]
    }
}
