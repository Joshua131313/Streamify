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
    func selectSource(streamID: String, url: URL) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }),
              streams[index].url != url,
              streams[index].availableSources.contains(where: { $0.url == url }) else { return }
        let existing = streams[index]
        streams[index] = SportsStream(title: existing.title, url: url,
            alternatives: existing.availableSources, stableID: existing.id)
    }
}

private enum SportsFilter: String, CaseIterable, Identifiable {
    case all = "All games", live = "Live", upcoming = "Upcoming", final = "Final", following = "Following"
    var id: String { rawValue }
}

private enum SportsLayout: String, CaseIterable, Identifiable {
    case list = "List", slider = "Slider", calendar = "Calendar"
    var id: String { rawValue }
}

struct SportsView: View {
    var searchRequest = 0
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: SportsPlaybackSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var queue = SportsWatchQueue()
    @State private var selectedLeagues = Set(SportsLeague.allCases)
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var filter: SportsFilter = .all
    @State private var layout: SportsLayout = .list
    @State private var home = true
    @State private var channels = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var handledSearchRequest = 0
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
    @State private var showLeaguePicker = false
    @State private var revision = 0
    @State private var calendarMarkers: [Date: Set<SportsLeague>] = [:]
    @State private var calendarUnavailable = Set<SportsLeague>()
    @State private var calendarLoading = false
    @State private var calendarLoadedAt: Date?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var lastDay: Date { Calendar.current.date(byAdding: .day, value: 13, to: today) ?? today }

    private var leagues: [SportsLeague] { SportsLeague.allCases.filter { selectedLeagues.contains($0) } }
    private var league: SportsLeague? { leagues.count == 1 ? leagues.first : nil }
    private var leagueTitle: String { selectedLeagues.count == SportsLeague.allCases.count ? "All leagues" : leagues.map(\.title).joined(separator: " + ") }
    private var requestKey: String { "\(leagues.map(\.rawValue).joined(separator: ","))-\(day.timeIntervalSince1970)-\(revision)-\(scenePhase == .active)-\(settings.apiBase)-\(channels)" }
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
        GeometryReader { viewport in
        ScrollViewReader { scroll in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !home || !query.isEmpty {
                    HStack(spacing: 8) {
                        Button { if !query.isEmpty { query = "" } else { chooseLeague(nil, showHome: true) } } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.accessibilityLabel("Back to sports home")
                        Text(!query.isEmpty ? "Search sports" : channels ? "Sports channels" : "\(leagueTitle) schedule").font(.headline)
                        Spacer()
                    }.buttonStyle(.plain).padding(.horizontal, 12)
                }
                if home && query.isEmpty { intro }
                searchField
                if query.isEmpty { gameDayBar }
                leagueDirectory
                if home && query.isEmpty { allLeaguesEntry }
                if channels && query.isEmpty {
                    SportsChannelsView()
                } else {
                    if !query.isEmpty { teamResults }
                    if home && query.isEmpty {
                        scheduleStatus
                        sportsHome
                    }
                    else {
                        filters
                        if filter != .live {
                            scheduleControls
                            if filter != .final {
                                if layout == .calendar { calendarGrid } else { dayStrip }
                                calendarLegend
                                dayNavigation
                            }
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            scheduleStatus
                            gameList.opacity(loading ? 0 : 1).allowsHitTesting(!loading)
                            if !loading && error == nil && filteredGames.isEmpty {
                                StateMessage(symbol: "sportscourt", title: filter == .following ? "No followed teams playing" : "No games to show", message: filter == .upcoming ? "Upcoming includes games starting within two hours. Try All games or another day." : "Try another date, league, or filter. Follow teams from their profile to personalize this view.")
                            }
                        }
                        // Enough trailing content prevents ScrollView from clamping its
                        // offset when a calendar day has fewer games than the previous one.
                        .frame(minHeight: layout == .calendar ? viewport.size.height : 0, alignment: .top)
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                    }
                    Text("Scores refresh every minute. Times are local. Scores and schedules by ESPN.").font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
                }
            }.padding(.top, 12).padding(.bottom, 110)
        }
        .foregroundStyle(AppTheme.foreground)
        .accessibilityIdentifier("sports-screen")
        .onChange(of: today) { _, value in day = min(lastDay, max(value, day)) }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if searchFocused {
                    Spacer()
                    Button("Done") { searchFocused = false }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("dismiss-sports-search")
                }
            }
        }
        .onDisappear { searchFocused = false }
        .onChange(of: playback.isMinimized) { _, minimized in
            guard minimized else { return }
            selectedGame = nil
            selectedTeam = nil
            showMultiWatch = false
        }
        .task(id: searchRequest) {
            guard searchRequest > 0, searchRequest != handledSearchRequest else { return }
            handledSearchRequest = searchRequest
            withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo("sports-search-field", anchor: .top) }
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                searchFocused = true
            } catch { }
        }
        .refreshable { await loadSchedule() }
        .task(id: requestKey) {
            guard scenePhase == .active, !channels else { return }
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
        .task(id: "\(home)-\(channels)-\(filter.rawValue)-\(scenePhase == .active)-\(today.timeIntervalSince1970)") {
            guard !home, !channels, filter != .live, filter != .final, scenePhase == .active else { return }
            if let calendarLoadedAt, Date().timeIntervalSince(calendarLoadedAt) < 600, calendarUnavailable.isEmpty { return }
            await loadCalendarMarkers()
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
                DatePicker("Game date", selection: Binding(get: { day }, set: selectDay), in: today...lastDay, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding().tint(AppTheme.foreground)
                    .navigationTitle("Choose a day").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { day = Calendar.current.startOfDay(for: day); showCalendar = false } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLeaguePicker) {
            SportsLeaguePicker(selected: selectedLeagues) { values in
                selectedLeagues = values
                searchFocused = false
                channels = false
                home = false
                query = ""
                showLeaguePicker = false
            }
        }
        }
        }
    }

    @ViewBuilder private var scheduleStatus: some View {
        if loading {
            ProgressView("Loading games…").frame(maxWidth: .infinity).frame(height: 44)
                .accessibilityIdentifier("sports-schedule-loading")
        }
        if let error { StateMessage(symbol: "wifi.exclamationmark", title: "Schedule unavailable", message: error, actionTitle: "Retry", action: { revision += 1 }) }
        if partial { Label("Some feeds are unavailable. Showing the games that loaded.", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(AppTheme.muted).padding(.horizontal, 20) }
    }

    private var allLeaguesEntry: some View {
        HStack(spacing: 10) {
            Button { chooseLeague(nil) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All leagues schedule").font(.subheadline.weight(.semibold))
                        Text("Games, results & calendar").font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.subheadline)
                }.padding(14).frame(minHeight: 58).streamifyControlSurface(cornerRadius: 14)
            }.accessibilityIdentifier("sports-all-leagues-schedule")
            Button { showLeaguePicker = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 58).streamifyControlSurface(cornerRadius: 14) }
                .accessibilityLabel("Choose leagues").accessibilityIdentifier("sports-home-league-picker")
        }.buttonStyle(.plain).padding(.horizontal, 20)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every game. Your teams.").font(.title2.bold())
            Text("Scores, schedules, and a front-row seat.").font(.subheadline).foregroundStyle(AppTheme.muted)
        }.padding(.horizontal, 20)
    }

    private var gameDayBar: some View {
        HStack {
            Text("GAME DAY").font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted)
            Spacer()
            Button { searchFocused = false; showMultiWatch = true } label: { Label("Multi-watch · \(queue.streams.count)/4", systemImage: "rectangle.split.2x2").font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44).streamifyControlSurface() }
                .buttonStyle(.plain).accessibilityLabel("Open multi-watch. \(queue.streams.count) of four slots used")
                .accessibilityIdentifier("sports-multi-watch")
        }.padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
            TextField("Search teams & games", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("sports-search-field")
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.muted) }.accessibilityLabel("Clear sports search") }
        }.padding(14).streamifyControlSurface(cornerRadius: 14).padding(.horizontal, 20)
            .id("sports-search-field")
    }

    private var leagueDirectory: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                leagueTile(title: "All", selected: home && !channels, tint: AppTheme.foreground) { Image(systemName: "house").font(.title2) } action: { chooseLeague(nil, showHome: true) }
                leagueTile(title: "Live now", selected: !home && filter == .live && !channels, tint: AppTheme.accent) { Image(systemName: "dot.radiowaves.left.and.right").font(.title2).foregroundStyle(filter == .live && !home ? AppTheme.accent : AppTheme.muted) } action: { chooseLeague(nil); filter = .live }
                ForEach(SportsLeague.allCases) { item in
                    leagueTile(title: item.title, selected: league == item && !channels, tint: item.accent) { Image("league-\(item.rawValue)").resizable().scaledToFit().frame(width: 36, height: 36) } action: { chooseLeague(item) }
                }
                leagueTile(title: "Channels", selected: channels, tint: AppTheme.foreground) { Image(systemName: "tv").font(.title2) } action: { searchFocused = false; channels = true; home = false; query = "" }
            }.padding(.horizontal, 20)
        }.accessibilityIdentifier("sports-league-directory")
    }

    private func leagueTile<Content: View>(title: String, selected: Bool, tint: Color, @ViewBuilder icon: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) { icon().frame(height: 36); Text(title).font(.caption.weight(.semibold)).lineLimit(1) }
                .frame(width: 78, height: 84).background(selected ? AppTheme.foreground.opacity(0.14) : AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? AppTheme.muted.opacity(0.6) : AppTheme.border, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(title == "Channels" ? "sports-channels" : "sports-league-\(title)")
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if filter == .final { Text("Final results").font(.headline).frame(maxWidth: .infinity, alignment: .leading) }
                else {
                    Button { showCalendar = true } label: {
                        HStack {
                            Text(layout == .calendar ? "Jump to date" : day.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down").font(.caption)
                        }.padding(.horizontal, 12).frame(minHeight: 44).streamifyControlSurface()
                    }.accessibilityLabel("Jump to date")
                    Button("Today") { selectDay(today) }.font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).streamifyControlSurface()
                }
                Button { revision += 1 } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Refresh scores").disabled(loading)
            }
            if filter != .final {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(SportsLayout.allCases) { value in
                        Pill(title: value.rawValue, selected: layout == value) { layout = value }
                            .accessibilityIdentifier("sports-layout-\(value.rawValue)")
                    } }
                }
            }
        }.buttonStyle(.plain).padding(.horizontal, 20)
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<14, id: \.self) { offset in dateCell(offset).frame(width: 64) }
            }.padding(.horizontal, 20)
        }
    }

    private var calendarGrid: some View {
        SportsPanel {
            Text("Next 14 days").font(.headline)
            Text("\(today.formatted(.dateTime.month(.abbreviated).day())) to \(lastDay.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(AppTheme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                ForEach(0..<14, id: \.self) { offset in dateCell(offset) }
            }
        }.padding(.horizontal, 20).accessibilityElement(children: .contain).accessibilityIdentifier("sports-calendar-grid")
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private func dateCell(_ offset: Int) -> some View {
        let value = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
        let selected = Calendar.current.isDate(value, inSameDayAs: day)
        return Button { selectDay(value) } label: {
            VStack(spacing: 7) {
                Text(value.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).lineLimit(1)
                Text(value.formatted(.dateTime.day())).font(.subheadline.weight(selected ? .bold : .medium).monospacedDigit())
                HStack(spacing: 2) {
                    ForEach(leagues.filter { calendarMarkers[value]?.contains($0) == true }) { item in
                        Circle().fill(leagueDotColor(item)).frame(width: 4, height: 4)
                    }
                }.frame(height: 5)
            }.frame(maxWidth: .infinity, minHeight: 68)
                .foregroundStyle(selected ? AppTheme.canvas : AppTheme.foreground)
                .background(selected ? AppTheme.foreground : AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(offset == 0 && !selected ? AppTheme.muted.opacity(0.4) : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel(dateDescription(value)).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("sports-date-offset-\(offset)")
    }

    private var calendarLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ForEach(leagues) { item in
                    HStack(spacing: 5) { Circle().fill(leagueDotColor(item)).frame(width: 6, height: 6); Text(item.title).font(.caption2).foregroundStyle(AppTheme.muted) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("sports-calendar-league-\(item.rawValue)")
                }
            }
            if calendarLoading { HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Finding games over the next two weeks").font(.caption).foregroundStyle(AppTheme.muted) } }
            if !calendarUnavailable.intersection(selectedLeagues).isEmpty {
                Text("Some event markers are unavailable. Select a day to check its schedule.").font(.caption).foregroundStyle(AppTheme.muted)
            }
        }.padding(.horizontal, 20)
    }

    private func dateDescription(_ date: Date) -> String {
        let eventLeagues = leagues.filter { calendarMarkers[date]?.contains($0) == true }
        let state = calendarLoading ? "Loading games" : !eventLeagues.isEmpty ? eventLeagues.map(\.title).joined(separator: ", ") + " games" : calendarUnavailable.isEmpty ? "No games scheduled" : "Schedule markers unavailable"
        return date.formatted(date: .complete, time: .omitted) + ": " + state
    }

    private func leagueDotColor(_ league: SportsLeague) -> Color {
        switch league {
        case .nfl: return Color(red: 0.22, green: 0.61, blue: 0.96)
        case .nba: return Color(red: 0.94, green: 0.53, blue: 0.24)
        case .wnba: return Color(red: 0.86, green: 0.40, blue: 0.71)
        case .nhl: return Color(red: 0.27, green: 0.74, blue: 0.70)
        case .mlb: return Color(red: 0.58, green: 0.45, blue: 0.91)
        }
    }

    private var dayNavigation: some View {
        HStack {
            Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(day <= today).accessibilityLabel("Previous day")
            Text(Calendar.current.isDateInToday(day) ? "Today’s games" : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(day >= lastDay).accessibilityLabel("Next day")
        }.buttonStyle(.plain).padding(.horizontal, 20)
    }

    private func moveDay(_ offset: Int) {
        guard let value = Calendar.current.date(byAdding: .day, value: offset, to: day) else { return }
        selectDay(value)
    }

    private func selectDay(_ value: Date) {
        let value = min(lastDay, max(today, Calendar.current.startOfDay(for: value)))
        guard value != day else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { day = value }
    }

    private func chooseLeague(_ value: SportsLeague?, showHome: Bool = false) {
        searchFocused = false
        selectedLeagues = value.map { Set([$0]) } ?? Set(SportsLeague.allCases)
        home = showHome; channels = false; filter = .all; day = today; query = ""
    }

    private var sportsHome: some View {
        ForEach(SportsLeague.allCases) { item in
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image("league-\(item.rawValue)").resizable().scaledToFit().frame(width: 36, height: 36)
                    Text(item.title).font(.title2.bold())
                    Spacer()
                    Button("View all") { chooseLeague(item) }.font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).streamifyControlSurface()
                }.buttonStyle(.plain)
                ForEach(games.filter { $0.league == item }.prefix(3)) { game in SportsGameCard(game: game) { selectedGame = game } }
                if !loading && !games.contains(where: { $0.league == item }) {
                    Text(partial || error != nil ? "Schedule temporarily unavailable." : "No games scheduled today.").font(.subheadline).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.horizontal, 20)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showLeaguePicker = true } label: {
                    Label(selectedLeagues.count == SportsLeague.allCases.count ? "All leagues" : "Leagues (\(selectedLeagues.count))", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).streamifyControlSurface()
                }.buttonStyle(.plain).accessibilityValue(leagueTitle).accessibilityIdentifier("sports-league-picker")
                ForEach(SportsFilter.allCases) { item in
                    Pill(title: item.rawValue, selected: filter == item) { filter = item; if item == .live || item == .upcoming || item == .final { selectDay(today) } }
                }
            }.padding(.horizontal, 20)
        }
    }

    @ViewBuilder private var gameList: some View {
        if layout == .slider && filter != .live && !filteredGames.isEmpty {
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
        let requestedKey = requestKey
        loading = true
        defer { if requestedKey == requestKey { loading = false } }
        do {
            let result = try await SportsService(backend: settings.apiBase).schedule(leagues: leagues, day: day)
            try Task.checkCancellation()
            guard requestedKey == requestKey else { return }
            games = result.games
            partial = result.partial
            error = nil
        } catch is CancellationError { }
        catch { if !Task.isCancelled && requestedKey == requestKey { self.error = error.localizedDescription } }
    }

    private func loadCalendarMarkers() async {
        calendarLoading = true
        defer { calendarLoading = false }
        let start = today, end = lastDay
        let calendar = Calendar.current
        let jobs = SportsLeague.allCases.flatMap { item in (-1...14).compactMap { offset in calendar.date(byAdding: .day, value: offset, to: start).map { (item, $0) } } }
        do {
            let batches = try await withThrowingTaskGroup(of: SportsMarkerBatch.self, returning: [SportsMarkerBatch].self) { group in
                // Match Android's limit: three scoreboard requests at a time.
                for worker in 0..<3 {
                    group.addTask {
                        var batch = SportsMarkerBatch()
                        for index in stride(from: worker, to: jobs.count, by: 3) {
                            try Task.checkCancellation()
                            let (item, date) = jobs[index]
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd"
                            guard let url = URL(string: "\(item.endpoint)/scoreboard?dates=\(formatter.string(from: date))&limit=100") else { batch.unavailable.insert(item); continue }
                            var request = URLRequest(url: url); request.timeoutInterval = 20
                            do {
                                let (data, response) = try await URLSession.shared.data(for: request)
                                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["events"] is [[String: Any]] else { batch.unavailable.insert(item); continue }
                                batch.games += json.sportsObjects("events").compactMap { SportsService().parseGame($0, league: item) }
                            } catch is CancellationError { throw CancellationError() }
                            catch { try Task.checkCancellation(); batch.unavailable.insert(item) }
                        }
                        return batch
                    }
                }
                var results: [SportsMarkerBatch] = []
                for try await batch in group { results.append(batch) }
                return results
            }
            try Task.checkCancellation()
            var markers: [Date: Set<SportsLeague>] = [:]
            for game in batches.flatMap(\.games) {
                guard let date = game.date.map({ calendar.startOfDay(for: $0) }), date >= start, date <= end else { continue }
                markers[date, default: []].insert(game.league)
            }
            calendarMarkers = markers; calendarUnavailable = Set(batches.flatMap(\.unavailable)); calendarLoadedAt = Date()
        } catch { }
    }
}

private struct SportsMarkerBatch: Sendable {
    var games: [SportsGame] = []
    var unavailable = Set<SportsLeague>()
}

struct SportsGameCard: View {
    let game: SportsGame
    var action: () -> Void
    @EnvironmentObject private var playback: SportsPlaybackSession
    @State private var watchRevision = 0
    @State private var watchLoading = false
    @State private var watchError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if game.isLive { Circle().fill(AppTheme.accent).frame(width: 5, height: 5) }
                Text(game.isLive ? game.status : game.isFinal ? "FINAL" : game.date?.formatted(date: .omitted, time: .shortened) ?? "Time TBD")
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(game.league.title).font(.caption2.weight(.bold)).foregroundStyle(AppTheme.muted)
                Text(game.date?.formatted(.dateTime.month(.abbreviated).day()) ?? "TBD")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
            Button(action: action) {
                VStack(spacing: 12) {
                    matchTeam(game.away)
                    matchTeam(game.home)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityIdentifier("sports-game-\(game.id)")
            Rectangle().fill(AppTheme.border).frame(height: 0.5)
            HStack(spacing: 10) {
                Button(action: action) {
                    HStack(spacing: 7) {
                        Text("Game Center")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }.frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.controlFill, in: Capsule())
                        .overlay { Capsule().strokeBorder(AppTheme.border, lineWidth: 0.7) }
                }.buttonStyle(.plain)
                if game.canWatch {
                    Button { watchRevision += 1 } label: {
                        HStack(spacing: 7) {
                            if watchLoading { ProgressView().controlSize(.small).tint(AppTheme.canvas) }
                            else { Image(systemName: "play.fill").font(.system(size: 11)) }
                            Text("Watch")
                        }.frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(AppTheme.canvas).background(AppTheme.foreground, in: Capsule())
                    }.buttonStyle(.plain).disabled(watchLoading)
                        .accessibilityLabel("Watch \(game.away.abbreviation) vs \(game.home.abbreviation)")
                }
            }.font(.caption.weight(.semibold))
        }.padding(16).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .task(id: watchRevision) {
                guard watchRevision > 0 else { return }
                watchLoading = true
                defer { watchLoading = false }
                do {
                    let streams = try await SportsService().streams(game)
                    try Task.checkCancellation()
                    if let first = streams.first {
                        playback.play(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: first.url, sources: streams)
                    }
                    else { watchError = "No source is available for this game yet. Try again closer to game time." }
                } catch is CancellationError { }
                catch { if !Task.isCancelled { watchError = error.localizedDescription } }
            }
            .alert("Source unavailable", isPresented: Binding(get: { watchError != nil }, set: { if !$0 { watchError = nil } })) {
                Button("OK", role: .cancel) { watchError = nil }
            } message: { Text(watchError ?? "Try again shortly.") }
    }

    private func matchTeam(_ team: SportsTeam) -> some View {
        HStack(spacing: 12) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(team.name.isEmpty ? team.abbreviation : team.name)
                    .font(.subheadline.weight(game.winner?.id == team.id ? .bold : .medium)).lineLimit(2)
                    .foregroundStyle(game.winner != nil && game.winner?.id != team.id ? AppTheme.foreground.opacity(0.8) : AppTheme.foreground)
                HStack(spacing: 7) {
                    if !team.record.isEmpty { Text(team.record).font(.caption2).foregroundStyle(AppTheme.muted) }
                    if game.winner?.id == team.id {
                        Text("WINNER").font(.system(size: 9, weight: .bold)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(AppTheme.controlFill, in: Capsule())
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if game.state != "pre" { score(team) }
            Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7))
                .opacity(game.winner?.id == team.id ? 1 : 0).accessibilityHidden(true)
        }.frame(minHeight: 48)
    }

    private func score(_ team: SportsTeam) -> some View {
        let losing = game.winner != nil && game.winner?.id != team.id
        return Text(team.score.isEmpty ? "—" : team.score)
            .font(.system(size: 23, weight: losing ? .medium : .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(losing ? AppTheme.muted : AppTheme.foreground).lineLimit(1).minimumScaleFactor(0.7)
    }
}

struct SportsTeamScore: View {
    let team: SportsTeam
    var showScore = true
    var winner = false
    var subdued = false
    var body: some View {
        HStack(spacing: 12) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(team.name).font(.subheadline.weight(winner ? .bold : .medium)).lineLimit(2)
                    .foregroundStyle(subdued ? AppTheme.foreground.opacity(0.8) : AppTheme.foreground)
                if winner { Label("Winner", systemImage: "checkmark.circle.fill").font(.caption2.weight(.semibold)) }
                else if !team.record.isEmpty { Text(team.record).font(.caption2).foregroundStyle(AppTheme.muted) }
            }
            Spacer(minLength: 6)
            if showScore { Text(team.score.isEmpty ? "—" : team.score).font(.title2.bold().monospacedDigit()).foregroundStyle(subdued ? AppTheme.muted : AppTheme.foreground).minimumScaleFactor(0.7) }
        }
    }
}

struct SportsPanel<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 16, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 1) }
    }
}
