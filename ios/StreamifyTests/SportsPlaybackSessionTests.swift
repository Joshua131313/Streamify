import XCTest
import Combine
import WebKit
@testable import Streamify

final class SportsPlaybackSessionTests: XCTestCase {
    @MainActor func testLiveGameSwitchKeepsPlayerIdentityAndRemembersEachGamesServer() async {
        let nba = playbackGame("nba-live", league: .nba)
        let nfl = playbackGame("nfl-live", league: .nfl)
        let final = playbackGame("nba-final", league: .nba, state: "post")
        let pregame = playbackGame("nba-next", league: .nba, state: "pre")
        let alpha = SportsStream(title: "Alpha", url: URL(string: "https://example.com/nba-a")!)
        let bravo = SportsStream(title: "Bravo", url: URL(string: "https://example.com/nba-b")!)
        let football = SportsStream(title: "Football", url: URL(string: "https://example.com/nfl-a")!)
        var requested: [String] = []
        let session = SportsPlaybackSession(loadSchedule: { _ in
            SportsSchedule(games: [nba, nfl, final, pregame, nba], failedLeagues: [], partial: false)
        }, loadStreams: { _, game in
            requested.append(game.id)
            return game.id == nba.id ? [alpha, bravo] : [football]
        })
        let origin = SportsPlaybackOrigin()
        session.play(title: "BOS vs TOR", url: alpha.url, sources: [alpha, bravo], origin: origin, game: nba)
        let identity = session.item?.id
        session.selectSource(bravo)
        let owner = UUID()
        session.pictureInPicture.attach(owner: owner, capability: .available, request: {}, stop: {})
        await session.refreshLiveGames()
        XCTAssertEqual(Set(session.liveGames.map(\.id)), Set([nba.id, nfl.id]))
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner), "Refreshing choices cannot reset the playing video or PiP driver.")
        XCTAssertEqual(session.item?.url, bravo.url)

        await session.selectGame(final)
        XCTAssertTrue(requested.isEmpty, "Final and scheduled games are not switchable live choices.")
        await session.selectGame(nfl)
        XCTAssertEqual(session.item?.id, identity, "A game switch must reuse the single playback surface.")
        XCTAssertEqual(session.item?.game?.id, nfl.id)
        XCTAssertEqual(session.item?.sources, [football])
        XCTAssertEqual(session.item?.url, football.url)
        XCTAssertNil(session.origin, "A different game cannot animate back to the original matchup's card.")
        session.selectSource(bravo)
        XCTAssertEqual(session.item?.url, football.url, "A previous game's stream must not appear in the current server list.")

        await session.selectGame(nba)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, bravo.url, "Returning restores this game's chosen server when it is still available.")
        XCTAssertEqual(session.sourceTitle, "Bravo")
        XCTAssertEqual(requested, [nfl.id, nba.id])
    }

    @MainActor func testChangingGameMetadataForTheSameChannelPreservesPiPAndDocumentKey() async {
        let first = playbackGame("first", league: .nba), next = playbackGame("next", league: .nfl)
        let channel = SportsStream(title: "Shared channel", url: URL(string: "https://example.com/channel")!)
        let session = SportsPlaybackSession(loadSchedule: { _ in
            SportsSchedule(games: [first, next], failedLeagues: [], partial: false)
        }, loadStreams: { _, _ in [channel] })
        session.play(title: "NBA game", url: channel.url, sources: [channel], game: first)
        await session.refreshLiveGames()
        let identity = session.item?.id, owner = UUID()
        var requests = 0
        session.pictureInPicture.attach(owner: owner, capability: .available, request: { requests += 1 }, stop: {})
        await session.selectGame(next)
        XCTAssertEqual(session.item?.game?.id, next.id)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, channel.url)
        XCTAssertEqual(session.reload, 0)
        XCTAssertFalse(session.direct)
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner),
            "Unchanged WebKit keys do not reattach their bridge, so metadata-only switching must retain its owner.")
        session.requestPictureInPicture()
        XCTAssertEqual(requests, 1)

        session.toggleDirect()
        let directOwner = UUID()
        session.pictureInPicture.attach(owner: directOwner, capability: .available, request: {}, stop: {})
        await session.selectGame(first)
        XCTAssertFalse(session.direct)
        XCTAssertFalse(session.pictureInPicture.owns(owner: directOwner),
            "Changing the playback mode changes the document key and must retire the old driver.")
    }

    @MainActor func testUnavailableGameStreamsLeaveCurrentPlaybackUntouched() async {
        let first = playbackGame("first", league: .nba), next = playbackGame("next", league: .nfl)
        let source = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession(loadSchedule: { _ in
            SportsSchedule(games: [first, next], failedLeagues: [], partial: false)
        }, loadStreams: { _, _ in [] })
        session.play(title: "Current game", url: source.url, sources: [source], game: first)
        let identity = session.item?.id, owner = UUID()
        session.pictureInPicture.attach(owner: owner, capability: .available, request: {}, stop: {})
        await session.refreshLiveGames()
        await session.selectGame(next)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.game?.id, first.id)
        XCTAssertEqual(session.item?.url, source.url)
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner))
        XCTAssertNotNil(session.gameSelectionError)
        XCTAssertNil(session.switchingGameID)
    }

    @MainActor func testLateGameSourceResponseCannotReopenOrReplaceAnotherSession() async {
        let first = playbackGame("first", league: .nba), next = playbackGame("next", league: .nfl)
        let source = SportsStream(title: "Original", url: URL(string: "https://example.com/original")!)
        let late = SportsStream(title: "Late", url: URL(string: "https://example.com/late")!)
        let started = expectation(description: "The selected game's source request began")
        var pending: CheckedContinuation<[SportsStream], Never>?
        let session = SportsPlaybackSession(loadSchedule: { _ in
            SportsSchedule(games: [first, next], failedLeagues: [], partial: false)
        }, loadStreams: { _, _ in
            await withCheckedContinuation { continuation in pending = continuation; started.fulfill() }
        })
        session.play(title: "First game", url: source.url, sources: [source], game: first)
        await session.refreshLiveGames()
        let switching = Task { await session.selectGame(next) }
        await fulfillment(of: [started], timeout: 2)
        session.close()
        session.play(title: "New channel", url: source.url, sources: [source])
        let newIdentity = session.item?.id
        pending?.resume(returning: [late])
        await switching.value
        XCTAssertEqual(session.item?.id, newIdentity)
        XCTAssertEqual(session.item?.title, "New channel")
        XCTAssertEqual(session.item?.url, source.url)
        XCTAssertNil(session.item?.game)
        XCTAssertNil(session.switchingGameID)
        XCTAssertNil(session.gameSelectionError)
    }

    private func playbackGame(_ id: String, league: SportsLeague, state: String = "in") -> SportsGame {
        SportsGame(eventID: id, league: league, date: Date(), state: state, status: "Q3",
            home: SportsTeam(id: "home", name: "Toronto", abbreviation: "TOR", logo: ""),
            away: SportsTeam(id: "away", name: "Boston", abbreviation: "BOS", logo: ""),
            venue: "", broadcasts: "", link: "")
    }

    @MainActor func testOnlyAConfirmedMissingVideoFrameClearsRetainedFullscreenOwnership() {
        XCTAssertFalse(SportsWebPiPBridge.confirmsMissingVideo(.success(true)))
        XCTAssertTrue(SportsWebPiPBridge.confirmsMissingVideo(.success(false)))
        XCTAssertTrue(SportsWebPiPBridge.confirmsMissingVideo(.success(NSNull())))
        XCTAssertTrue(SportsWebPiPBridge.confirmsMissingVideo(.failure(NSError(domain: WKError.errorDomain,
            code: WKError.Code.javaScriptInvalidFrameTarget.rawValue))))
        XCTAssertFalse(SportsWebPiPBridge.confirmsMissingVideo(.failure(NSError(domain: WKError.errorDomain,
            code: WKError.Code.javaScriptExceptionOccurred.rawValue))),
            "A transient script failure does not prove that WebKit returned or destroyed the fullscreen video.")
        XCTAssertFalse(SportsWebPiPBridge.confirmsMissingVideo(.failure(NSError(domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut))), "Background suspension or time passing must never raise the black app window.")
    }

    @MainActor func testPiPRestoreWaitsForProviderToReturnTheVideoBeforeRaisingAppWindow() {
        let source = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession(), owner = UUID()
        session.play(title: "Game", url: source.url, sources: [source])
        let identity = session.item?.id
        session.pictureInPicture.attach(owner: owner, capability: .available, request: {}, stop: {})
        var focus = SportsPlaybackWindowFocus()
        XCTAssertEqual(focus.transition(expanded: session.isExpanded, providerFullscreen: false), .player)

        session.pictureInPicture.reportProviderFullscreen(true, owner: owner)
        XCTAssertEqual(focus.transition(expanded: session.isExpanded, providerFullscreen: true), .provider)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertEqual(focus.transition(expanded: session.isExpanded, providerFullscreen: true), .application)

        // PiP can stop before WebKit moves its WKWebView back from the fullscreen
        // window. Raising our player now would show only its black placeholder.
        session.pictureInPicture.didStop(owner: owner, restoring: true)
        XCTAssertTrue(session.isExpanded)
        XCTAssertEqual(focus.transition(expanded: session.isExpanded,
            providerFullscreen: session.pictureInPicture.providerOwnsFullscreen), .provider)
        XCTAssertNil(focus.transition(expanded: true, providerFullscreen: true))

        session.pictureInPicture.reportProviderFullscreen(false, owner: owner)
        XCTAssertEqual(focus.transition(expanded: session.isExpanded,
            providerFullscreen: session.pictureInPicture.providerOwnsFullscreen), .player)
        XCTAssertNil(focus.transition(expanded: true, providerFullscreen: false))
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, source.url)
        XCTAssertEqual(session.reload, 0, "A presentation handoff must retain the existing provider document.")
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner))

        // The inverse ordering is valid too: returning the video to its parent
        // while PiP is still active must keep the app player out of the way.
        session.pictureInPicture.reportProviderFullscreen(true, owner: owner)
        XCTAssertEqual(focus.transition(expanded: true, providerFullscreen: true), .provider)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertEqual(focus.transition(expanded: session.isExpanded, providerFullscreen: true), .application)
        session.pictureInPicture.reportProviderFullscreen(false, owner: owner)
        XCTAssertNil(focus.transition(expanded: session.isExpanded, providerFullscreen: false))
        session.pictureInPicture.didStop(owner: owner, restoring: true)
        XCTAssertEqual(focus.transition(expanded: session.isExpanded, providerFullscreen: false), .player)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, source.url)
        XCTAssertEqual(session.reload, 0)
    }

    @MainActor func testFullscreenOwnerIgnoresStaleDriversAndRepeatedVideoSnapshots() {
        let pictureInPicture = SportsSystemPiP(), owner = UUID()
        pictureInPicture.attach(owner: owner, capability: .available, request: {}, stop: {})
        var invalidations = 0
        let observation = pictureInPicture.objectWillChange.sink { invalidations += 1 }
        defer { observation.cancel() }
        pictureInPicture.reportProviderFullscreen(true, owner: owner)
        XCTAssertTrue(pictureInPicture.providerOwnsFullscreen)
        XCTAssertEqual(invalidations, 1)
        for _ in 0..<10 { pictureInPicture.reportProviderFullscreen(true, owner: owner) }
        pictureInPicture.reportProviderFullscreen(false, owner: UUID())
        XCTAssertEqual(invalidations, 1)
        XCTAssertTrue(pictureInPicture.providerOwnsFullscreen)

        pictureInPicture.reset()
        pictureInPicture.reportProviderFullscreen(true, owner: owner)
        XCTAssertFalse(pictureInPicture.providerOwnsFullscreen,
            "An old fullscreen frame cannot cover or alter the next selected stream.")
    }

    @MainActor func testUnchangedPiPCapabilityHeartbeatsDoNotInvalidatePlayerChrome() {
        let pictureInPicture = SportsSystemPiP(), owner = UUID()
        pictureInPicture.attach(owner: owner, capability: .unavailable, request: {}, stop: {})
        var invalidations = 0
        let observation = pictureInPicture.objectWillChange.sink { invalidations += 1 }
        defer { observation.cancel() }

        for _ in 0..<10 { pictureInPicture.reportCapability(.unavailable, owner: owner) }
        XCTAssertEqual(invalidations, 0, "Unchanged WebKit heartbeats must not rebuild an open native source menu.")

        pictureInPicture.reportCapability(.available, owner: owner)
        XCTAssertEqual(invalidations, 1, "A real capability transition must still update the PiP control.")
        XCTAssertEqual(pictureInPicture.capability, .available)
        pictureInPicture.reportCapability(.available, owner: owner)
        pictureInPicture.reportCapability(.unavailable, owner: UUID())
        XCTAssertEqual(invalidations, 1, "Duplicate and stale-driver reports must not invalidate current player chrome.")
        XCTAssertEqual(pictureInPicture.capability, .available)

        pictureInPicture.reportCapability(.unavailable, owner: owner)
        XCTAssertEqual(invalidations, 2)
        XCTAssertEqual(pictureInPicture.capability, .unavailable)
    }

    @MainActor func testPresentationKeepsTheSameStreamOriginAndNativePiPOwner() {
        let source = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo.mp4")!)
        let session = SportsPlaybackSession()
        let origin = SportsPlaybackOrigin()
        session.play(title: "Game", url: source.url, sources: [source], origin: origin)
        let identity = session.item?.id, owner = UUID()
        session.pictureInPicture.attach(owner: owner, capability: .available, request: {}, stop: {})
        session.expand()
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, source.url)
        XCTAssertTrue(session.origin === origin)
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner), "Presentation must not replace the actual PiP/player driver")
        XCTAssertEqual(session.reload, 0)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertTrue(session.isPiPActive)
        session.pictureInPicture.didStop(owner: owner, restoring: true)
        XCTAssertTrue(session.isExpanded)
        XCTAssertTrue(session.pictureInPicture.owns(owner: owner))
        XCTAssertEqual(session.item?.id, identity)
        session.close()
        XCTAssertNil(session.origin, "Closing must release the old return card before another game opens")
    }

    @MainActor func testOnlyConfirmedSystemPiPHidesPlayerAndRestoreKeepsSource() {
        let first = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let second = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession()
        session.play(title: "Away vs Home", url: first.url, sources: [first, second])
        let identity = session.item?.id
        session.selectSource(second)
        let owner = UUID()
        var requested = 0, stopped = 0
        session.pictureInPicture.attach(owner: owner, capability: .available, request: { requested += 1 }, stop: { stopped += 1 })
        session.requestPictureInPicture()
        XCTAssertEqual(requested, 1)
        XCTAssertTrue(session.isExpanded, "An attempted request must not hide the player.")
        XCTAssertFalse(session.isPiPActive)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertTrue(session.isPiPActive)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
        XCTAssertEqual(session.sourceTitle, "Bravo")
        session.expand()
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(session.isPiPActive, "Restore waits for the real PiP stop callback.")
        session.pictureInPicture.didStop(owner: owner, restoring: true)
        XCTAssertTrue(session.isExpanded)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
    }

    @MainActor func testOnlyExplicitCloseEndsSessionAndInvalidSourceIsIgnored() {
        let source = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let session = SportsPlaybackSession()
        session.play(title: "Game", url: source.url, sources: [source])
        let identity = session.item?.id
        session.selectSource(SportsStream(title: "Unknown", url: URL(string: "https://example.com/other")!))
        XCTAssertEqual(session.item?.url, source.url)
        session.play(title: "Insecure", url: URL(string: "http://example.com/insecure")!)
        XCTAssertEqual(session.item?.id, identity)
        session.expand()
        XCTAssertEqual(session.item?.id, identity)
        session.close()
        XCTAssertNil(session.item)
        XCTAssertFalse(session.isExpanded)
        XCTAssertFalse(session.isMinimized)
        XCTAssertEqual(session.reload, 0)
        XCTAssertFalse(session.direct)
    }

    @MainActor func testUnsupportedAndStaleDriversNeverHideOrReplacePlayer() {
        let first = SportsStream(title: "Alpha", url: URL(string: "https://example.com/alpha")!)
        let second = SportsStream(title: "Bravo", url: URL(string: "https://example.com/bravo")!)
        let session = SportsPlaybackSession()
        session.play(title: "Game", url: first.url, sources: [first, second])
        let identity = session.item?.id, owner = UUID()
        session.pictureInPicture.attach(owner: owner, capability: .unavailable, request: { XCTFail("Unsupported PiP must not request a fake window") }, stop: {})
        session.requestPictureInPicture()
        XCTAssertTrue(session.isExpanded)
        XCTAssertNotNil(session.pictureInPicture.message)
        session.selectSource(second)
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertFalse(session.isPiPActive)
        XCTAssertEqual(session.item?.id, identity)
        XCTAssertEqual(session.item?.url, second.url)
        session.close()
        session.pictureInPicture.didStart(owner: owner)
        XCTAssertNil(session.item)
    }
}
