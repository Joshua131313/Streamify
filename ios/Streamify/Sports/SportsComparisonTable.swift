import SwiftUI

struct SportsComparisonTable: View {
    let away: SportsTeam
    let home: SportsTeam
    let rows: [SportsStatRow]
    let title: String
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            HStack(spacing: 8) {
                teamHeading(away).frame(width: min(90, valueWidth))
                Text("STAT").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity)
                teamHeading(home).frame(width: min(90, valueWidth))
            }.frame(minHeight: 32)
            if rows.isEmpty {
                Text("Statistics will appear when the feed updates.").font(.subheadline).foregroundStyle(AppTheme.muted).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 8) {
                            value(row.away).frame(width: min(90, valueWidth))
                            Text(row.label).font(.caption).foregroundStyle(AppTheme.muted)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                            value(row.home).frame(width: min(90, valueWidth))
                        }
                        .padding(.vertical, 5).frame(minHeight: rowHeight)
                        .background(index.isMultiple(of: 2) ? AppTheme.foreground.opacity(0.025) : Color.clear)
                        .accessibilityElement(children: .contain)
                        if index < rows.count - 1 { Rectangle().fill(AppTheme.border.opacity(0.6)).frame(height: 0.5).accessibilityHidden(true) }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("sports-comparison-table")
    }

    private func teamHeading(_ team: SportsTeam) -> some View {
        HStack(spacing: 5) {
            RemoteArtwork(url: team.logoURL, contentMode: .fit).frame(width: 20, height: 20)
            Text(team.abbreviation.isEmpty ? team.name : team.abbreviation)
                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.foreground).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func value(_ text: String) -> some View {
        Text(text.isEmpty ? "—" : text).font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
            .foregroundStyle(AppTheme.foreground).lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity)
    }
}
