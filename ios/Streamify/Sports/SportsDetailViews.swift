import SwiftUI

struct SportsGameView: View {
    let game: SportsGame
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SportsWatchQueue
    @EnvironmentObject private var playback: SportsPlaybackSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var center: SportsGameCenter?
    @State private var error: String?
    @State private var tab = "Overview"
    @State private var revision = 0
    @State private var streams: [SportsStream] = []
    @State private var streamsLoading = true
    @State private var streamsError: String?
    @State private var selectedTeam: SportsTeamResult?
    @State private var showMultiWatch = false
    private var current: SportsGame { center?.game ?? game }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(current.isLive ? "● LIVE · \(current.status)" : current.status).font(.caption.bold()).foregroundStyle(current.isLive ? AppTheme.accent : AppTheme.muted)
                    Text("\(current.away.name)\nat \(current.home.name)").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(current.date?.formatted(date: .abbreviated, time: .shortened) ?? "Time to be announced").font(.subheadline).foregroundStyle(AppTheme.muted)
                    if !current.venue.isEmpty { Text(current.venue).font(.caption).foregroundStyle(AppTheme.muted) }
                }
                SportsPanel {
                    ForEach([current.away, current.home]) { team in
                        HStack {
                            Button { selectedTeam = SportsTeamResult(league: game.league, team: team) } label: {
                                SportsTeamScore(team: team, showScore: current.state != "pre", winner: current.winner?.id == team.id,
                                    subdued: current.winner != nil && current.winner?.id != team.id)
                            }.buttonStyle(.plain).accessibilityIdentifier("sports-team-\(team.id)")
                            followButton(team)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(["Overview", "Scoring", "Team stats", "Latest play", "Chat"], id: \.self) { value in Pill(title: value, selected: tab == value) { tab = value }.accessibilityIdentifier(value == "Scoring" ? "sports-scoring-tab" : "sports-game-tab-\(value)") } }
                }
                if let error {
                    StateMessage(symbol: "exclamationmark.circle", title: "Detailed feed unavailable", message: error, actionTitle: "Retry", action: { revision += 1 })
                }
                if tab == "Overview" { overview }
                if tab == "Scoring" {
                    if let scoring = center?.scoring, !scoring.isEmpty { SportsScoringTable(game: current, periods: scoring) }
                    else { StateMessage(symbol: "chart.bar.xaxis", title: "Awaiting scoring", message: "A breakdown is not available in the current feed.") }
                }
                if tab == "Team stats" { statTable(center?.statistics ?? [], title: "Team comparison") }
                if tab == "Latest play" {
                    SportsPanel { Label("Latest play", systemImage: "waveform.path").font(.headline); Text(center.flatMap { $0.latest.isEmpty ? nil : $0.latest } ?? "Play-by-play is not available in the current feed.").foregroundStyle(AppTheme.muted) }
                }
                if tab == "Chat" {
                    StateMessage(symbol: "bubble.left.and.bubble.right", title: "Matchup chat", message: "The shared Streamify chat requires a connected cloud account. iOS cloud sign-in has not been configured for this build.")
                }
            }.padding(20).padding(.bottom, 24)
        }
        .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
        .navigationTitle("Game center").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if let url = sportsHTTPSURL(game.link) { Link(destination: url) { Text("ESPN ↗").font(.caption.bold()) }.accessibilityLabel("Open game on ESPN") }
            }
        }
        .task(id: "\(game.id)-\(revision)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            repeat {
                do { center = try await SportsService().center(game); error = nil }
                catch is CancellationError { return }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            } while !Task.isCancelled
        }
        .task(id: "\(game.id)-\(revision)") { await loadStreams() }
        .sheet(item: $selectedTeam) { item in NavigationStack { SportsTeamView(result: item).environmentObject(queue) } }
        .sheet(isPresented: $showMultiWatch) { NavigationStack { SportsMultiWatchView().environmentObject(queue) } }
        .onChange(of: playback.isMinimized) { _, minimized in
            guard minimized else { return }
            selectedTeam = nil
            showMultiWatch = false
            dismiss()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            SportsPanel {
                Text("Game information").font(.headline)
                Text("\(current.away.name) at \(current.home.name). \(current.status).").foregroundStyle(AppTheme.muted)
                Label(current.broadcasts.isEmpty ? "Broadcast not announced" : current.broadcasts, systemImage: "tv").font(.subheadline).foregroundStyle(AppTheme.muted)
                if current.canWatch, let first = streams.first {
                    Button { play(first) } label: { Label("Watch game", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(14).foregroundStyle(Color.black).background(Color.white, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                }
                Button {
                    guard let first = streams.first else { return }
                    queue.add(SportsStream(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: first.url, alternatives: streams))
                    showMultiWatch = true
                } label: { Label("Add to multi-watch", systemImage: "rectangle.split.2x2").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44).streamifyControlSurface() }
                    .buttonStyle(.plain).disabled(streams.isEmpty || queue.streams.count >= 4)
            }
            ForEach([current.away, current.home]) { team in
                Button { selectedTeam = SportsTeamResult(league: game.league, team: team) } label: {
                    SportsPanel { HStack { SportsTeamScore(team: team, showScore: false); Image(systemName: "chevron.right").foregroundStyle(AppTheme.muted) } }
                }.buttonStyle(.plain).accessibilityIdentifier("sports-team-profile-\(team.id)")
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Watch sources").font(.title3.bold()); Spacer(); if streamsLoading { ProgressView() } }
                if let streamsError {
                    StateMessage(symbol: "wifi.exclamationmark", title: "Sources unavailable", message: streamsError, actionTitle: "Retry", action: { revision += 1 })
                } else if !streamsLoading && streams.isEmpty {
                    Text(current.canWatch ? "No matching stream is available. Sources depend on the provider and may appear closer to game time." : "Sources are available for live games and games starting within an hour.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }
                ForEach(streams) { stream in
                    SportsPanel {
                        Text(stream.title).font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            Button { play(stream) } label: { Label("Watch", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 30) }
                                .buttonStyle(.borderedProminent).tint(AppTheme.foreground).foregroundStyle(AppTheme.canvas)
                            Button {
                                queue.add(SportsStream(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: stream.url, alternatives: streams))
                                showMultiWatch = true
                            } label: { Image(systemName: "rectangle.split.2x2").frame(minWidth: 32, minHeight: 28) }.buttonStyle(.bordered)
                                .disabled(queue.streams.count >= 4 || queue.streams.contains(where: { $0.url == stream.url })).accessibilityLabel("Add source to multi-watch")
                        }
                    }
                }
            }
        }
    }

    private func play(_ stream: SportsStream) {
        playback.play(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: stream.url, sources: streams)
    }

    private func followButton(_ team: SportsTeam) -> some View {
        let following = library.followedTeams.contains(team.key(in: game.league))
        return Button { library.toggleTeam(team.key(in: game.league)) } label: { Image(systemName: following ? "star.fill" : "star").foregroundStyle(following ? AppTheme.foreground : AppTheme.muted).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("\(following ? "Unfollow" : "Follow") \(team.name)")
    }

    @ViewBuilder private func statTable(_ rows: [SportsStatRow], title: String) -> some View {
        if rows.isEmpty {
            StateMessage(symbol: "chart.bar.xaxis", title: "Awaiting \(title.lowercased())", message: "A breakdown is not available in the current feed.")
        } else {
            SportsComparisonTable(away: current.away, home: current.home, rows: rows, title: title)
        }
    }

    private func loadStreams() async {
        streamsLoading = true
        defer { streamsLoading = false }
        do { streams = try await SportsService().streams(game); streamsError = nil }
        catch is CancellationError { }
        catch { if !Task.isCancelled { streamsError = error.localizedDescription } }
    }
}

struct SportsTeamView: View {
    let result: SportsTeamResult
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SportsWatchQueue
    @Environment(\.dismiss) private var dismiss
    @State private var profile: SportsTeamProfile?
    @State private var error: String?
    @State private var loading = true
    @State private var tab = "Schedule"
    @State private var revision = 0
    @State private var selectedGame: SportsGame?
    private var team: SportsTeam { profile?.team ?? result.team }
    private var following: Bool { library.followedTeams.contains(result.id) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SportsPanel {
                    RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 84, height: 84)
                    Text(team.name).font(.title.bold())
                    Text([result.league.title, team.record, profile?.venue ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(AppTheme.muted)
                    Button { library.toggleTeam(result.id) } label: {
                        Label(following ? "Following" : "Follow team", systemImage: following ? "star.fill" : "star")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44).streamifyControlSurface()
                    }.buttonStyle(.plain).foregroundStyle(AppTheme.foreground)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(["Schedule", "Results", "Roster"], id: \.self) { value in Pill(title: value, selected: tab == value) { tab = value }.accessibilityIdentifier(value == "Roster" ? "sports-team-roster-tab" : "sports-team-tab-\(value)") } }
                }
                if loading { ProgressView("Loading team…").frame(maxWidth: .infinity).padding(24) }
                if let error { StateMessage(symbol: "wifi.exclamationmark", title: "Team unavailable", message: error, actionTitle: "Retry", action: { revision += 1 }) }
                if let profile {
                    if tab == "Roster" { roster(profile) } else { schedule(profile) }
                }
            }.padding(20).padding(.bottom, 24)
        }.background(AppTheme.canvas).foregroundStyle(AppTheme.foreground).navigationTitle("\(result.league.title) · Team").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task(id: revision) {
                loading = true
                defer { loading = false }
                do { profile = try await SportsService().profile(result); error = nil }
                catch is CancellationError { }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .sheet(item: $selectedGame) { game in NavigationStack { SportsGameView(game: game).environmentObject(queue) } }
    }

    @ViewBuilder private func roster(_ profile: SportsTeamProfile) -> some View {
        if profile.roster.isEmpty {
            StateMessage(symbol: "person.3", title: "No roster available", message: profile.rosterUnavailable ? "The roster service could not be reached." : "Players have not been announced.")
        } else {
            SportsRosterTable(profile.roster, accent: result.league.accent)
        }
    }

    @ViewBuilder private func schedule(_ profile: SportsTeamProfile) -> some View {
        let games = tab == "Results" ? profile.games.filter(\.isFinal).reversed().map { $0 } : profile.games.filter { !$0.isFinal && ($0.isLive || ($0.date ?? .distantPast) >= Date()) }
        if games.isEmpty {
            StateMessage(symbol: "calendar", title: "No \(tab.lowercased()) available", message: profile.scheduleUnavailable ? "The schedule service could not be reached." : "Check back when games are announced.")
        } else {
            ForEach(games) { game in
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.date?.formatted(date: .abbreviated, time: .omitted) ?? "Date TBD").font(.caption).foregroundStyle(AppTheme.muted)
                    SportsGameCard(game: game) { selectedGame = game }
                }
            }
        }
    }
}

/// Team identities and totals stay pinned while periods or innings scroll.
struct SportsScoringTable: View {
    let game: SportsGame
    let periods: [SportsStatRow]
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var teamWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var periodWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var totalWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .title2) private var totalSize: CGFloat = 24

    private var subtitle: String {
        "\(game.league.title) · " + (game.league == .mlb ? "Inning by inning" : game.league == .nhl ? "Period by period" : "Quarter by quarter")
    }
    private var teamColumnWidth: CGFloat { min(116, teamWidth) }
    private var totalColumnWidth: CGFloat { min(84, totalWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Score breakdown").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted)
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    heading("TEAM").frame(width: teamColumnWidth, alignment: .leading)
                    teamLabel(game.away, side: "Away", stripe: false)
                    teamLabel(game.home, side: "Home", stripe: true)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                            VStack(spacing: 0) {
                                heading(periodTitle(index))
                                periodCell(period.away, team: game.away, stripe: false)
                                periodCell(period.home, team: game.home, stripe: true)
                            }.frame(width: periodWidth)
                        }
                    }
                }
                .accessibilityLabel(game.league == .mlb ? "Inning scores" : game.league == .nhl ? "Period scores" : "Quarter scores")
                VStack(spacing: 0) {
                    heading("TOTAL")
                    total(game.away, stripe: false)
                    total(game.home, stripe: true)
                }
                .frame(width: totalColumnWidth)
                .background(AppTheme.foreground.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(height: headerHeight + rowHeight * 2)
        }
        .padding(16).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-scoring-table")
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
            .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity).frame(height: headerHeight)
    }
    private func teamLabel(_ team: SportsTeam, side: String, stripe: Bool) -> some View {
        HStack(spacing: 8) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(team.abbreviation.isEmpty ? team.name : team.abbreviation).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(side).font(.caption2).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(.horizontal, 6).frame(width: teamColumnWidth, height: rowHeight, alignment: .leading)
        .background(stripe ? AppTheme.foreground.opacity(0.025) : Color.clear)
    }
    private func periodCell(_ value: String, team: SportsTeam, stripe: Bool) -> some View {
        Text(value.isEmpty ? "—" : value).font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(numberColor(team)).lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity).frame(height: rowHeight)
            .background(stripe ? AppTheme.foreground.opacity(0.025) : Color.clear)
    }
    private func total(_ team: SportsTeam, stripe: Bool) -> some View {
        Text(team.score.isEmpty ? "—" : team.score)
            .font(.system(size: totalSize, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(numberColor(team))
            .lineLimit(1).minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity).frame(height: rowHeight)
            .background(stripe ? AppTheme.foreground.opacity(0.025) : Color.clear)
            .accessibilityLabel("\(team.abbreviation.isEmpty ? team.name : team.abbreviation) total\(game.winner?.id == team.id ? ", winner" : "")")
            .accessibilityValue(team.score.isEmpty ? "Unavailable" : team.score)
            .accessibilityIdentifier("sports-scoring-total-\(team.id)")
    }
    private func numberColor(_ team: SportsTeam) -> Color {
        game.winner.map { $0.id != team.id } == true ? AppTheme.muted : AppTheme.foreground
    }
    private func periodTitle(_ index: Int) -> String {
        switch game.league {
        case .mlb: return String(index + 1)
        case .nhl: return index < 3 ? "P\(index + 1)" : index == 3 ? "OT" : "OT\(index - 2)"
        case .nba, .wnba, .nfl: return index < 4 ? "Q\(index + 1)" : index == 4 ? "OT" : "OT\(index - 3)"
        }
    }

}
