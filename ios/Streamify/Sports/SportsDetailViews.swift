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
    @State private var showChat = false
    private var current: SportsGame { center?.game ?? game }
    private var tabs: [String] { current.league == .tennis ? ["Overview", "Sets", "Chat"] : ["Overview", "Scoring", "Team stats"] + (current.state == "pre" ? [] : ["Players"]) + [current.isFinal ? "Play-by-play" : "Latest play", "Chat"] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scoreboard
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(tabs, id: \.self) { value in Pill(title: value, selected: tab == value) {
                        if value == "Chat" { showChat = true } else { tab = value }
                    }.accessibilityIdentifier(value == "Scoring" ? "sports-scoring-tab" : "sports-game-tab-\(value)") } }
                }.accessibilityIdentifier("sports-game-tabs")
                if let error {
                    StateMessage(symbol: "exclamationmark.circle", title: "Detailed feed unavailable", message: error, actionTitle: "Retry", action: { revision += 1 })
                }
                if tab == "Overview" { overview }
                if tab == "Scoring" || tab == "Sets" {
                    if let scoring = center?.scoring, !scoring.isEmpty { SportsScoringTable(game: current, periods: scoring) }
                    else { StateMessage(symbol: "chart.bar.xaxis", title: "Awaiting scoring", message: "A breakdown is not available in the current feed.") }
                }
                if tab == "Team stats" { statTable(center?.statistics ?? [], title: "Team comparison") }
                if tab == "Latest play" {
                    SportsPanel { Label("Latest play", systemImage: "waveform.path").font(.headline); Text(center.flatMap { $0.latest.isEmpty ? nil : $0.latest } ?? "Play-by-play is not available in the current feed.").foregroundStyle(AppTheme.muted) }
                }
                if tab == "Play-by-play" { SportsPlayByPlayView(game: current, periods: center?.playByPlay ?? []) }
                if tab == "Players" { SportsGamePlayersView(game: current, groups: center?.playerStats ?? []) }
            }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
        }
        .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
        .navigationTitle("Game center").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if let url = sportsHTTPSURL(game.link) { Link(destination: url) { Text(game.tennis?.source == "tennisexplorer" ? "Details ↗" : "ESPN ↗").font(.caption.bold()) }.accessibilityLabel("Open match source") }
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
        .task(id: "\(game.id)-\(revision)-\(current.canWatch)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            repeat {
                await loadStreams()
                guard current.canWatch, streams.isEmpty else { return }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
        .sheet(item: $selectedTeam) { item in NavigationStack { SportsTeamView(result: item).environmentObject(queue) } }
        .sheet(isPresented: $showMultiWatch) { NavigationStack { SportsMultiWatchView().environmentObject(queue) } }
        .sheet(isPresented: $showChat) { SportsGameChatScreen(game: current) }
        .onChange(of: current.isFinal) { _, final in if final && tab == "Latest play" { tab = "Play-by-play" } }
        .onChange(of: playback.isMinimized) { _, minimized in
            guard minimized else { return }
            selectedTeam = nil
            showMultiWatch = false
            dismiss()
        }
    }

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(current.isLive ? "LIVE" : current.league.title).font(.caption2.bold())
                Text(current.status).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted).lineLimit(2)
                Spacer(minLength: 6)
                if current.isLive { Text(current.league.title).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted) }
            }
            if let tennis = current.tennis {
                Text([tennis.tour.rawValue, tennis.tournament, tennis.discipline, tennis.round].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.muted)
                ForEach([current.away, current.home]) { player in
                    HStack { SportsTennisScoreRow(game: current, player: player); followButton(player) }
                }
            } else { VStack(spacing: 0) {
                ForEach([current.away, current.home]) { team in
                    HStack(spacing: 0) {
                        Button { selectedTeam = SportsTeamResult(league: game.league, team: team) } label: {
                            HStack(spacing: 10) {
                                RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(team.name).font(.subheadline.weight(current.winner?.id == team.id ? .bold : .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    if !team.record.isEmpty { Text(team.record).font(.caption2).foregroundStyle(AppTheme.muted) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 4) {
                                    if current.possessionTeam?.id == team.id {
                                        Image(systemName: current.league.sport == "football" ? "football.fill" : "basketball.fill")
                                            .font(.system(size: 14)).frame(width: 18, height: 18)
                                            .accessibilityLabel("\(team.name) in possession")
                                    }
                                    Text(current.state == "pre" || team.score.isEmpty ? "—" : team.score)
                                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                                    Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7)).frame(width: 7)
                                        .opacity(current.winner?.id == team.id ? 1 : 0).accessibilityHidden(true)
                                }.frame(minWidth: 48, alignment: .trailing)
                            }.frame(minHeight: 62).contentShape(Rectangle())
                        }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-team-\(team.id)")
                            .foregroundStyle(current.winner != nil && current.winner?.id != team.id ? AppTheme.muted : AppTheme.foreground)
                        followButton(team)
                    }
                    if team.id == current.away.id { Rectangle().fill(AppTheme.border.opacity(0.6)).frame(height: 0.5).accessibilityHidden(true) }
                }
            } }
            if current.isLive { SportsLiveSituationView(game: current) }
            Text([current.tennis?.timeConfirmed == false ? (current.date?.formatted(date: .abbreviated, time: .omitted) ?? "") + " · Time TBA" : current.date?.formatted(date: .abbreviated, time: .shortened) ?? "Time to be announced", current.venue]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(2)
        }.padding(14).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 0.5) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sports-game-scoreboard")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            SportsPlaybackOriginCard { origin in
                HStack(spacing: 10) {
                    if !current.isFinal { SportsTrackGameButton(game: current) }
                    if current.canWatch, let first = streams.first {
                        Button { play(first, origin: origin) } label: {
                            HStack(spacing: 7) {
                                Text("Watch")
                                Image(systemName: "play.fill").font(.system(size: 11))
                            }.font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 36)
                                .foregroundStyle(AppTheme.canvas)
                                .background(AppTheme.foreground, in: RoundedRectangle(cornerRadius: 10))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(HapticPlainButtonStyle())
                            .accessibilityLabel("Watch game").accessibilityIdentifier("sports-center-watch")
                    } else if current.canWatch && streamsLoading {
                        HStack { ProgressView(); Text("Finding streams…").font(.subheadline) }.frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Label(current.broadcasts.isEmpty ? current.league.title : current.broadcasts, systemImage: "tv")
                            .font(.caption).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        guard let first = streams.first else { return }
                        queue.add(SportsStream(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: first.url, alternatives: streams))
                        showMultiWatch = true
                    } label: {
                        Image(systemName: "rectangle.split.2x2").font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 36).streamifyControlSurface()
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                        .buttonStyle(HapticPlainButtonStyle()).disabled(streams.isEmpty || queue.streams.count >= 4)
                        .accessibilityLabel("Add to multi-watch")
                }
            }
            if let scoring = center?.scoring, !scoring.isEmpty { SportsScoringTable(game: current, periods: scoring) }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Watch sources").font(.title3.bold()); Spacer(); if streamsLoading { ProgressView() } }
                if let streamsError {
                    SportsSourcesUnavailableView(message: streamsError) { revision += 1 }
                } else if !streamsLoading && streams.isEmpty {
                    Text(current.canWatch ? "No matching stream is available. Sources depend on the provider and may appear closer to game time." : "Sources are available for live games and games starting within an hour.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }
                ForEach(streams) { stream in
                    SportsPlaybackOriginCard { origin in
                        HStack(spacing: 10) {
                            Text(stream.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Button { play(stream, origin: origin) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44).streamifyControlSurface() }
                                    .buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("Watch \(stream.title)")
                                Button {
                                    queue.add(SportsStream(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: stream.url, alternatives: streams))
                                    showMultiWatch = true
                                } label: { Image(systemName: "rectangle.split.2x2").frame(width: 44, height: 44).streamifyControlSurface() }.buttonStyle(HapticPlainButtonStyle())
                                    .disabled(queue.streams.count >= 4 || queue.streams.contains(where: { $0.url == stream.url })).accessibilityLabel("Add source to multi-watch")
                        }.padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func play(_ stream: SportsStream, origin: SportsPlaybackOrigin) {
        playback.play(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: stream.url, sources: streams, origin: origin, game: current)
    }

    private func followButton(_ team: SportsTeam) -> some View {
        let following = library.followedTeams.contains(team.key(in: game.league))
        return Button { library.toggleTeam(team.key(in: game.league)) } label: { Image(systemName: following ? "star.fill" : "star").foregroundStyle(following ? Color.yellow : AppTheme.muted).frame(width: 44, height: 44) }.buttonStyle(HapticPlainButtonStyle()).accessibilityLabel("\(following ? "Unfollow" : "Follow") \(team.name)")
            .accessibilityIdentifier("sports-game-follow-\(team.id)")
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
        do { streams = try await SportsService().streams(current); streamsError = nil }
        catch is CancellationError { }
        catch { if !Task.isCancelled { streamsError = error.localizedDescription } }
    }
}

private struct SportsSourcesUnavailableView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "play.slash")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources unavailable").font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: 36)
                        .streamifyControlSurface()
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(HapticPlainButtonStyle())
                    .accessibilityIdentifier("sports-source-retry")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 0.5) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sports-source-error")
    }
}

struct SportsTeamView: View {
    let result: SportsTeamResult
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SportsWatchQueue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
                        HStack { Image(systemName: following ? "star.fill" : "star").foregroundStyle(following ? Color.yellow : AppTheme.foreground); Text(following ? "Following" : "Follow team") }
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44).streamifyControlSurface()
                    }.buttonStyle(HapticPlainButtonStyle()).foregroundStyle(AppTheme.foreground)
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
            .task(id: "\(revision)-\(scenePhase == .active)") {
                guard scenePhase == .active else { return }
                loading = profile == nil
                defer { loading = false }
                repeat {
                    do { profile = try await SportsService().profile(result); error = nil; loading = false }
                    catch is CancellationError { return }
                    catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                } while !Task.isCancelled
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
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 42
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var teamWidth: CGFloat = 82
    @ScaledMetric(relativeTo: .body) private var periodWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var totalWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .title2) private var totalSize: CGFloat = 20

    private var subtitle: String {
        "\(game.league.title) · " + (game.league == .tennis ? "Set by set" : game.league == .mlb ? "Inning by inning" : game.league == .nhl ? "Period by period" : "Quarter by quarter")
    }
    private var teamColumnWidth: CGFloat { min(116, teamWidth) }
    private var totalColumnWidth: CGFloat { min(84, totalWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scoring").font(.subheadline.bold())
                Spacer()
                Text(game.league == .tennis ? "Sets" : game.league == .mlb ? "Innings" : game.league == .nhl ? "Periods" : "Quarters").font(.caption2).foregroundStyle(AppTheme.muted)
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    heading(game.league == .tennis ? "PLAYER" : "TEAM").frame(width: teamColumnWidth, alignment: .leading)
                    teamLabel(game.away, side: "Away", stripe: false)
                    teamLabel(game.home, side: "Home", stripe: true)
                }
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 0) {
                            ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                                VStack(spacing: 0) {
                                    heading(periodTitle((period.period ?? index + 1) - 1))
                                    periodCell(period.away, team: game.away, stripe: false)
                                    periodCell(period.home, team: game.home, stripe: true)
                                }.frame(width: max(periodWidth, geometry.size.width / CGFloat(max(1, periods.count))))
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("sports-scoring-period-\(index)")
                            }
                        }
                    }
                    .accessibilityLabel(game.league == .tennis ? "Set scores" : game.league == .mlb ? "Inning scores" : game.league == .nhl ? "Period scores" : "Quarter scores")
                    .accessibilityIdentifier("sports-scoring-periods")
                }
                VStack(spacing: 0) {
                    heading("TOTAL")
                    total(game.away, stripe: false)
                    total(game.home, stripe: true)
                }
                .frame(width: totalColumnWidth)
                .background(AppTheme.foreground.opacity(0.045))
            }
            .frame(height: headerHeight + rowHeight * 2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-scoring-table")
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
            .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity).frame(height: headerHeight)
    }
    private func teamLabel(_ team: SportsTeam, side: String, stripe: Bool) -> some View {
        HStack(spacing: 6) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.abbreviation.isEmpty ? team.name : team.abbreviation).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 6).frame(width: teamColumnWidth, height: rowHeight, alignment: .leading)
        .background(stripe ? AppTheme.foreground.opacity(0.025) : Color.clear)
        .accessibilityLabel("\(team.name), \(side)")
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
        case .nba, .wnba, .nfl, .ncaaf: return index < 4 ? "Q\(index + 1)" : index == 4 ? "OT" : "OT\(index - 3)"
        case .tennis: return "S\(index + 1)"
        }
    }

}
