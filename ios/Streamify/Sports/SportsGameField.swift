import SwiftUI
import WebKit

enum SportsFieldSource: Equatable {
    case embed(URL)
    case external(provider: String, url: URL)

    private struct Response: Decodable {
        let provider: String
        let embedUrl: String?
        let externalUrl: String?
    }

    static func lookupURL(for game: SportsGame) -> URL? {
        var id = game.eventID
        var tour: String?
        if game.league == .tennis {
            guard SportsService.validTennisEventID(id), let match = game.tennis else { return nil }
            if match.source == "espn" {
                guard SportsService.validEventID(match.competitionID), match.tour == .atp || match.tour == .wta,
                      id == "espn-\(match.tour.rawValue.lowercased())-\(match.competitionID)" else { return nil }
                id = match.competitionID
            }
            if match.tour == .atp || match.tour == .wta { tour = match.tour.rawValue.lowercased() }
            else if id.hasPrefix("tennislive-atp-") { tour = "atp" }
            else if id.hasPrefix("tennislive-wta-") { tour = "wta" }
        } else {
            #if DEBUG
            let isFixture = PreviewFixtures.enabled && ["fixture", "final"].contains { id == "\(game.league.rawValue)-\($0)" }
            #else
            let isFixture = false
            #endif
            guard SportsService.validEventID(id) || isFixture else { return nil }
        }
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = "streamify.watch"; parts.path = "/api/field"
        var query = [URLQueryItem(name: "league", value: game.league.rawValue), URLQueryItem(name: "gameId", value: id)]
        if let tour { query.append(URLQueryItem(name: "tour", value: tour)) }
        if let date = game.date, date.timeIntervalSince1970.isFinite {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd"
            query.append(URLQueryItem(name: "date", value: formatter.string(from: date)))
        }
        parts.queryItems = query
        return parts.url
    }

    static func load(from url: URL, league: SportsLeague, session: URLSession = .shared) async throws -> Self? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.url == url,
              (200..<300).contains(response.statusCode), data.count <= 16_384 else { throw SportsServiceError.invalidResponse }
        return try decode(data, league: league)
    }

    static func decode(_ data: Data, league: SportsLeague) throws -> Self? {
        guard let response = try JSONDecoder().decode(Response?.self, from: data) else { return nil }
        if response.provider == "SportScore", let address = response.embedUrl,
           let url = embedURL(address, league: league), response.externalUrl == nil { return .embed(url) }
        if let address = response.externalUrl, response.embedUrl == nil,
           let url = trustedHTTPS(address), let host = url.host?.lowercased() {
            switch (response.provider, host, league) {
            case ("ESPN", "www.espn.com", _), ("MLB", "www.mlb.com", .mlb), ("NHL", "www.nhl.com", .nhl):
                if url.path != "/", !url.path.isEmpty { return .external(provider: response.provider, url: url) }
            case ("SportScore", "sportscore.com", _):
                if embedURL(address, league: league) != nil { return .external(provider: response.provider, url: url) }
            default: break
            }
        }
        throw SportsServiceError.invalidResponse
    }

    static func embedURL(_ address: String, league: SportsLeague) -> URL? {
        guard ["basketball", "tennis"].contains(league.sport), let url = trustedHTTPS(address),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.host == "sportscore.com",
              parts.fragment == nil,
              parts.percentEncodedPath.range(of: "^/embed/tracker/\(league.sport)/[a-z0-9]+(?:-[a-z0-9]+)*-vs-[a-z0-9]+(?:-[a-z0-9]+)*/$", options: .regularExpression) != nil else { return nil }
        if let query = parts.percentEncodedQuery, query != "theme=dark", query != "theme=light" { return nil }
        return url
    }

    static func trustedHTTPS(_ address: String) -> URL? {
        guard let url = sportsHTTPSURL(address), url.port == nil || url.port == 443 else { return nil }
        return url
    }
}

struct SportsGameField: View {
    let game: SportsGame
    @State private var source: SportsFieldSource?
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0

    var body: some View {
        let requestURL = SportsFieldSource.lookupURL(for: game)
        VStack(alignment: .leading, spacing: 10) {
            if loading {
                ProgressView("Finding field coverage…").frame(maxWidth: .infinity, minHeight: 86)
            } else if failed {
                Text("The field could not be loaded.").foregroundStyle(AppTheme.muted)
                Pill(title: "Retry", selected: false) { revision += 1 }
            } else {
                switch source {
                case .embed(let url):
                    SportsFieldWebView(url: url, failed: $failed)
                        .frame(height: game.league == .tennis ? 350 : 390)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("sports-field-tracker")
                case .external(let provider, let url):
                    Link(destination: url) {
                        Label("Open \(provider) game coverage", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityIdentifier("sports-field-provider-link")
                case nil:
                    Text("Interactive field coverage is unavailable for this game.").foregroundStyle(AppTheme.muted)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-center-field-\(game.league.rawValue)")
        .task(id: "\(requestURL?.absoluteString ?? "")|\(revision)") {
            loading = true; failed = false; source = nil
            guard let requestURL else { loading = false; return }
            do {
                let value = try await SportsFieldSource.load(from: requestURL, league: game.league)
                try Task.checkCancellation()
                source = value
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                failed = true; loading = false
            }
        }
    }
}

private struct SportsFieldWebView: UIViewRepresentable {
    let url: URL
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard coordinator.loadedURL != url else { return }
        coordinator.loadedURL = url
        view.stopLoading()
        #if DEBUG
        if let html = PreviewFixtures.fieldTrackerHTML(for: url) {
            view.loadHTMLString(html, baseURL: url)
            return
        }
        #endif
        view.load(URLRequest(url: url, timeoutInterval: 15))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.loadedURL = nil
        view.navigationDelegate = nil
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SportsFieldWebView
        var loadedURL: URL?
        init(_ parent: SportsFieldWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let frame = action.targetFrame, let url = action.request.url else { decisionHandler(.cancel); return }
            if frame.isMainFrame {
                #if DEBUG
                if url.absoluteString == "about:blank", let loadedURL, PreviewFixtures.fieldTrackerHTML(for: loadedURL) != nil {
                    decisionHandler(.allow); return
                }
                #endif
                decisionHandler(url == loadedURL ? .allow : .cancel)
                return
            }
            let allowed = SportsFieldSource.trustedHTTPS(url.absoluteString) != nil &&
                ["sportscore.com", "widgets.thesports01.com", "widgets-v2.thesports01.com"].contains(url.host?.lowercased() ?? "")
            decisionHandler(allowed || url.absoluteString == "about:blank" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse,
               http.url != loadedURL || !(200..<300).contains(http.statusCode) {
                decisionHandler(.cancel); fail(); return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }

        private func fail(_ error: Error? = nil) {
            guard loadedURL != nil, (error as? URLError)?.code != .cancelled else { return }
            parent.failed = true
        }
    }
}
