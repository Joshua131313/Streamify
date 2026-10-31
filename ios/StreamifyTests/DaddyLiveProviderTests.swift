import Foundation
import XCTest
@testable import Streamify

/// Captured public HTML structure and a protocol that intercepts every host.
/// No protected API, player document, authentication or video is requested.
final class DaddyLiveProviderTests: XCTestCase {
    func testPublishedKentStateAndCSSacramentoFootballListingKeepsTheExactSchoolIdentity() {
        let date = Date(timeIntervalSince1970: 1_793_413_800)
        let game = SportsGame(eventID: "401866451", league: .ncaaf, date: date, state: "in", status: "Live",
            home: SportsTeam(id: "16", name: "Sacramento State Hornets", abbreviation: "SAC", logo: "", streamNames: ["Sacramento State"]),
            away: SportsTeam(id: "2309", name: "Kent State Golden Flashes", abbreviation: "KENT", logo: "", streamNames: ["Kent State"]), venue: "", broadcasts: "", link: "")
        let html = DaddyFixture.home(game, title: "🏈 NCAA FBS : Kent State 🇺🇸 vs CS Sacramento 🇺🇸", links: "<a href='/watch.php?id=45'>ESPN2 USA</a>",
            heading: "Friday 30th October 2026 - Schedule Time UK GMT", clock: "02:30")
        XCTAssertEqual(DaddyLiveProvider.channels(in: html, game: game, now: date).map(\.title), ["ESPN2 USA"])
        for wrong in ["Sacramento Kings", "CS San Francisco", "Sacramento", "Kent"] {
            XCTAssertTrue(DaddyLiveProvider.channels(in: html.replacingOccurrences(of: "CS Sacramento", with: wrong), game: game, now: date).isEmpty)
        }
    }

    func testExpandedScheduleAboveTwoMegabytesResolvesAndFourMegabyteLimitIsStillEnforced() async throws {
        let expanded = DaddyProtocolFixture(.expandedCatalog(2_240_815), count: 1)
        let values = try await DaddyLiveProvider(session: expanded.session).streams(expanded.game)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(expanded.requests.count, 2)
        let oversized = DaddyProtocolFixture(.expandedCatalog(4 * 1024 * 1024 + 1), count: 1)
        do {
            _ = try await DaddyLiveProvider(session: oversized.session).streams(oversized.game)
            XCTFail("An unbounded schedule must still be rejected")
        } catch { XCTAssertEqual(oversized.requests.count, 1) }
    }

    func testAllSixLeaguesUseBothFullTeamsAndPublishedChannelLinks() throws {
        for league in SportsLeague.allCases where league != .tennis {
            let game = DaddyFixture.game(league)
            let suffix = league == .wnba ? " W" : ""
            let title = "🏀 \(league == .ncaaf ? "NCAAF" : league.title) : \(game.home.name)\(suffix) 🇺🇸 vs \(game.away.name)\(suffix) 🇨🇦"
            let html = DaddyFixture.home(game, title: title, links: "<a href='/watch.php?id=12'>TV &amp; Sports</a>")
            let values = DaddyLiveProvider.channels(in: html, game: game, now: DaddyFixture.instant)
            XCTAssertEqual(values.map(\.title), ["TV & Sports"], "League \(league)")
            XCTAssertEqual(values.map(\.watchURL.absoluteString), ["https://thedaddy.pk/watch.php?id=12"])
        }
    }

    func testWNBAAndCollegeFootballNeverMatchADifferentLeagueOrSchool() {
        let wnba = DaddyFixture.game(.wnba)
        let teams = "\(wnba.away.name) W vs \(wnba.home.name) W"
        XCTAssertTrue(channels(DaddyFixture.home(wnba, title: "NBA : " + teams), wnba).isEmpty)
        let college = DaddyFixture.game(.ncaaf)
        for label in ["NCAA", "NCAAB", "NFL"] {
            XCTAssertTrue(channels(DaddyFixture.home(college, title: "\(label) : Alabama Crimson Tide vs Georgia Bulldogs"), college).isEmpty)
        }
        XCTAssertEqual(channels(DaddyFixture.home(college, title: "College Football : Alabama Crimson Tide vs Georgia Bulldogs"), college).count, 1)
        for wrong in ["NCAAF : Alabama State Hornets vs Georgia Bulldogs", "NCAAF : Alabama Crimson Tide vs Georgia Tech Yellow Jackets"] {
            XCTAssertTrue(channels(DaddyFixture.home(college, title: wrong), college).isEmpty)
        }
        let nba = DaddyFixture.game(.nba)
        for wrong in ["NBA : Golden State Warriors vs Minnesota Timberwolves", "OHL : Moose Jaw Warriors vs Denver Nuggets"] {
            XCTAssertTrue(channels(DaddyFixture.home(nba, title: wrong), nba).isEmpty)
        }
    }

    func testHTMLApostrophesAccentEntitiesAndOrdinalHeadingsAreDecoded() {
        let game = DaddyFixture.game(.nhl, away: "Montréal Canadiens", home: "St. John's IceCaps")
        let html = DaddyFixture.home(game, title: "NHL : Montr&eacute;al Canadiens vs St. John&#039;s IceCaps",
                                     links: "<a title='NHL &amp; TV' href='watch.php?id=15'>NHL&nbsp;&amp;&#32;TV</a>",
                                     heading: "Monday 26th Oct 2026 - Schedule Time UK GMT", clock: "02:00")
        XCTAssertEqual(channels(html, game).map(\.title), ["NHL & TV"])
    }

    func testCapturedCollegeFootballListingsMatchFormalSchoolNamesAndMidnightGame() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-10-28T00:30:00Z"))
        func game(away: String, awaySchool: String, home: String, homeSchool: String, at timestamp: String) throws -> SportsGame {
            SportsGame(eventID: "college-capture", league: .ncaaf, date: try XCTUnwrap(formatter.date(from: timestamp)), state: "in", status: "Live",
                home: SportsTeam(id: "h", name: home, abbreviation: "HOME", logo: "", streamNames: [homeSchool]),
                away: SportsTeam(id: "a", name: away, abbreviation: "AWAY", logo: "", streamNames: [awaySchool]), venue: "", broadcasts: "", link: "")
        }
        let delaware = try game(away: "Delaware Blue Hens", awaySchool: "Delaware", home: "Western Kentucky Hilltoppers",
            homeSchool: "Western Kentucky", at: "2026-10-27T23:00:00Z")
        let samHouston = try game(away: "Sam Houston Bearkats", awaySchool: "Sam Houston", home: "Missouri State Bears",
            homeSchool: "Missouri State", at: "2026-10-28T00:00:00Z")
        let delawareChannels = DaddyLiveProvider.channels(in: DaddyFixture.capturedCollegeFootball, game: delaware, now: now)
        XCTAssertEqual(delawareChannels.map(\.title), ["CBS Sports Network"])
        XCTAssertEqual(delawareChannels.map(\.watchURL.absoluteString), ["https://thedaddy.pk/watch.php?id=308"])
        let samHoustonChannels = DaddyLiveProvider.channels(in: DaddyFixture.capturedCollegeFootball, game: samHouston, now: now)
        XCTAssertEqual(samHoustonChannels.map(\.title), ["ESPN2 USA"])
        XCTAssertEqual(samHoustonChannels.map(\.watchURL.absoluteString), ["https://thedaddy.pk/watch.php?id=45"])

        let wrongSchool = try game(away: "Delaware State Hornets", awaySchool: "Delaware State", home: "Western Kentucky Hilltoppers",
            homeSchool: "Western Kentucky", at: "2026-10-27T23:00:00Z")
        let wrongOpponent = try game(away: "Sam Houston Bearkats", awaySchool: "Sam Houston", home: "Missouri Tigers",
            homeSchool: "Missouri", at: "2026-10-28T00:00:00Z")
        let wrongDate = try game(away: "Sam Houston Bearkats", awaySchool: "Sam Houston", home: "Missouri State Bears",
            homeSchool: "Missouri State", at: "2026-10-29T00:00:00Z")
        for invalid in [wrongSchool, wrongOpponent, wrongDate] {
            XCTAssertTrue(DaddyLiveProvider.channels(in: DaddyFixture.capturedCollegeFootball, game: invalid, now: now).isEmpty)
        }
    }

    func testMidnightSportsDayRollsForwardOnceAndRejectsStaleWrongOrMalformedDates() {
        let game = DaddyFixture.game(.nba)
        XCTAssertEqual(channels(DaddyFixture.home(game, heading: "Monday 26th Oct 2026 - Schedule Time UK GMT", clock: "02:00"), game).count, 1)
        for heading in ["Saturday 24th Oct 2026 - Schedule Time UK GMT", "Wednesday 28th Oct 2026 - Schedule Time UK GMT", "No date published"] {
            XCTAssertTrue(channels(DaddyFixture.home(game, heading: heading, clock: "02:00"), game).isEmpty)
        }
        for clock in ["12:00", "25:00", "02:99", "", "tomorrow"] {
            XCTAssertTrue(channels(DaddyFixture.home(game, clock: clock), game).isEmpty)
        }
        let html = DaddyFixture.home(game)
        XCTAssertTrue(DaddyLiveProvider.channels(in: html, game: game, now: DaddyFixture.instant.addingTimeInterval(19 * 3600)).isEmpty)
        let noDate = SportsGame(eventID: game.eventID, league: game.league, date: nil, state: game.state, status: game.status,
                            home: game.home, away: game.away, venue: "", broadcasts: "", link: "")
        XCTAssertTrue(channels(html, noDate).isEmpty)
    }

    func testClosestDoubleheaderDoesNotOfferTheOtherGamesChannels() {
        let game = DaddyFixture.game(.mlb)
        let early = DaddyFixture.event(game, clock: "00:30", links: "<a href='/watch.php?id=1'>Earlier game</a>")
        let exact = DaddyFixture.event(game, clock: "02:00", links: "<a href='/watch.php?id=2'>Current game</a>")
        let html = DaddyFixture.day(early + exact)
        XCTAssertEqual(channels(html, game).map(\.watchURL.absoluteString), ["https://thedaddy.pk/watch.php?id=2"])
    }

    func testOnlyExactSafeAdvertisedWatchLinksAreAcceptedAndDeduplicated() {
        let game = DaddyFixture.game(.nba)
        let unsafe = ["javascript:alert(1)", "http://thedaddy.pk/watch.php?id=1", "https://evil.test/watch.php?id=1", "//evil.test/watch.php?id=1",
                      "https://user:secret@thedaddy.pk/watch.php?id=1", "/watch.php?id=1&id=2", "/watch.php?id=1&amp;other=2", "/other.php?id=1",
                      "/watch.php?id=1#fragment", "/watch.php?id=abc", "/watch.php?id=1%0A", "https://thedaddy.pk:444/watch.php?id=1"]
        let links = unsafe.map { "<a href='\($0)'>Unsafe</a>" }.joined() +
            "<a href='/watch.php?id=12'>Main</a><a href='https://thedaddy.pk/watch.php?id=12'>Duplicate</a>"
        XCTAssertEqual(channels(DaddyFixture.home(game, links: links), game).map(\.title), ["Main"])
        let fake = "<script>let template = `\(DaddyFixture.event(game))`;</script><a href='/watch.php?id=99'>Outside schedule</a>"
        XCTAssertTrue(channels(fake, game).isEmpty)
    }

    func testEmbedUsesThePublishedPlayerFrameAndEscapedEmbedCodeWithoutGuessing() throws {
        let watch = try XCTUnwrap(URL(string: "https://thedaddy.pk/watch.php?id=12"))
        let markup = "<iframe id='advertisement' src='https://ad.example.test/'></iframe><iframe allowfullscreen src='https://fixture.streamify.test/actual?one=1&amp;two=2' id='playerFrame'></iframe>"
        XCTAssertEqual(DaddyLiveProvider.embedURL(in: markup, relativeTo: watch)?.absoluteString, "https://fixture.streamify.test/actual?one=1&two=2")
        let code = "<textarea id='embedCode'>&lt;iframe src=&quot;https://fixture.streamify.test/published&quot; allowfullscreen&gt;&lt;/iframe&gt;</textarea>"
        XCTAssertEqual(DaddyLiveProvider.embedURL(in: code, relativeTo: watch)?.absoluteString, "https://fixture.streamify.test/published")
        let literal = "<textarea id='embedCode'><iframe src='/public-embed.php?channel=12'></iframe></textarea>"
        XCTAssertEqual(DaddyLiveProvider.embedURL(in: literal, relativeTo: watch)?.absoluteString, "https://thedaddy.pk/public-embed.php?channel=12")
        XCTAssertNil(DaddyLiveProvider.embedURL(in: "<p>Channel 12</p>", relativeTo: watch), "Channel IDs never become invented stream URLs.")
        XCTAssertNil(DaddyLiveProvider.embedURL(in: "<script>const fake=\"<iframe id='playerFrame' src='https://bad.test/'></iframe>\";</script>", relativeTo: watch))
    }

    func testUnsafeOrUnrelatedEmbedsNeverBecomeSources() throws {
        let watch = try XCTUnwrap(URL(string: "https://thedaddy.pk/watch.php?id=12"))
        for value in ["http://fixture.streamify.test/plain", "https://user:secret@fixture.streamify.test/player", "javascript:alert(1)", "data:text/html,video", "https://"] {
            XCTAssertNil(DaddyLiveProvider.embedURL(in: "<iframe id='playerFrame' src='\(value)'></iframe>", relativeTo: watch))
        }
        XCTAssertNil(DaddyLiveProvider.embedURL(in: "<iframe src='https://ads.example.test/'></iframe>", relativeTo: watch))
    }

    func testCatalogCacheFreshWatchDocumentsTwelveChoiceLimitAndFourConcurrentRequests() async throws {
        let fixture = DaddyProtocolFixture(.normal, count: 14)
        let provider = DaddyLiveProvider(session: fixture.session)
        let first = try await provider.streams(fixture.game)
        let second = try await provider.streams(fixture.game)
        XCTAssertEqual(first.count, 12); XCTAssertEqual(second.count, 12)
        XCTAssertEqual(first.first?.title, "DaddyLive · Server 1")
        XCTAssertEqual(first.first?.url.absoluteString, "https://fixture.streamify.test/embed-1-1")
        XCTAssertEqual(second.first?.url.absoluteString, "https://fixture.streamify.test/embed-1-2")
        XCTAssertEqual(fixture.requests.filter { $0.url?.path == "/" }.count, 1, "The public homepage stays warm for 30 seconds.")
        XCTAssertEqual(fixture.requests.filter { $0.url?.path == "/watch.php" }.count, 24, "Watch pages always resolve their current advertised embed.")
        XCTAssertLessThanOrEqual(fixture.maximumActive, 4)
        XCTAssertGreaterThan(fixture.maximumActive, 1, "Choices should resolve concurrently within the fixed limit.")
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "thedaddy.pk" }, "Never prefetch a player document or a protected API.")
        XCTAssertFalse(fixture.requests.contains { $0.url?.query == "id=13" || $0.url?.query == "id=14" })
    }

    func testOneFailedChannelAndDuplicateEmbedDoNotHideTheOtherSource() async throws {
        let fixture = DaddyProtocolFixture(.partial, count: 4)
        let values = try await DaddyLiveProvider(session: fixture.session).streams(fixture.game)
        XCTAssertEqual(values.map(\.url.absoluteString), ["https://fixture.streamify.test/shared-player"])
        XCTAssertEqual(values.map(\.title), ["DaddyLive · Server 1"])
        XCTAssertEqual(fixture.requests.count, 5)
    }

    func testAllFailedWatchPagesAndCatalogTransportFailureRemainReadable() async throws {
        let all = DaddyProtocolFixture(.allFailed, count: 4)
        do { _ = try await DaddyLiveProvider(session: all.session).streams(all.game); XCTFail("Unavailable player pages must not turn into guessed sources.") }
        catch { guard case .streamsUnavailable? = error as? SportsServiceError else { return XCTFail("Unexpected error: \(error)") } }
        let failed = DaddyProtocolFixture(.catalogFailure, count: 4)
        do { _ = try await DaddyLiveProvider(session: failed.session).streams(failed.game); XCTFail("The catalog failure must be reported.") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(failed.requests.count, 1)
    }

    func testCancellationStopsOwnedWatchRequestsAndCannotReturnSources() async throws {
        let fixture = DaddyProtocolFixture(.slow, count: 12)
        let provider = DaddyLiveProvider(session: fixture.session)
        let task = Task { try await provider.streams(fixture.game) }
        for _ in 0..<200 {
            if fixture.active > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(fixture.active, 0)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must not deliver an embed.") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        for _ in 0..<100 {
            if fixture.active == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fixture.active, 0, "Provider deadlines cancel the actual URLSession tasks.")
        XCTAssertGreaterThan(fixture.cancelled, 0)
        XCTAssertLessThanOrEqual(fixture.maximumActive, 4)
        let finishedRequestCount = fixture.requests.count
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.requests.count, finishedRequestCount, "Cancelled discovery cannot keep starting requests after returning.")
    }

    private func channels(_ html: String, _ game: SportsGame) -> [DaddyLiveProvider.Channel] {
        DaddyLiveProvider.channels(in: html, game: game, now: DaddyFixture.instant)
    }
}

private enum DaddyFixture {
    // Narrow excerpt of the public 27 October 2026 schedule: original date,
    // league/title/flag text, times and advertised channel links are retained.
    static let capturedCollegeFootball = """
    <div class="schedule__day">
      <div class="schedule__dayTitle">Tuesday 27th Oct 2026 - Schedule Time UK GMT</div>
      <div class="schedule__category is-expanded">
        <div class="schedule__catHeader"><div class="card__meta">College Football 🏈</div></div>
        <div class="schedule__categoryBody">
          <div class="schedule__event">
            <div class="schedule__eventHeader">
              <span class="schedule__time" data-time="23:00">23:00</span>
              <span class="schedule__eventTitle">🏈 College Football : University of Delaware 🇺🇸 vs Western Kentucky 🇺🇸</span>
            </div>
            <div class="schedule__channels">
              <a target="_blank" href="/watch.php?id=308" title="CBS Sports Network" data-ch="cbs sports network">CBS Sports Network</a>
            </div>
          </div>
          <div class="schedule__event">
            <div class="schedule__eventHeader">
              <span class="schedule__time" data-time="00:00">00:00</span>
              <span class="schedule__eventTitle">🏈 College Football : Sam Houston 🇺🇸 vs Missouri State 🇺🇸</span>
            </div>
            <div class="schedule__channels">
              <a target="_blank" href="/watch.php?id=45" title="ESPN2 USA" data-ch="espn2 usa">ESPN2 USA</a>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
    static var instant: Date { ISO8601DateFormatter().date(from: "2026-10-27T02:00:00Z")! }
    static func game(_ league: SportsLeague, away: String? = nil, home: String? = nil, date: Date? = nil) -> SportsGame {
        let names: (String, String)
        switch league {
        case .nba: names = ("Golden State Warriors", "Denver Nuggets")
        case .wnba: names = ("Golden State Valkyries", "Atlanta Dream")
        case .nfl: names = ("Dallas Cowboys", "Philadelphia Eagles")
        case .ncaaf: names = ("Alabama Crimson Tide", "Georgia Bulldogs")
        case .nhl: names = ("Detroit Red Wings", "Edmonton Oilers")
        case .mlb: names = ("Milwaukee Brewers", "Tampa Bay Rays")
        case .tennis: names = ("Jannik Sinner", "Carlos Alcaraz")
        }
        return SportsGame(eventID: "401020304", league: league, date: date ?? instant, state: "in", status: "Live",
                          home: SportsTeam(id: "h", name: home ?? names.1, abbreviation: "HOME", logo: ""),
                          away: SportsTeam(id: "a", name: away ?? names.0, abbreviation: "AWAY", logo: ""), venue: "", broadcasts: "", link: "")
    }
    static func heading(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEEE d MMM yyyy"
        return formatter.string(from: date) + " - Schedule Time UK GMT"
    }
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    static func day(_ events: String, heading: String = "Tuesday 27th Oct 2026 - Schedule Time UK GMT") -> String {
        "<html><div class='schedule__day'><div class='schedule__dayTitle'>\(heading)</div><div class='schedule__category'><div class='schedule__categoryBody'>\(events)</div></div></div></html>"
    }
    static func event(_ game: SportsGame, title: String? = nil, clock: String = "02:00", links: String = "<a href='/watch.php?id=12'>Main</a>") -> String {
        let title = title ?? "\(game.league.title) : \(game.away.name) vs \(game.home.name)"
        return "<div class='schedule__event'><div class='schedule__eventHeader'><span class='schedule__time' data-time='\(clock)'>\(clock)</span><span class='schedule__eventTitle'>\(title)</span></div><div class='schedule__channels'>\(links)</div></div>"
    }
    static func home(_ game: SportsGame, title: String? = nil, links: String = "<a href='/watch.php?id=12'>Main</a>",
                     heading: String = "Tuesday 27th Oct 2026 - Schedule Time UK GMT", clock: String = "02:00") -> String {
        day(event(game, title: title, clock: clock, links: links), heading: heading)
    }
}

private final class DaddyProtocolFixture {
    enum Mode { case normal, partial, allFailed, catalogFailure, slow, expandedCatalog(Int) }
    let session: URLSession
    let game: SportsGame
    private let identifier = UUID().uuidString
    private let scenario: DaddyProtocolScenario
    var requests: [URLRequest] { scenario.requests }
    var active: Int { scenario.snapshot.0 }
    var maximumActive: Int { scenario.snapshot.1 }
    var cancelled: Int { scenario.snapshot.2 }
    init(_ mode: Mode, count: Int) {
        game = DaddyFixture.game(.nba, date: Date())
        scenario = DaddyProtocolScenario(mode, game: game, count: count)
        DaddyURLProtocol.register(scenario, id: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DaddyURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Streamify-Daddy-Test": identifier]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); DaddyURLProtocol.unregister(identifier) }
}

private final class DaddyProtocolScenario {
    struct Reply { let data: Data; let status: Int; let delay: TimeInterval; let watch: Bool }
    let mode: DaddyProtocolFixture.Mode
    let home: String
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var current = 0, peak = 0, stopped = 0
    private var watches: [String: Int] = [:]
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    var snapshot: (Int, Int, Int) { lock.lock(); defer { lock.unlock() }; return (current, peak, stopped) }
    init(_ mode: DaddyProtocolFixture.Mode, game: SportsGame, count: Int) {
        self.mode = mode
        let links = (1...count).map { "<a href='/watch.php?id=\($0)'>Server \($0)</a>" }.joined()
        home = DaddyFixture.home(game, links: links, heading: DaddyFixture.heading(game.date!), clock: DaddyFixture.clock(game.date!))
    }
    func begin(_ request: URLRequest) throws -> Reply {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let url = try XCTUnwrap(request.url)
        guard url.scheme == "https", url.host == "thedaddy.pk" else { throw URLError(.unsupportedURL) }
        if url.path == "/" {
            if case .catalogFailure = mode { throw URLError(.notConnectedToInternet) }
            var body = Data(home.utf8)
            if case .expandedCatalog(let bytes) = mode { body.append(Data(repeating: 32, count: max(0, bytes - body.count))) }
            return Reply(data: body, status: 200, delay: 0, watch: false)
        }
        guard url.path == "/watch.php", let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value else { throw URLError(.unsupportedURL) }
        current += 1; peak = max(peak, current); watches[id, default: 0] += 1
        if case .allFailed = mode { return Reply(data: Data("Unavailable".utf8), status: 503, delay: 0.03, watch: true) }
        if case .partial = mode, id == "2" { return Reply(data: Data("Unavailable".utf8), status: 503, delay: 0.03, watch: true) }
        if case .partial = mode, id == "3" { return Reply(data: Data("<iframe id='playerFrame' src='http://unsafe.test/'></iframe>".utf8), status: 200, delay: 0.03, watch: true) }
        let address: String
        if case .partial = mode { address = "https://fixture.streamify.test/shared-player" }
        else { address = "https://fixture.streamify.test/embed-\(id)-\(watches[id]!)" }
        let html = "<html><iframe src='\(address)' id='playerFrame' allowfullscreen></iframe></html>"
        let delay: TimeInterval = { if case .slow = mode { return 5 }; return 0.03 }()
        return Reply(data: Data(html.utf8), status: 200, delay: delay, watch: true)
    }
    func end(watch: Bool, cancelled: Bool) {
        guard watch else { return }
        lock.lock(); defer { lock.unlock() }
        current -= 1; if cancelled { stopped += 1 }
    }
}

private final class DaddyURLProtocol: URLProtocol {
    private static let registryLock = NSLock()
    private static var scenarios: [String: DaddyProtocolScenario] = [:]
    private let lock = NSLock()
    private var completed = false
    private var scenario: DaddyProtocolScenario?
    private var work: DispatchWorkItem?
    private var watch = false
    static func register(_ scenario: DaddyProtocolScenario, id: String) { registryLock.lock(); defer { registryLock.unlock() }; scenarios[id] = scenario }
    static func unregister(_ id: String) { registryLock.lock(); defer { registryLock.unlock() }; scenarios.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.registryLock.lock()
        let registered = request.value(forHTTPHeaderField: "X-Streamify-Daddy-Test").flatMap { Self.scenarios[$0] }
        Self.registryLock.unlock()
        lock.lock()
        guard !completed else { lock.unlock(); return }
        do {
            let scenario = try XCTUnwrap(registered)
            let reply = try scenario.begin(request)
            self.scenario = scenario; watch = reply.watch
            let item = DispatchWorkItem { [weak self] in self?.deliver(reply) }
            work = item
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: item)
        } catch {
            completed = true; lock.unlock()
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    private func finish(cancelled: Bool) -> Bool {
        lock.lock()
        guard !completed else { lock.unlock(); return false }
        completed = true
        let scenario = scenario, watch = watch, work = work
        self.work = nil
        lock.unlock()
        if cancelled { work?.cancel() }
        scenario?.end(watch: watch, cancelled: cancelled)
        return true
    }
    private func deliver(_ reply: DaddyProtocolScenario.Reply) {
        guard finish(cancelled: false) else { return }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=UTF-8"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { _ = finish(cancelled: true) }
}
