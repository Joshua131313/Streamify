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
    case list = "List", slider = "Slider"
    var id: String { rawValue }
}

struct SportsView: View {
    var searchRequest = 0
    var searchNamespace: Namespace.ID? = nil
    var searchSourceID = "sports-search"
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: SportsPlaybackSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var queue = SportsWatchQueue()
    @StateObject private var daySwipeScope = SportsDaySwipeScope()
    @State private var selectedLeagues = Set(SportsLeague.allCases)
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var currentToday = Calendar.current.startOfDay(for: Date())
    @State private var filter: SportsFilter = .all
    @State private var layout: SportsLayout = .list
    @State private var home = false
    @State private var channels = false
    @State private var showSportsSearch = false
    @State private var handledSearchRequest = 0
    @State private var games: [SportsGame] = []
    @State private var loading = true
    @State private var loadedScheduleKey: String?
    @State private var loadedBackend: String?
    @State private var scheduleRequest = UUID()
    @State private var manualReload = false
    @State private var error: String?
    @State private var partial = false
    @State private var selectedGame: SportsGame?
    @State private var showMultiWatch = false
    @State private var showCalendar = false
    @State private var showLeaguePicker = false
    @State private var showFilters = false
    @State private var calendarMonth = Calendar.current.startOfDay(for: Date())
    @State private var revision = 0
    @State private var calendarMarkers: [Date: Set<SportsLeague>] = [:]
    @State private var calendarUnavailable = Set<SportsLeague>()
    @State private var calendarLoading = false
    @State private var calendarLoadedAt: Date?
    @State private var daySwipeDirection = 1
    @State private var daySwipeSerial = 0
    @State private var dayTransitioning = false

    private var today: Date { currentToday }
    private var lastDay: Date { Calendar.current.date(byAdding: .day, value: 13, to: today) ?? today }

    private var leagues: [SportsLeague] { SportsLeague.allCases.filter { selectedLeagues.contains($0) } }
    private var allLeagues: Bool { selectedLeagues.count == SportsLeague.allCases.count }
    private var leagueTitle: String { allLeagues ? "All leagues" : leagues.map(\.title).joined(separator: ", ") }
    private var liveAvailable: Bool { Calendar.current.isDate(day, inSameDayAs: today) }
    private var requestKey: String { "\(leagues.map(\.rawValue).joined(separator: ","))-\(day.timeIntervalSince1970)-\(revision)-\(scenePhase == .active)-\(settings.apiBase)-\(channels)" }
    private var scheduleKey: String { "\(settings.apiBase)|\(Calendar.current.timeZone.identifier)|\(day.timeIntervalSince1970)|\(leagues.map(\.rawValue).joined(separator: ","))" }
    private var filteredGames: [SportsGame] {
        games.filter { game in
            guard selectedLeagues.contains(game.league) else { return false }
            let status: Bool
            switch filter {
            case .all: status = true
            case .live: status = game.isLive
            case .final: status = game.isFinal
            case .upcoming: status = game.state == "pre" && game.date.map { !liveAvailable || (0...7200).contains($0.timeIntervalSinceNow) } == true
            case .following: status = library.followedTeams.contains(game.home.key(in: game.league)) || library.followedTeams.contains(game.away.key(in: game.league))
            }
            return status
        }
    }

    private var emptyScheduleMessage: String {
        if filter == .upcoming {
            return liveAvailable ? "Upcoming includes games starting within two hours. Try All games or another day." : "No upcoming games are scheduled for this day. Try another date or league."
        }
        return "Try another date, league, or filter. Follow teams from their profile to personalize this view."
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                compactToolbar.padding(.bottom, 8)
                if channels {
                    SportsChannelsView()
                } else {
                    if home {
                        scheduleHeading
                        scheduleStatus
                        sportsHome
                    } else {
                        scheduleDayContent
                    }
                    Text("Scores refresh every 30 seconds. Times are local. Scores and schedules by ESPN.").font(.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
                }
            }.padding(.top, 14).padding(.bottom, 110)
        }
        .foregroundStyle(AppTheme.foreground)
        .accessibilityIdentifier("sports-screen")
        .onAppear { refreshCurrentDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshCurrentDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshCurrentDay() }
        .onChange(of: scenePhase) { _, value in
            if value == .active { refreshCurrentDay() }
            else { dayTransitioning = false }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: playback.isMinimized) { _, minimized in
            guard minimized else { return }
            selectedGame = nil
            showMultiWatch = false
        }
        .task(id: searchRequest) {
            guard searchRequest > 0, searchRequest != handledSearchRequest else { return }
            handledSearchRequest = searchRequest
            showSportsSearch = true
        }
        .refreshable { await loadSchedule(forceReload: true) }
        .task(id: daySwipeSerial) {
            guard dayTransitioning else { return }
            do { try await Task.sleep(for: .milliseconds(240)); try Task.checkCancellation() }
            catch { return }
            dayTransitioning = false
        }
        .task(id: requestKey) {
            guard scenePhase == .active, !channels else { return }
            repeat {
                let reload = manualReload; manualReload = false
                await loadSchedule(forceReload: reload)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
        .task(id: "\(showCalendar)-\(scenePhase == .active)-\(today.timeIntervalSince1970)") {
            guard showCalendar, scenePhase == .active else { return }
            if let calendarLoadedAt, Date().timeIntervalSince(calendarLoadedAt) < 600, calendarUnavailable.isEmpty { return }
            await loadCalendarMarkers()
        }
        .sheet(item: $selectedGame) { game in
            NavigationStack { SportsGameView(game: game).environmentObject(queue) }
        }
        .streamifySearchPresentation(isPresented: $showSportsSearch, sourceID: searchSourceID, in: searchNamespace) {
            SportsSearchDialog(day: day, initialGames: games).environmentObject(queue)
        }
        .sheet(isPresented: $showMultiWatch) { NavigationStack { SportsMultiWatchView().environmentObject(queue) } }
        .sheet(isPresented: $showCalendar) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        calendarGrid
                        calendarLegend
                        Text("Choose a day in the next two weeks. Dots show leagues with scheduled games.")
                            .font(.footnote).foregroundStyle(AppTheme.muted).padding(.horizontal, 20)
                    }.padding(.vertical, 16)
                }.background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
                    .navigationTitle("Game calendar").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Today") { selectDay(today); calendarMonth = monthStart(today) } }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showCalendar = false }.accessibilityIdentifier("sports-calendar-done") }
                    }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFilters) { filterSheet }
        .sheet(isPresented: $showLeaguePicker) {
            SportsLeaguePicker(selected: selectedLeagues) { values in
                selectedLeagues = values
                channels = false
                home = false
                showLeaguePicker = false
            }
        }
    }

    private var scheduleDayContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 16) {
                scheduleHeading
                scheduleStatus
                gameList.opacity(loading ? 0 : 1).allowsHitTesting(!loading)
                if !loading && error == nil && filteredGames.isEmpty {
                    StateMessage(symbol: "sportscourt", title: filter == .following ? "No followed teams playing" : "No games to show", message: emptyScheduleMessage)
                }
            }
            .id(day)
            .transition(.asymmetric(
                insertion: .offset(x: CGFloat(daySwipeDirection) * 28).combined(with: .opacity),
                removal: .offset(x: CGFloat(daySwipeDirection) * -28).combined(with: .opacity)))
        }
        .clipped()
        .allowsHitTesting(!dayTransitioning)
        .accessibilityElement(children: .contain).accessibilityIdentifier("sports-day-content")
        .accessibilityValue(day.formatted(date: .complete, time: .omitted))
        .background {
            SportsDaySwipeObserver(scope: daySwipeScope,
                enabled: scenePhase == .active && !home && !channels && layout == .list && !loading && !dayTransitioning &&
                    !showCalendar && !showFilters && !showLeaguePicker && !showSportsSearch && !showMultiWatch && selectedGame == nil && !playback.isExpanded,
                canGoBack: day > today, canGoForward: day < lastDay, changeDay: swipeDay)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var scheduleHeading: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter == .final ? "Final results" : Calendar.current.isDateInToday(day) ? "Today’s games" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                if filter == .upcoming || filter == .following {
                    Text(filter.rawValue).font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            Spacer(minLength: 8)
            Button {
                guard daySwipeScope.permitsProtectedAction else { return }
                AppHaptics.tap()
                filter = filter == .live ? .all : .live
                home = false
                if filter == .live { selectDay(today) }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(liveAvailable ? AppTheme.accent : AppTheme.muted).frame(width: 5, height: 5)
                    Text("Live").font(.caption.weight(.semibold))
                }.padding(.horizontal, 12).frame(height: 30)
                    .foregroundStyle(filter == .live ? AppTheme.canvas : AppTheme.foreground)
                    .background(filter == .live ? AppTheme.foreground : AppTheme.controlFill, in: Capsule())
                    .overlay { Capsule().strokeBorder(filter == .live ? .clear : AppTheme.border, lineWidth: 0.7) }
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Live games")
                .disabled(!liveAvailable).opacity(liveAvailable ? 1 : 0.4)
                .accessibilityValue(liveAvailable ? (filter == .live ? "On" : "Off") : "Unavailable for future dates")
                .accessibilityAddTraits(filter == .live ? .isSelected : [])
                .accessibilityIdentifier("sports-quick-live")
                .sportsDaySwipeExcluded(daySwipeScope)
        }.padding(.horizontal, 20)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-schedule-heading")
    }

    @ViewBuilder private var scheduleStatus: some View {
        if loading {
            ProgressView("Loading games…").frame(maxWidth: .infinity).frame(height: 44)
                .accessibilityIdentifier("sports-schedule-loading")
        }
        if let error { StateMessage(symbol: "wifi.exclamationmark", title: games.isEmpty ? "Schedule unavailable" : "Couldn’t refresh scores", message: error, actionTitle: "Retry", action: { if daySwipeScope.permitsProtectedAction { manualReload = true; revision += 1 } }).sportsDaySwipeExcluded(daySwipeScope) }
        if partial { Label("Some feeds are unavailable. Showing the games that loaded.", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(AppTheme.muted).padding(.horizontal, 20) }
    }

    private var compactToolbar: some View {
        HStack(spacing: 6) {
            Button { showLeaguePicker = true } label: {
                HStack(spacing: 6) {
                    if allLeagues {
                        Image(systemName: "square.grid.2x2").font(.system(size: 16, weight: .medium))
                            .frame(width: 22, height: 24).accessibilityHidden(true)
                    } else {
                        ZStack(alignment: .leading) {
                            ForEach(Array(leagues.prefix(2).enumerated()), id: \.offset) { index, item in
                                Image("league-\(item.rawValue)").resizable().scaledToFit()
                                    .frame(width: 18, height: 18).padding(2)
                                    .background(AppTheme.panel, in: Circle()).offset(x: CGFloat(index) * 12)
                            }
                        }.frame(width: 22 + CGFloat(max(0, min(2, leagues.count) - 1)) * 12, height: 24).accessibilityHidden(true)
                    }
                    Text(leagueTitle).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
                    .streamifyControlSurface()
            }.accessibilityLabel("Choose leagues").accessibilityValue(leagueTitle)
                .accessibilityIdentifier("sports-league-picker")
            Button {
                calendarMonth = monthStart(day)
                showCalendar = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.caption)
                    Text(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption.weight(.semibold)).lineLimit(1)
                }.padding(.horizontal, 10).frame(minHeight: 44).streamifyControlSurface()
            }.accessibilityLabel("Choose game date").accessibilityValue(day.formatted(date: .complete, time: .omitted))
                .accessibilityIdentifier("sports-date-picker").disabled(channels)
            Button { showFilters = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).streamifyControlSurface()
                    .overlay(alignment: .topTrailing) {
                        if filter != .all || layout != .list {
                            Circle().fill(AppTheme.foreground).frame(width: 5, height: 5).padding(7)
                        }
                    }
            }.accessibilityLabel("Sports filters").accessibilityValue("\(filter.rawValue), \(layout.rawValue)")
                .accessibilityIdentifier("sports-filter-picker").disabled(channels)
            Menu {
                Button { chooseLeague(nil) } label: { Label("Today’s schedule", systemImage: "sportscourt") }
                    .accessibilityIdentifier("sports-all-leagues-schedule")
                Button { chooseLeague(nil, showHome: true) } label: { Label("Browse by league", systemImage: "square.grid.2x2") }
                    .accessibilityIdentifier("sports-home-overview")
                Button { channels = true; home = false } label: { Label("Sports channels", systemImage: "tv") }
                    .accessibilityIdentifier("sports-channels")
                Button { showMultiWatch = true } label: { Label("Multi-watch · \(queue.streams.count)/4", systemImage: "rectangle.split.2x2") }
                    .accessibilityIdentifier("sports-multi-watch")
                Divider()
                Button { manualReload = true; revision += 1 } label: { Label("Refresh scores", systemImage: "arrow.clockwise") }
                    .disabled(loading || channels).accessibilityIdentifier("sports-refresh")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("More sports options").accessibilityIdentifier("sports-menu")
        }.buttonStyle(HapticPlainButtonStyle()).padding(.horizontal, 16)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-toolbar")
    }

    private var filterSheet: some View {
        NavigationStack {
            List {
                Section("Games") {
                    ForEach(SportsFilter.allCases) { item in
                        Button {
                            filter = item
                            home = false
                            if item == .live || item == .upcoming || item == .final { selectDay(today) }
                        } label: {
                            HStack {
                                Text(item.rawValue)
                                Spacer()
                                if filter == item { Image(systemName: "checkmark").font(.subheadline.weight(.semibold)) }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(HapticPlainButtonStyle()).accessibilityAddTraits(filter == item ? .isSelected : [])
                            .disabled(item == .live && !liveAvailable)
                            .foregroundStyle(item == .live && !liveAvailable ? AppTheme.muted.opacity(0.4) : AppTheme.foreground)
                            .accessibilityIdentifier("sports-filter-\(item.rawValue)")
                    }
                }.listRowBackground(AppTheme.panel)
                Section("Display") {
                    ForEach(SportsLayout.allCases) { item in
                        Button { layout = item; home = false } label: {
                            HStack {
                                Label(item.rawValue, systemImage: item == .list ? "list.bullet" : "rectangle.split.3x1")
                                Spacer()
                                if layout == item { Image(systemName: "checkmark").font(.subheadline.weight(.semibold)) }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(HapticPlainButtonStyle()).accessibilityAddTraits(layout == item ? .isSelected : [])
                            .accessibilityIdentifier("sports-layout-\(item.rawValue)")
                    }
                }.listRowBackground(AppTheme.panel)
            }.scrollContentBackground(.hidden).background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
                .navigationTitle("Sports filters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFilters = false }.accessibilityIdentifier("sports-filter-done") } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-filter-sheet")
    }

    private func monthStart(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? today
    }

    private var calendarDates: [Date] {
        let calendar = Calendar.current
        let first = monthStart(calendarMonth)
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: first) }
    }

    private var calendarGrid: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: monthStart(calendarMonth)) ?? calendarMonth
                } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(monthStart(calendarMonth) <= monthStart(today))
                    .accessibilityLabel("Previous month").accessibilityIdentifier("sports-calendar-previous-month")
                Text(calendarMonth.formatted(.dateTime.month(.wide).year())).font(.headline).frame(maxWidth: .infinity)
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart(calendarMonth)) ?? calendarMonth
                } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(monthStart(calendarMonth) >= monthStart(lastDay))
                    .accessibilityLabel("Next month").accessibilityIdentifier("sports-calendar-next-month")
            }.buttonStyle(HapticPlainButtonStyle())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Calendar.current.veryShortStandaloneWeekdaySymbols[(Calendar.current.firstWeekday - 1 + index) % 7])
                        .font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity)
                }
                ForEach(calendarDates, id: \.self) { value in calendarDateCell(value) }
            }
        }.padding(.horizontal, 16)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-calendar-grid")
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private func calendarDateCell(_ value: Date) -> some View {
        let selected = Calendar.current.isDate(value, inSameDayAs: day)
        let enabled = value >= today && value <= lastDay
        let offset = Calendar.current.dateComponents([.day], from: today, to: value).day ?? -1
        return Button { selectDay(value) } label: {
            VStack(spacing: 5) {
                Text(value.formatted(.dateTime.day())).font(.subheadline.weight(selected ? .bold : .medium).monospacedDigit())
                HStack(spacing: 2) {
                    ForEach(leagues.filter { calendarMarkers[value]?.contains($0) == true }) { item in
                        Circle().fill(leagueDotColor(item)).frame(width: 4, height: 4)
                    }
                }.frame(height: 4)
            }.frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(selected ? AppTheme.canvas : enabled ? AppTheme.foreground : AppTheme.muted.opacity(0.4))
                .background(selected ? AppTheme.foreground : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(offset == 0 && !selected ? AppTheme.muted.opacity(0.4) : .clear, lineWidth: 1) }
                .contentShape(Rectangle())
        }.buttonStyle(HapticPlainButtonStyle()).disabled(!enabled)
            .accessibilityLabel(dateDescription(value)).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(enabled ? "sports-date-offset-\(offset)" : "sports-calendar-outside-\(offset)")
    }

    private var calendarLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(SportsLeague.allCases) { item in
                    let selected = !allLeagues && selectedLeagues.contains(item)
                    Button { toggleCalendarLeague(item) } label: {
                        HStack(spacing: 6) {
                            Image("league-\(item.rawValue)").resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true)
                            Circle().fill(leagueDotColor(item)).frame(width: 5, height: 5)
                            Text(item.title).font(.caption2.weight(selected ? .semibold : .regular))
                            if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)) }
                        }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(selected ? AppTheme.foreground : AppTheme.muted)
                            .background(AppTheme.foreground.opacity(selected ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                    }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel(item.title)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("sports-calendar-league-\(item.rawValue)")
                }
            }
            Text("Choose leagues to filter games. No selection shows all leagues.").font(.caption2).foregroundStyle(AppTheme.muted)
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
        case .ncaaf: return Color(red: 0.33, green: 0.65, blue: 0.94)
        case .nba: return Color(red: 0.94, green: 0.53, blue: 0.24)
        case .wnba: return Color(red: 0.86, green: 0.40, blue: 0.71)
        case .nhl: return Color(red: 0.27, green: 0.74, blue: 0.70)
        case .mlb: return Color(red: 0.58, green: 0.45, blue: 0.91)
        }
    }

    private func selectDay(_ value: Date, animated: Bool = false) {
        let value = min(lastDay, max(today, Calendar.current.startOfDay(for: value)))
        guard value != day else { return }
        let update = {
            daySwipeScope.invalidateRequests()
            revision += 1
            games = []
            loading = true
            error = nil
            partial = false
            day = value
            if !Calendar.current.isDateInToday(value), filter == .live { filter = .all }
        }
        if animated && !reduceMotion {
            dayTransitioning = true
            daySwipeSerial &+= 1
            withAnimation(.easeInOut(duration: 0.22), update)
        } else {
            dayTransitioning = false
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
    }

    private func refreshCurrentDay(now: Date = Date()) {
        let calendar = Calendar.current
        let freshToday = calendar.startOfDay(for: now)
        guard freshToday != currentToday else { return }
        let selection = SportsScheduleDayPolicy.selectedDay(day, now: now, calendar: calendar)
        daySwipeScope.invalidateRequests()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentToday = freshToday
            revision += 1
            dayTransitioning = false
            calendarLoadedAt = nil
            calendarMarkers = [:]
            if day != selection {
                day = selection
                games = []
                loading = true
                error = nil
                partial = false
            }
            if !calendar.isDate(selection, inSameDayAs: freshToday), filter == .live { filter = .all }
            calendarMonth = monthStart(selection)
        }
    }

    private func swipeDay(_ direction: Int) {
        guard !loading, !dayTransitioning, layout == .list, !home, !channels,
              let next = Calendar.current.date(byAdding: .day, value: direction, to: day), next >= today, next <= lastDay else { return }
        daySwipeDirection = direction
        selectDay(next, animated: true)
    }

    private func toggleCalendarLeague(_ league: SportsLeague) {
        var draft = allLeagues ? Set<SportsLeague>() : selectedLeagues
        if draft.contains(league) { draft.remove(league) } else { draft.insert(league) }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedLeagues = draft.isEmpty ? Set(SportsLeague.allCases) : draft
            home = false
        }
    }

    private func chooseLeague(_ value: SportsLeague?, showHome: Bool = false) {
        selectedLeagues = value.map { Set([$0]) } ?? Set(SportsLeague.allCases)
        home = showHome; channels = false; filter = .all; selectDay(today)
    }

    private var sportsHome: some View {
        ForEach(SportsHomeOrder.leagues(withGames: Set(games.map(\.league)))) { item in
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image("league-\(item.rawValue)").resizable().scaledToFit().frame(width: 24, height: 24)
                    Text(item.title).font(.headline)
                    Spacer()
                    Button("View all") { chooseLeague(item) }.font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).streamifyControlSurface()
                }.buttonStyle(HapticPlainButtonStyle())
                ForEach(games.filter { $0.league == item }.prefix(3)) { game in SportsGameCard(game: game) { selectedGame = game } }
                if !loading && !games.contains(where: { $0.league == item }) {
                    Text(partial || error != nil ? "Schedule temporarily unavailable." : "No games scheduled today.").font(.subheadline).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.horizontal, 20)
        }
    }

    @ViewBuilder private var gameList: some View {
        if layout == .slider && filter != .live && !filteredGames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) { ForEach(filteredGames) { game in SportsGameCard(game: game, daySwipeScope: daySwipeScope) { selectedGame = game }.frame(width: 300) } }.padding(.horizontal, 20)
            }
        } else {
            ForEach(filteredGames) { game in SportsGameCard(game: game, daySwipeScope: daySwipeScope) { selectedGame = game }.padding(.horizontal, 20) }
        }
    }

    private func loadSchedule(forceReload: Bool = false) async {
        refreshCurrentDay()
        guard !channels else { return }
        let requestedKey = requestKey
        let identity = scheduleKey
        let request = UUID(); scheduleRequest = request
        if loadedBackend != settings.apiBase {
            games = []; loadedScheduleKey = nil; loadedBackend = settings.apiBase
        }
        // Switching tabs or returning from search keeps the current scorecards
        // visible and tappable while live data refreshes in the background.
        // A new league selection may have no matching retained cards yet.
        // Keep its loading state until that selection has a real result.
        loading = filteredGames.isEmpty && loadedScheduleKey != identity
        defer { if scheduleRequest == request { loading = false } }
        do {
            let result = try await SportsService(backend: settings.apiBase, forceReload: forceReload).schedule(leagues: leagues, day: day)
            try Task.checkCancellation()
            guard requestedKey == requestKey, scheduleRequest == request else { return }
            games = result.games
            loadedScheduleKey = identity
            partial = result.partial
            error = nil
        } catch is CancellationError { }
        catch { if !Task.isCancelled && requestedKey == requestKey && scheduleRequest == request { self.error = error.localizedDescription } }
    }

    private func loadCalendarMarkers() async {
        refreshCurrentDay()
        calendarLoading = true
        defer { calendarLoading = false }
        let start = today, end = lastDay, referenceTime = Date()
        let calendar = Calendar.current
        let jobs: [(SportsLeague, Date, String)] = {
            var result: [(SportsLeague, Date, String)] = []
            for item in SportsLeague.allCases {
                for offset in -1...14 {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                    for parameters in item.scoreboardParameters { result.append((item, date, parameters)) }
                }
            }
            return result
        }()
        do {
            let batches = try await withThrowingTaskGroup(of: SportsMarkerBatch.self, returning: [SportsMarkerBatch].self) { group in
                // Match Android's limit: three scoreboard requests at a time.
                for worker in 0..<3 {
                    group.addTask {
                        var batch = SportsMarkerBatch()
                        for index in stride(from: worker, to: jobs.count, by: 3) {
                            try Task.checkCancellation()
                            let (item, date, parameters) = jobs[index]
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd"
                            guard let url = URL(string: "\(item.endpoint)/scoreboard?dates=\(formatter.string(from: date))\(parameters)") else { batch.unavailable.insert(item); continue }
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
            guard start == today else { return }
            var markers: [Date: Set<SportsLeague>] = [:]
            for game in SportsScheduleDayPolicy.canonicalGames(batches.flatMap(\.games)) {
                guard let date = SportsScheduleDayPolicy.markerDay(for: game, now: referenceTime, calendar: calendar), date >= start, date <= end else { continue }
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
    var daySwipeScope: SportsDaySwipeScope? = nil
    var action: () -> Void
    @EnvironmentObject private var playback: SportsPlaybackSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playbackOrigin = SportsPlaybackOrigin()
    @State private var watchRevision = 0
    @State private var handledWatchRevision = 0
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
            }.buttonStyle(HapticCardButtonStyle()).accessibilityElement(children: .combine).accessibilityIdentifier("sports-game-\(game.id)")
            Rectangle().fill(AppTheme.border).frame(height: 0.5)
            HStack(spacing: 10) {
                Button {
                    guard daySwipeScope?.permitsProtectedAction != false else { return }
                    AppHaptics.tap()
                    action()
                } label: {
                    HStack(spacing: 7) {
                        Text("Game Center")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }.frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                        .overlay { RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius).strokeBorder(AppTheme.border, lineWidth: 0.7) }
                }.buttonStyle(.plain)
                    .sportsDaySwipeExcluded(daySwipeScope)
                if game.canWatch {
                    Button {
                        guard daySwipeScope?.permitsProtectedAction != false else { return }
                        AppHaptics.tap()
                        watchRevision += 1
                    } label: {
                        HStack(spacing: 7) {
                            if watchLoading { ProgressView().controlSize(.small).tint(AppTheme.canvas) }
                            else { Image(systemName: "play.fill").font(.system(size: 11)) }
                            Text("Watch")
                        }.frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(AppTheme.canvas).background(AppTheme.foreground, in: RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                    }.buttonStyle(.plain).disabled(watchLoading)
                        .accessibilityLabel("Watch \(game.away.abbreviation) vs \(game.home.abbreviation)")
                        .sportsDaySwipeExcluded(daySwipeScope)
                }
            }.font(.caption.weight(.semibold))
        }.padding(16).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 0.7) }
            .streamifyCardDepth(cornerRadius: 20)
            .sportsPlaybackOrigin(playbackOrigin)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
            .contextMenu {
                Button("Game Center", systemImage: "sportscourt", action: action)
                if game.canWatch {
                    Button("Watch game", systemImage: "play.fill") { watchRevision += 1 }.disabled(watchLoading)
                }
            }
            .task(id: "\(watchRevision)-\(scenePhase == .active)") {
                let request = watchRevision
                guard scenePhase == .active else {
                    // Leaving this tab consumes even a request whose task had
                    // not started yet; returning never replays a Watch tap.
                    handledWatchRevision = max(handledWatchRevision, request)
                    return
                }
                guard request > handledWatchRevision else { return }
                // Consume before suspension. SwiftUI can restart a row task
                // after returning to a tab or restoring a recycled lazy row.
                handledWatchRevision = request
                let scheduleGeneration = daySwipeScope?.generation
                let requestOrigin = playbackOrigin
                watchLoading = true
                watchError = nil
                defer { if watchRevision == request { watchLoading = false } }
                do {
                    let streams = try await SportsService().streams(game)
                    try Task.checkCancellation()
                    guard watchRevision == request, daySwipeScope?.generation == scheduleGeneration else { return }
                    if let first = streams.first {
                        playback.play(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: first.url, sources: streams, origin: requestOrigin)
                    }
                    else { watchError = "No source is available for this game yet. Try again closer to game time." }
                } catch is CancellationError { }
                catch { if !Task.isCancelled && daySwipeScope?.generation == scheduleGeneration { watchError = error.localizedDescription } }
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
                if !team.record.isEmpty { Text(team.record).font(.caption2).foregroundStyle(AppTheme.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if game.state != "pre" { score(team) }
        }.frame(minHeight: 48)
    }

    private func score(_ team: SportsTeam) -> some View {
        let losing = game.winner != nil && game.winner?.id != team.id
        return HStack(spacing: 6) {
            Text(team.score.isEmpty ? "—" : team.score)
                .font(.system(size: 23, weight: losing ? .medium : .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(losing ? AppTheme.muted : AppTheme.foreground).lineLimit(1).minimumScaleFactor(0.7)
            SportsWinnerChevron(visible: game.winner?.id == team.id)
        }
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
                if !team.record.isEmpty { Text(team.record).font(.caption2).foregroundStyle(AppTheme.muted) }
            }
            Spacer(minLength: 6)
            if showScore {
                HStack(spacing: 6) {
                    Text(team.score.isEmpty ? "—" : team.score).font(.title2.bold().monospacedDigit())
                        .foregroundStyle(subdued ? AppTheme.muted : AppTheme.foreground).minimumScaleFactor(0.7)
                    SportsWinnerChevron(visible: winner)
                }
            }
        }
    }
}

/// Reserve the same small score gutter on both rows so the scores stay aligned.
private struct SportsWinnerChevron: View {
    let visible: Bool
    var body: some View {
        Image(systemName: "chevron.left").font(.system(size: 8, weight: .heavy))
            .foregroundStyle(AppTheme.foreground).frame(width: 8)
            .opacity(visible ? 1 : 0).accessibilityHidden(true)
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
