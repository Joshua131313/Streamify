import Foundation
import Combine
import UIKit

struct SportsPlaybackItem: Identifiable {
    let id: UUID
    let title: String
    var url: URL
    let sources: [SportsStream]
    let game: SportsGame?
}

enum SportsPlaybackPresentation: Equatable { case expanded, systemPictureInPicture }

/// Owned by the app, never by a recyclable schedule row or a presented sheet.
/// Scene activation does not replace the item, source, or playback surface.
@MainActor
final class SportsPlaybackSession: ObservableObject {
    @Published private(set) var item: SportsPlaybackItem?
    @Published private(set) var presentation: SportsPlaybackPresentation = .expanded
    @Published private(set) var reload = 0
    @Published private(set) var direct = false
    @Published private(set) var safeAreaInsets = UIEdgeInsets.zero
    @Published private(set) var origin: SportsPlaybackOrigin?
    @Published private(set) var liveGames: [SportsGame] = []
    @Published private(set) var gamesLoading = false
    @Published private(set) var gamesError: String?
    @Published private(set) var switchingGameID: String?
    @Published var gameSelectionError: String?
    private var backend = ""
    private var selectionToken = UUID()
    private var scheduleToken = UUID()
    private var rememberedSources: [String: URL] = [:]
    private var readPreferredServer: () -> String? = { nil }
    private var savePreferredServer: (String) -> Void = { _ in }
    private let loadSchedule: (SportsService) async throws -> SportsSchedule
    private let loadStreams: (SportsService, SportsGame) async throws -> [SportsStream]
    let pictureInPicture = SportsSystemPiP()

    var isExpanded: Bool { item != nil && presentation == .expanded }
    var isPiPActive: Bool { item != nil && presentation == .systemPictureInPicture }
    // Existing context sheets dismiss only after confirmed system PiP starts.
    var isMinimized: Bool { isPiPActive }
    var sourceTitle: String { item.flatMap { item in item.sources.first { $0.url == item.url }?.title } ?? "Current source" }

    init(loadSchedule: @escaping (SportsService) async throws -> SportsSchedule = {
        try await $0.schedule(leagues: SportsLeague.allCases, day: Date())
    }, loadStreams: @escaping (SportsService, SportsGame) async throws -> [SportsStream] = {
        try await $0.streams($1)
    }) {
        self.loadSchedule = loadSchedule
        self.loadStreams = loadStreams
        pictureInPicture.onStateChange = { [weak self] active, restoring in
            guard let self, self.item != nil else { return }
            if active { self.presentation = .systemPictureInPicture }
            else if restoring { self.presentation = .expanded }
            else { self.close() }
        }
    }

    func configureSourcePreference(read: @escaping () -> String?, write: @escaping (String) -> Void) {
        readPreferredServer = read; savePreferredServer = write
    }

    func preferredSource(in sources: [SportsStream]) -> SportsStream? {
        SportsServerPreference.source(in: sources, preference: readPreferredServer())
    }

    func play(title: String, url: URL, sources: [SportsStream] = [], origin: SportsPlaybackOrigin? = nil, game: SportsGame? = nil, rememberSource: Bool = false) {
        guard sportsHTTPSURL(url.absoluteString) != nil else { return }
        var seen = Set<URL>()
        var choices = sources.flatMap(\.availableSources).filter { seen.insert($0.url).inserted }
        if !seen.contains(url) { choices.insert(SportsStream(title: "Current source", url: url), at: 0) }
        if rememberSource, let selected = choices.first(where: { $0.url == url }) { savePreferredServer(selected.title) }
        if item?.url == url, item?.title == title, item?.game?.id == game?.id {
            if let origin { self.origin = origin }
            expand(); return
        }
        pictureInPicture.reset()
        invalidateRequests()
        rememberedSources = game.map { [$0.id: url] } ?? [:]
        self.origin = origin
        item = SportsPlaybackItem(id: UUID(), title: title, url: url, sources: choices, game: game)
        reload = 0; direct = false; presentation = .expanded
    }

    func selectSource(_ source: SportsStream) {
        guard var current = item,
              current.sources.contains(where: { $0.url == source.url }) else { return }
        savePreferredServer(source.title)
        guard current.url != source.url else { return }
        current.url = source.url
        if let game = current.game { rememberedSources[game.id] = source.url }
        pictureInPicture.reset()
        item = current
        reload = 0; direct = false
    }

    func configureBackend(_ value: String) { backend = value }

    /// The same response cache used by the schedule supplies real live choices.
    /// A refresh never changes the stream already playing, even if it has ended.
    func refreshLiveGames(forceReload: Bool = false) async {
        guard let identity = item?.id, !gamesLoading else { return }
        let token = UUID()
        scheduleToken = token
        gamesLoading = true
        defer { if scheduleToken == token { gamesLoading = false } }
        do {
            let schedule = try await loadSchedule(SportsService(backend: backend, forceReload: forceReload))
            try Task.checkCancellation()
            guard item?.id == identity, scheduleToken == token else { return }
            let games = SportsScheduleDayPolicy.canonicalGames(schedule.games).filter(\.isLive)
            if liveGames != games { liveGames = games }
            gamesError = schedule.partial ? "Some leagues could not be refreshed." : nil
        } catch is CancellationError { return }
        catch {
            guard item?.id == identity, scheduleToken == token else { return }
            gamesError = error.localizedDescription
        }
    }

    /// Resolve the next game's own sources before replacing anything visible.
    /// Keeping the item identity retains the one WebKit/player surface; only its
    /// selected URL changes. Failed or stale requests leave playback untouched.
    func selectGame(_ game: SportsGame) async {
        guard let current = item, isExpanded, current.game?.id != game.id,
              liveGames.contains(where: { $0.id == game.id && $0.isLive }) else { return }
        let token = UUID()
        selectionToken = token
        switchingGameID = game.id
        gameSelectionError = nil
        defer { if selectionToken == token { switchingGameID = nil } }
        do {
            var seen = Set<URL>()
            let loaded = try await loadStreams(SportsService(backend: backend), game)
            try Task.checkCancellation()
            let choices = loaded.flatMap(\.availableSources).filter { seen.insert($0.url).inserted }
            guard item?.id == current.id, selectionToken == token, isExpanded else { return }
            guard liveGames.contains(where: { $0.id == game.id && $0.isLive }) else {
                gameSelectionError = "This game is no longer live. Your current stream is still playing."
                return
            }
            guard let source = choices.first(where: { $0.url == rememberedSources[game.id] }) ?? preferredSource(in: choices) else {
                gameSelectionError = "No stream is available for this game yet. Your current stream is still playing."
                return
            }
            if let previous = item?.game { rememberedSources[previous.id] = item?.url }
            rememberedSources[game.id] = source.url
            // A channel can carry several schedule entries. When only the game
            // metadata changes, WebKit keeps its existing document and will not
            // run beginSession again; retain its PiP/fullscreen driver as well.
            if item?.url != source.url || reload != 0 || direct { pictureInPicture.reset() }
            // A different matchup must not collapse into the original game's card.
            origin = nil
            item = SportsPlaybackItem(id: current.id,
                title: "\(game.away.abbreviation) vs \(game.home.abbreviation)",
                url: source.url, sources: choices, game: game)
            reload = 0; direct = false
        } catch is CancellationError { return }
        catch {
            guard item?.id == current.id, selectionToken == token else { return }
            gameSelectionError = error.localizedDescription
        }
    }

    private func invalidateRequests() {
        selectionToken = UUID(); scheduleToken = UUID()
        switchingGameID = nil; gamesLoading = false
        gameSelectionError = nil; gamesError = nil
    }
    func reloadCurrent() { guard item != nil else { return }; pictureInPicture.reset(); reload += 1 }
    func toggleDirect() { guard item != nil else { return }; pictureInPicture.reset(); direct.toggle() }
    func requestPictureInPicture() { guard item != nil else { return }; pictureInPicture.request() }
    func expand() {
        guard item != nil else { return }
        if pictureInPicture.isActive { pictureInPicture.restore() }
        else { presentation = .expanded }
    }
    func close() {
        invalidateRequests()
        pictureInPicture.reset()
        item = nil
        origin = nil
        liveGames = []; rememberedSources = [:]
        reload = 0; direct = false; presentation = .expanded
    }
    func updateSafeArea(_ value: UIEdgeInsets) { if safeAreaInsets != value { safeAreaInsets = value } }
}
