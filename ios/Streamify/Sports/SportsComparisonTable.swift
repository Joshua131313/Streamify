import SwiftUI

struct SportsComparisonTable: View {
    let away: SportsTeam
    let home: SportsTeam
    let rows: [SportsStatRow]
    let title: String
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 70
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            HStack(spacing: 10) {
                teamHeading(away).frame(width: min(90, valueWidth))
                Text("STAT").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity)
                teamHeading(home).frame(width: min(90, valueWidth))
            }
            if rows.isEmpty {
                Text("Statistics will appear when the feed updates.").font(.subheadline).foregroundStyle(AppTheme.muted).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            value(row.away).frame(width: min(90, valueWidth))
                            Text(row.label).font(.subheadline).foregroundStyle(AppTheme.muted)
                                .multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: .infinity)
                            value(row.home).frame(width: min(90, valueWidth))
                        }
                        .padding(.vertical, 8).frame(minHeight: rowHeight)
                        .background(index.isMultiple(of: 2) ? AppTheme.foreground.opacity(0.025) : Color.clear)
                        .accessibilityElement(children: .contain)
                        if index < rows.count - 1 { Rectangle().fill(AppTheme.border.opacity(0.6)).frame(height: 0.5).accessibilityHidden(true) }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("sports-comparison-table")
    }

    private func teamHeading(_ team: SportsTeam) -> some View {
        VStack(spacing: 6) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 24, height: 24)
            Text(team.abbreviation.isEmpty ? team.name : team.abbreviation)
                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.foreground).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func value(_ text: String) -> some View {
        Text(text.isEmpty ? "—" : text).font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
            .foregroundStyle(AppTheme.foreground).lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity)
    }
}
