import SwiftUI

struct SportsGameView: View {
    let game: SportsGame
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SportsWatchQueue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var center: SportsGameCenter?
    @State private var error: String?
    @State private var tab = "Overview"
    @State private var revision = 0
    @State private var streams: [SportsStream] = []
    @State private var streamsLoading = true
    @State private var streamsError: String?
    @State private var selectedStream: SportsStream?
    @State private var selectedTeam: SportsTeamResult?
    @State private var showMultiWatch = false
    private var current: SportsGame { center?.game ?? game }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(current.isLive ? "● LIVE · \(current.status)" : current.status).font(.caption.bold()).foregroundStyle(game.league.accent)
                    Text("\(current.away.name)\nat \(current.home.name)").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(current.date?.formatted(date: .abbreviated, time: .shortened) ?? "Time to be announced").font(.subheadline).foregroundStyle(AppTheme.muted)
                    if !current.venue.isEmpty { Text(current.venue).font(.caption).foregroundStyle(AppTheme.muted) }
                }
                SportsPanel {
                    ForEach([current.away, current.home]) { team in
                        HStack {
                            Button { selectedTeam = SportsTeamResult(league: game.league, team: team) } label: { SportsTeamScore(team: team, showScore: current.state != "pre") }.buttonStyle(.plain)
                            followButton(team)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(["Overview", "Scoring", "Team stats", "Latest play", "Chat"], id: \.self) { value in Pill(title: value, selected: tab == value) { tab = value } } }
                }
                if let error {
                    StateMessage(symbol: "exclamationmark.circle", title: "Detailed feed unavailable", message: error, actionTitle: "Retry", action: { revision += 1 })
                }
                if tab == "Overview" { overview }
                if tab == "Scoring" { statTable(center?.scoring ?? [], title: "Scoring") }
                if tab == "Team stats" { statTable(center?.statistics ?? [], title: "Team comparison") }
                if tab == "Latest play" {
                    SportsPanel { Label("Latest play", systemImage: "waveform.path").font(.headline); Text(center.flatMap { $0.latest.isEmpty ? nil : $0.latest } ?? "Play-by-play is not available in the current feed.").foregroundStyle(AppTheme.muted) }
                }
                if tab == "Chat" {
                    StateMessage(symbol: "bubble.left.and.bubble.right", title: "Matchup chat", message: "The shared Streamify chat requires a connected cloud account. iOS cloud sign-in has not been configured for this build.")
                }
            }.padding(20).padding(.bottom, 24)
        }
        .background(AppTheme.canvas)
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
        .fullScreenCover(item: $selectedStream) { stream in ProviderPlayerView(title: "\(game.away.abbreviation) vs \(game.home.abbreviation) · \(stream.title)", url: stream.url) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            SportsPanel {
                Text("Game information").font(.headline)
                Text("\(current.away.name) at \(current.home.name). \(current.status).").foregroundStyle(AppTheme.muted)
                Label(current.broadcasts.isEmpty ? "Broadcast not announced" : current.broadcasts, systemImage: "tv").font(.subheadline).foregroundStyle(AppTheme.muted)
                if current.canWatch, let first = streams.first {
                    Button { selectedStream = first } label: { Label("Watch game", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(14).foregroundStyle(Color.black).background(Color.white, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                }
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
                            Button { selectedStream = stream } label: { Label("Watch", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(AppTheme.accent)
                            Button {
                                queue.add(SportsStream(title: "\(game.away.abbreviation) vs \(game.home.abbreviation)", url: stream.url))
                                showMultiWatch = true
                            } label: { Image(systemName: "rectangle.split.2x2").frame(minWidth: 32, minHeight: 28) }.buttonStyle(.bordered)
                                .disabled(queue.streams.count >= 4 || queue.streams.contains(where: { $0.url == stream.url })).accessibilityLabel("Add source to multi-watch")
                        }
                    }
                }
            }
        }
    }

    private func followButton(_ team: SportsTeam) -> some View {
        let following = library.followedTeams.contains(team.key(in: game.league))
        return Button { library.toggleTeam(team.key(in: game.league)) } label: { Image(systemName: following ? "star.fill" : "star").foregroundStyle(game.league.accent).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("\(following ? "Unfollow" : "Follow") \(team.name)")
    }

    @ViewBuilder private func statTable(_ rows: [SportsStatRow], title: String) -> some View {
        if rows.isEmpty {
            StateMessage(symbol: "chart.bar.xaxis", title: "Awaiting \(title.lowercased())", message: "A breakdown is not available in the current feed.")
        } else {
            SportsPanel {
                HStack { Text(current.away.abbreviation).foregroundStyle(game.league.accent); Spacer(); Text(title).foregroundStyle(AppTheme.muted); Spacer(); Text(current.home.abbreviation).foregroundStyle(game.league.accent) }.font(.caption.bold())
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Text(row.away).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.label).font(.caption).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .center)
                        Text(row.home).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .trailing)
                    }.font(.subheadline).padding(.vertical, 5)
                    if row.id != rows.last?.id { Divider() }
                }
            }
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
                    Button { library.toggleTeam(result.id) } label: { Label(following ? "Following" : "Follow team", systemImage: following ? "star.fill" : "star").frame(minHeight: 30) }.buttonStyle(.borderedProminent).tint(result.league.accent).foregroundStyle(Color.black)
                }
                HStack(spacing: 8) { ForEach(["Schedule", "Results", "Roster"], id: \.self) { value in Pill(title: value, selected: tab == value) { tab = value } } }
                if loading { ProgressView("Loading team…").frame(maxWidth: .infinity).padding(24) }
                if let error { StateMessage(symbol: "wifi.exclamationmark", title: "Team unavailable", message: error, actionTitle: "Retry", action: { revision += 1 }) }
                if let profile {
                    if tab == "Roster" { roster(profile) } else { schedule(profile) }
                }
            }.padding(20).padding(.bottom, 24)
        }.background(AppTheme.canvas).navigationTitle("\(result.league.title) · Team").navigationBarTitleDisplayMode(.inline)
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
            ForEach(profile.roster) { player in
                HStack(spacing: 16) {
                    Text(player.number.isEmpty ? "—" : player.number).font(.title3.bold().monospacedDigit()).foregroundStyle(result.league.accent).frame(width: 42)
                    VStack(alignment: .leading, spacing: 5) { Text(player.name).font(.subheadline.weight(.semibold)); Text([player.position, player.height].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(AppTheme.muted) }
                    Spacer(minLength: 0)
                }.padding(16).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            }
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
