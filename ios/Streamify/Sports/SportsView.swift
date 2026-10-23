import SwiftUI
import Combine

@MainActor
final class SportsWatchQueue: ObservableObject {
    @Published var streams: [SportsStream] = []
    func add(_ stream: SportsStream) {
        guard streams.count < 4, !streams.contains(where: { $0.id == stream.id }) else { return }
        streams.append(stream)
    }
    func remove(_ stream: SportsStream) { streams.removeAll { $0.id == stream.id } }
}

private enum SportsFilter: String, CaseIterable, Identifiable {
    case all = "All games", live = "Live", upcoming = "Upcoming", final = "Final", following = "Following"
    var id: String { rawValue }
}

struct SportsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var queue = SportsWatchQueue()
    @State private var league: SportsLeague?
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var filter: SportsFilter = .all
    @State private var carousel = false
    @State private var channels = false
    @State private var query = ""
    @State private var games: [SportsGame] = []
    @State private var teams: [SportsTeamResult] = []
    @State private var loading = true
    @State private var teamLoading = false
    @State private var error: String?
    @State private var searchError: String?
    @State private var partial = false
    @State private var selectedGame: SportsGame?
    @State private var selectedTeam: SportsTeamResult?
    @State private var showMultiWatch = false
    @State private var showCalendar = false
    @State private var revision = 0

    private var requestKey: String { "\(league?.rawValue ?? "all")-\(day.timeIntervalSince1970)-\(revision)-\(scenePhase == .active)-\(settings.apiBase)-\(channels)" }
    private var filteredGames: [SportsGame] {
        games.filter { game in
            let status: Bool
            switch filter {
            case .all: status = true
            case .live: status = game.isLive
            case .final: status = game.isFinal
            case .upcoming: status = game.state == "pre" && game.date.map { (0...7200).contains($0.timeIntervalSinceNow) } == true
            case .following: status = library.followedTeams.contains(game.home.key(in: game.league)) || library.followedTeams.contains(game.away.key(in: game.league))
            }
            return status && (query.isEmpty || "\(game.home.name) \(game.away.name) \(game.league.title) \(game.league.sport)".localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                intro
                searchField
                leagueDirectory
                if channels && query.isEmpty {
                    SportsChannelsView()
                } else {
                    if !query.isEmpty { teamResults }
                    scheduleControls
                    dayStrip
                    filters
                    if loading && games.isEmpty { ProgressView("Loading games…").frame(maxWidth: .infinity).padding(32) }
                    if let error { StateMessage(symbol: "wifi.exclamationmark", title: "Schedule unavailable", message: error, actionTitle: "Retry", action: { revision += 1 }) }
                    if partial { Label("Some feeds are unavailable. Showing the games that loaded.", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(AppTheme.muted).padding(.horizontal, 20) }
                    gameList
                    if !loading && error == nil && filteredGames.isEmpty {
                        StateMessage(symbol: "sportscourt", title: filter == .following ? "No followed teams playing" : "No games to show", message: filter == .upcoming ? "Upcoming includes games starting within two hours. Try All games or another day." : "Try another date, league, or filter. Follow teams from their profile to personalize this view.")
                    }
                    Text("Scores and schedules by ESPN").font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
                }
            }.padding(.top, 12).padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await loadSchedule() }
        .task(id: requestKey) {
            guard scenePhase == .active, !channels else { return }
            games = []
            error = nil
            partial = false
            repeat {
                await loadSchedule()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            } while !Task.isCancelled
        }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, teams.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                teamLoading = true
                defer { teamLoading = false }
                var loaded: [SportsTeamResult] = []
                var failures: [String] = []
                for selected in SportsLeague.allCases {
                    do { loaded += try await SportsService().teams(league: selected) }
                    catch is CancellationError { return }
                    catch { failures.append(selected.title) }
                    try Task.checkCancellation()
                }
                teams = loaded
                searchError = failures.isEmpty ? nil : "Team search is unavailable for \(failures.joined(separator: ", "))."
            } catch { }
        }
        .sheet(item: $selectedGame) { game in
            NavigationStack { SportsGameView(game: game).environmentObject(queue) }
        }
        .sheet(item: $selectedTeam) { team in
            NavigationStack { SportsTeamView(result: team).environmentObject(queue) }
        }
        .sheet(isPresented: $showMultiWatch) { NavigationStack { SportsMultiWatchView().environmentObject(queue) } }
        .sheet(isPresented: $showCalendar) {
            NavigationStack {
                DatePicker("Game date", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding().tint(AppTheme.accent)
                    .navigationTitle("Choose a day").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { day = Calendar.current.startOfDay(for: day); showCalendar = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every game. Your teams.").font(.title2.bold())
            Text("Scores, schedules, and a front-row seat.").font(.subheadline).foregroundStyle(AppTheme.muted)
            HStack {
                Label("GAME DAY", systemImage: "dot.radiowaves.left.and.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
                Spacer()
                Button { showMultiWatch = true } label: { Label("Multi-watch · \(queue.streams.count)/4", systemImage: "rectangle.split.2x2").font(.caption.weight(.semibold)).padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12)) }
                    .buttonStyle(.plain).accessibilityLabel("Open multi-watch. \(queue.streams.count) of four slots used")
            }
        }.padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
            TextField("Search teams & games", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted) }.accessibilityLabel("Clear sports search") }
        }.padding(14).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
    }

    private var leagueDirectory: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                leagueTile(title: "All", selected: league == nil && !channels, tint: AppTheme.accent) { Image(systemName: "sportscourt.fill").font(.title2) } action: { league = nil; channels = false }
                ForEach(SportsLeague.allCases) { item in
                    leagueTile(title: item.title, selected: league == item && !channels, tint: item.accent) { Image("league-\(item.rawValue)").resizable().scaledToFit().frame(width: 36, height: 36) } action: { league = item; channels = false }
                }
                leagueTile(title: "Channels", selected: channels, tint: AppTheme.accent) { Image(systemName: "tv").font(.title2) } action: { channels = true; query = "" }
            }.padding(.horizontal, 20)
        }
    }

    private func leagueTile<Content: View>(title: String, selected: Bool, tint: Color, @ViewBuilder icon: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) { icon().frame(height: 36); Text(title).font(.caption.weight(.semibold)).lineLimit(1) }
                .frame(width: 78, height: 84).background(selected ? tint.opacity(0.16) : AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? tint : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scheduleControls: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(league?.title ?? "All leagues") schedule").font(.title3.bold())
                Text(day.formatted(.dateTime.month(.wide).day().year())).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Button { showCalendar = true } label: { Image(systemName: "calendar").frame(width: 44, height: 44).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12)) }.accessibilityLabel("Choose game date")
            Button { carousel.toggle() } label: { Image(systemName: carousel ? "list.bullet" : "rectangle.split.2x1").frame(width: 44, height: 44).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12)) }.accessibilityLabel(carousel ? "Switch to list view" : "Switch to carousel view")
        }.buttonStyle(.plain).padding(.horizontal, 20)
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(-3..<11, id: \.self) { offset in
                    let value = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    let selected = Calendar.current.isDate(value, inSameDayAs: day)
                    Button { day = value } label: {
                        VStack(spacing: 7) {
                            Text(Calendar.current.isDateInToday(value) ? "TODAY" : value.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(size: 9, weight: .bold))
                            Text(value.formatted(.dateTime.day())).font(.title3.bold().monospacedDigit())
                        }.frame(width: 57, height: 65).foregroundStyle(selected ? Color.white : .primary)
                            .background(selected ? AppTheme.accent : AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityLabel(value.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.horizontal, 20)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(SportsFilter.allCases) { item in Pill(title: item.rawValue, selected: filter == item) { filter = item } } }.padding(.horizontal, 20)
        }
    }

    @ViewBuilder private var gameList: some View {
        if carousel && !filteredGames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) { ForEach(filteredGames) { game in SportsGameCard(game: game) { selectedGame = game }.frame(width: 300) } }.padding(.horizontal, 20)
            }
        } else {
            ForEach(filteredGames) { game in SportsGameCard(game: game) { selectedGame = game }.padding(.horizontal, 20) }
        }
    }

    private var teamResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teams").font(.headline)
            if teamLoading { ProgressView("Searching teams…") }
            if let searchError { Text(searchError).font(.footnote).foregroundStyle(AppTheme.muted) }
            ForEach(teams.filter { "\($0.team.name) \($0.team.abbreviation) \($0.league.title) \($0.league.sport)".localizedCaseInsensitiveContains(query) }.prefix(12)) { item in
                Button { selectedTeam = item } label: {
                    HStack(spacing: 12) {
                        RemoteArtwork(url: item.team.logoURL, contentMode: .fit).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 3) { Text(item.team.name).font(.subheadline.weight(.semibold)); Text(item.league.title).font(.caption).foregroundStyle(AppTheme.muted) }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.muted)
                    }.padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 20)
    }

    private func loadSchedule() async {
        guard !channels else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await SportsService(backend: settings.apiBase).schedule(leagues: league.map { [$0] } ?? SportsLeague.allCases, day: day)
            try Task.checkCancellation()
            games = result.games
            partial = result.partial
            error = nil
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct SportsGameCard: View {
    let game: SportsGame
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 7) {
                    Image("league-\(game.league.rawValue)").resizable().scaledToFit().frame(width: 22, height: 22)
                    Text(game.league.title).font(.caption.weight(.bold)).foregroundStyle(game.league.accent)
                    Spacer()
                    if game.isLive { Text("● LIVE").font(.caption2.bold()).foregroundStyle(AppTheme.accent) }
                    else { Text(game.isFinal ? "FINAL" : game.date?.formatted(date: .omitted, time: .shortened) ?? "TBD").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted) }
                }
                SportsTeamScore(team: game.away, showScore: game.state != "pre")
                SportsTeamScore(team: game.home, showScore: game.state != "pre")
                Divider().overlay(AppTheme.muted.opacity(0.15))
                HStack { Text(game.status.isEmpty ? "Game center" : game.status).font(.caption).lineLimit(1).foregroundStyle(AppTheme.muted); Spacer(); Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
            }.padding(18).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(game.isLive ? AppTheme.accent.opacity(0.35) : game.league.accent.opacity(0.12)))
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}

struct SportsTeamScore: View {
    let team: SportsTeam
    var showScore = true
    var body: some View {
        HStack(spacing: 12) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) { Text(team.name).font(.subheadline.weight(.semibold)).lineLimit(2); if !team.record.isEmpty { Text(team.record).font(.caption2).foregroundStyle(AppTheme.muted) } }
            Spacer(minLength: 6)
            if showScore { Text(team.score.isEmpty ? "—" : team.score).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.7) }
        }
    }
}

struct SportsPanel<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View { VStack(alignment: .leading, spacing: 16, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20)) }
}
