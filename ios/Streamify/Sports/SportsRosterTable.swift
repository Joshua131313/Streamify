import SwiftUI

/// Fixed position/number columns leave the remaining width for player names.
struct SportsRosterTable: View {
    let players: [SportsRosterPlayer]
    var accent: Color = AppTheme.accent
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 60

    init(_ players: [SportsRosterPlayer], accent: Color = AppTheme.accent) {
        self.players = players
        self.accent = accent
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("POS").frame(width: 42).accessibilityLabel("Position")
                Text("#").frame(width: 34).accessibilityLabel("Jersey number")
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 14).frame(minHeight: 38).background(AppTheme.controlFill)

            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: 12) {
                    HStack(spacing: 11) {
                        photo(player)
                        Text(player.name).font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.foreground).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(player.position.isEmpty ? "—" : player.position)
                        .font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted)
                        .frame(width: 42).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel("Position \(player.position.isEmpty ? "unavailable" : player.position)")
                    Text(player.number.isEmpty ? "—" : player.number)
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(AppTheme.foreground)
                        .frame(width: 34).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel("Jersey number \(player.number.isEmpty ? "unavailable" : player.number)")
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: rowHeight)
                .background(index.isMultiple(of: 2) ? Color.clear : AppTheme.foreground.opacity(0.025))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sports-roster-player-\(player.id)")
                if index < players.count - 1 { Rectangle().fill(AppTheme.border).frame(height: 0.5).accessibilityHidden(true) }
            }
        }
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-team-roster")
    }

    private func photo(_ player: SportsRosterPlayer) -> some View {
        Circle().fill(accent.opacity(0.12)).frame(width: 36, height: 36)
            .overlay {
                AsyncImage(url: player.photoURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "person.fill").font(.system(size: 20)).foregroundStyle(AppTheme.muted) }
                }.frame(width: 36, height: 36).clipped()
            }
            .clipShape(Circle()).allowsHitTesting(false).accessibilityHidden(true)
    }
}
