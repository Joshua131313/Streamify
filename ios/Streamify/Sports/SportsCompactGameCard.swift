import SwiftUI
import UIKit

enum SportsLiveTint {
    static let color = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.40, green: 0.83, blue: 0.59, alpha: 1)
        : UIColor(red: 0.08, green: 0.44, blue: 0.25, alpha: 1) })
}

/// Field position is offense-relative: own goal on the left, opponent goal on
/// the right. Missing feed values never imply possession or a fabricated spot.
struct SportsLiveSituationView: View {
    let game: SportsGame
    private var football: Bool { game.league == .nfl || game.league == .ncaaf }
    private var teamLabel: String? { game.possessionTeam.map { $0.abbreviation.isEmpty ? $0.name : $0.abbreviation } }

    var body: some View {
        if game.isLive, let situation = game.liveSituation {
            if football {
                if situation.downDistance != nil || situation.fieldPosition != nil || teamLabel != nil {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            if let down = situation.downDistance { Text(down).fontWeight(.semibold) }
                            if let position = situation.fieldPosition { Text("· \(position)").foregroundStyle(AppTheme.muted) }
                            Spacer(minLength: 4)
                            if let teamLabel {
                                Text("\(teamLabel) ball").foregroundStyle(AppTheme.muted)
                                Image(systemName: "arrow.right").foregroundStyle(SportsLiveTint.color)
                            }
                        }.font(.system(size: 11)).lineLimit(1)
                        if let progress = situation.fieldProgress, progress.isFinite {
                            SportsFootballField(progress: min(1, max(0, progress)))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Football field position")
                                .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) yards from the offense’s goal line")
                                .accessibilityIdentifier("sports-field-\(game.id)")
                        }
                    }.accessibilityElement(children: .contain)
                }
            } else if let teamLabel {
                Text("\(teamLabel) possession").font(.system(size: 11, weight: .medium))
                    .accessibilityIdentifier("sports-possession-\(game.id)")
            }
        }
    }
}

private struct SportsFootballField: View {
    let progress: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(AppTheme.foreground.opacity(0.08))
                RoundedRectangle(cornerRadius: 3).fill(SportsLiveTint.color.opacity(0.60))
                    .frame(width: geometry.size.width * progress)
                ForEach(1..<10, id: \.self) { yard in
                    Rectangle().fill(AppTheme.foreground.opacity(yard == 5 ? 0.28 : 0.12))
                        .frame(width: 0.7).offset(x: geometry.size.width * CGFloat(yard) / 10)
                }
                Rectangle().fill(AppTheme.foreground).frame(width: 2, height: 13)
                    .offset(x: min(max(0, geometry.size.width * progress - 1), max(0, geometry.size.width - 2)))
            }
        }.frame(height: 9).padding(.vertical, 2)
    }
}
