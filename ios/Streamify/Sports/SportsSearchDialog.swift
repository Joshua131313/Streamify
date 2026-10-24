import SwiftUI

/// Search owns its query and scope so the schedule beneath it keeps its place.
@MainActor
struct SportsSearchDialog: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var queue: SportsWatchQueue
    @EnvironmentObject private var playback: SportsPlaybackSession
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var search = ""
    @State private var league: SportsLeague?
    @State private var games: [SportsGame] = []
    @State private var teams: [SportsTeamResult] = []
    @State private var teamsLoading = true
    @State private var gamesLoading = true
    @State private var teamError: String?
    @State private var gameError: String?
    @State private var recents: [String] = []
    @State private var selectedGame: SportsGame?
    @State private var selectedTeam: SportsTeamResult?
    @State private var revision = 0
    @State private var hasFocused = false

    init(day: Date, initialGames: [SportsGame]) {
        self.day = day
        _games = State(initialValue: initialGames)
    }

    private var defaults: UserDefaults {
        #if DEBUG
        if PreviewFixtures.enabled { return PreviewFixtures.defaults }
        #endif
        return .standard
    }
    private let recentsKey = "streamify.ios.sportsSearch.recents"
    private var words: [String] { search.split(whereSeparator: \.isWhitespace).map(String.init) }
    private func matches(_ text: String) -> Bool {
        words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    private var matchingTeams: [SportsTeamResult] {
        teams.filter { (league == nil || $0.league == league) && matches("\($0.team.name) \($0.team.abbreviation) \($0.league.title) \($0.league.sport)") }
            .sorted { $0.team.name.localizedStandardCompare($1.team.name) == .orderedAscending }
    }
    private var matchingGames: [SportsGame] {
        games.filter { (league == nil || $0.league == league) && matches("\($0.home.name) \($0.home.abbreviation) \($0.away.name) \($0.away.abbreviation) \($0.league.title) \($0.league.sport)") }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Pill(title: "All leagues", selected: league == nil) { league = nil }
                        ForEach(SportsLeague.allCases) { item in
                            Pill(title: item.title, selected: league == item) { league = item }
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 14)
                }.accessibilityIdentifier("sports-search-scope")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if search.isEmpty { suggestions }
                        else { results }
                    }.padding(20).padding(.bottom, 24)
                }.scrollDismissesKeyboard(.interactively)
            }
            .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false; remember() }.frame(minHeight: 44)
                        .accessibilityIdentifier("dismiss-sports-search-keyboard")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sports-search-dialog")
            .accessibilityAction(.escape) { focused = false; dismiss() }
            .task {
                recents = Array((defaults.stringArray(forKey: recentsKey) ?? []).prefix(8))
            }
            .searchPresentationReady {
                guard !hasFocused else { return }
                hasFocused = true
                focused = true
            }
            .task(id: revision) {
                let request = revision
                async let teamLoad: Void = loadTeams(request: request)
                async let gameLoad: Void = loadGames(request: request)
                _ = await (teamLoad, gameLoad)
            }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    try Task.checkCancellation()
                    search = query.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch { }
            }
            .sheet(item: $selectedGame) { game in
                NavigationStack { SportsGameView(game: game).environmentObject(queue) }
            }
            .sheet(item: $selectedTeam) { team in
                NavigationStack { SportsTeamView(result: team).environmentObject(queue) }
            }
            .onChange(of: playback.item?.id) { _, _ in
                if playback.isExpanded { focused = false }
            }
            .onChange(of: playback.isExpanded) { _, expanded in
                if expanded { focused = false }
            }
            .onChange(of: playback.isPiPActive) { _, active in
                if active { dismiss() }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                TextField("Teams, games or leagues", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .focused($focused).onSubmit { focused = false; remember() }
                    .accessibilityIdentifier("sports-dialog-search")
                if !query.isEmpty {
                    Button { query = ""; search = ""; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted).frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear sports search")
                }
            }.padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 48).streamifyControlSurface()
            Button("Cancel") { focused = false; dismiss() }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                .accessibilityIdentifier("close-sports-search")
        }.buttonStyle(HapticPlainButtonStyle()).padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !recents.isEmpty {
                HStack {
                    Text("Recent searches").font(.headline)
                    Spacer()
                    Button("Clear") { recents = []; defaults.removeObject(forKey: recentsKey) }
                        .font(.subheadline).foregroundStyle(AppTheme.muted).frame(minHeight: 44)
                        .accessibilityLabel("Clear recent sports searches")
                }
                ForEach(recents, id: \.self) { value in
                    Button { query = value; search = value; focused = false } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(AppTheme.muted)
                            Text(value).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.left").foregroundStyle(AppTheme.muted)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-search-recent-\(value)")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Find your next game").font(.title2.bold())
                Text("Search team names, abbreviations or leagues. Team profiles include results and rosters.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                Text("Game results are for \(day.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
    }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teams").font(.title3.bold())
            if teamsLoading && teams.isEmpty { ProgressView("Finding teams…") }
            if let teamError { errorNotice(teamError) }
            ForEach(matchingTeams.prefix(50)) { item in
                Button { focused = false; remember(); selectedTeam = item } label: {
                    HStack(spacing: 12) {
                        RemoteArtwork(url: item.team.logoURL, contentMode: .fit).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.team.name).font(.subheadline.weight(.semibold))
                            Text("\(item.league.title) · \(item.team.abbreviation)").font(.caption).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.muted)
                    }.padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-search-team-\(item.id)")
            }
            if !teamsLoading && matchingTeams.isEmpty && teamError == nil {
                Text("No matching teams").font(.subheadline).foregroundStyle(AppTheme.muted)
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("Games").font(.title3.bold())
            Text(day.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(AppTheme.muted)
            if gamesLoading && games.isEmpty { ProgressView("Finding games…") }
            if let gameError { errorNotice(gameError) }
            ForEach(matchingGames.prefix(30)) { game in
                SportsGameCard(game: game) { focused = false; remember(); selectedGame = game }
            }
            if !gamesLoading && matchingGames.isEmpty && gameError == nil {
                Text("No matching games on this date. Try a team profile for its full schedule.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(message).font(.footnote).foregroundStyle(AppTheme.muted)
            Spacer()
            Button("Retry") { revision += 1 }.font(.footnote.weight(.semibold)).frame(minHeight: 44)
        }
    }
    private func remember() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        recents.removeAll { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
        recents.insert(String(value.prefix(100)), at: 0)
        recents = Array(recents.prefix(8))
        defaults.set(recents, forKey: recentsKey)
    }
    private func loadGames(request: Int) async {
        guard request == revision, !Task.isCancelled else { return }
        gamesLoading = true
        gameError = nil
        defer { if request == revision && !Task.isCancelled { gamesLoading = false } }
        do {
            let result = try await SportsService(backend: settings.apiBase).schedule(leagues: SportsLeague.allCases, day: day)
            try Task.checkCancellation()
            guard request == revision else { return }
            games = result.games
            if result.partial { gameError = "Some league schedules are unavailable. Showing games that loaded." }
        } catch is CancellationError { }
        catch {
            guard request == revision, !Task.isCancelled else { return }
            gameError = games.isEmpty ? "Games are unavailable right now. Team search is still available." : "Games could not be refreshed. Showing earlier results for this date."
        }
    }
    private struct TeamLoad: Sendable {
        let league: SportsLeague
        let teams: [SportsTeamResult]?
    }
    private func loadTeams(request: Int) async {
        guard request == revision, !Task.isCancelled else { return }
        teamsLoading = true
        teamError = nil
        defer { if request == revision && !Task.isCancelled { teamsLoading = false } }
        let loaded = await withTaskGroup(of: TeamLoad.self, returning: [TeamLoad].self) { group in
            for league in SportsLeague.allCases {
                group.addTask { TeamLoad(league: league, teams: try? await SportsService().teams(league: league)) }
            }
            var values: [TeamLoad] = []
            for await value in group { values.append(value) }
            return values
        }
        guard request == revision, !Task.isCancelled else { return }
        let unavailable = Set(loaded.filter { $0.teams == nil }.map(\.league))
        let previous = teams.filter { unavailable.contains($0.league) }
        var seen = Set<String>()
        teams = (loaded.flatMap { $0.teams ?? [] } + previous).filter { seen.insert($0.id).inserted }
        let failed = unavailable.map(\.title).sorted()
        if !failed.isEmpty {
            teamError = "Team search is unavailable for \(failed.joined(separator: ", "))." + (previous.isEmpty ? "" : " Showing earlier results where available.")
        }
    }
}
