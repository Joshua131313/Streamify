import SwiftUI
import UIKit

enum SportsLiveTint {
    static let color = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.40, green: 0.83, blue: 0.59, alpha: 1)
        : UIColor(red: 0.08, green: 0.44, blue: 0.25, alpha: 1) })
}

/// The field mirrors with possession while keeping both teams' ends fixed.
/// Missing feed values never imply possession or a fabricated spot.
struct SportsLiveSituationView: View {
    let game: SportsGame
    private var football: Bool { game.league.sport == "football" }
    private var teamLabel: String? { game.possessionTeam.map { $0.abbreviation.isEmpty ? $0.name : $0.abbreviation } }

    var body: some View {
        if game.isLive, let situation = game.liveSituation {
            if football {
                if situation.downDistance != nil || situation.fieldPosition != nil || situation.fieldProgress?.isFinite == true {
                    VStack(alignment: .leading, spacing: 5) {
                        if situation.downDistance != nil || situation.fieldPosition != nil {
                            HStack(spacing: 4) {
                                if let down = situation.downDistance { Text(down).fontWeight(.semibold) }
                                if let position = situation.fieldPosition { Text("\(situation.downDistance == nil ? "" : "· ")\(position)").foregroundStyle(AppTheme.muted) }
                                Spacer(minLength: 0)
                            }.font(.system(size: 11)).lineLimit(1)
                        }
                        if let position = game.footballFieldPosition {
                            SportsFootballField(position: position,
                                offense: SportsTeamPalette.color(game.possessionTeam, fallback: AppTheme.foreground.opacity(0.30)))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Football field position")
                                .accessibilityValue("\(teamLabel.map { "\($0) possession. " } ?? "")\(Int((position.progress * 100).rounded())) yards from the offense’s goal line, advancing \(position.advancesRight ? "right" : "left")")
                                .accessibilityIdentifier("sports-field-\(game.id)")
                        }
                    }.accessibilityElement(children: .contain)
                }
            } else if game.league == .mlb, let baseball = situation.baseball {
                SportsBaseballSituationView(game: game, situation: baseball)
            } else if game.league == .nhl, let hockey = situation.hockey, game.hockeySummary != nil {
                SportsHockeySituationView(game: game, situation: hockey)
            } else if let teamLabel {
                Text("\(teamLabel) possession").font(.system(size: 11, weight: .medium))
                    .accessibilityIdentifier("sports-possession-\(game.id)")
            }
        }
    }
}

private struct SportsHockeySituationView: View {
    let game: SportsGame
    let situation: SportsHockeySituation
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(game.hockeySummary ?? "").font(.system(size: 11, weight: .semibold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
                }.padding(.horizontal, 9).frame(height: 30)
                    .background(AppTheme.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(HapticPlainButtonStyle()).accessibilityIdentifier("sports-hockey-tag-\(game.id)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach([game.away, game.home]) { team in
                        HStack {
                            Text(team.abbreviation).fontWeight(.semibold)
                            Spacer()
                            let skaters = team.id == game.away.id ? situation.awaySkaters : situation.homeSkaters
                            Text("\(skaters) skaters\(situation.emptyNetTeamIDs.contains(team.id) ? " · Empty net" : "")")
                        }
                    }
                    if let timer = situation.strengthTime {
                        HStack { Text("Strength timer").foregroundStyle(AppTheme.muted); Spacer(); Text(timer).monospacedDigit().fontWeight(.semibold) }
                    }
                    Text("Feed snapshot · \(game.status)").font(.caption2).foregroundStyle(AppTheme.muted)
                }.font(.caption).padding(10)
                    .background(AppTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("sports-hockey-details-\(game.id)")
            }
        }
    }
}

private enum SportsTeamPalette {
    static func color(_ team: SportsTeam?, fallback: Color) -> Color {
        guard let hex = team?.primaryColorHex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return fallback }
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

private struct SportsFootballField: View {
    let position: SportsFootballFieldPosition
    let offense: Color
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 3) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.foreground.opacity(0.08))
                    Rectangle().fill(offense).frame(width: geometry.size.width * position.progress)
                        .offset(x: geometry.size.width * position.fillStart)
                    ForEach(1..<10, id: \.self) { yard in
                        let fraction = Double(yard) / 10
                        let filled = position.advancesRight ? fraction <= position.ballPosition : fraction >= position.ballPosition
                        Rectangle().fill((filled ? Color.white : AppTheme.foreground).opacity(yard == 5 ? 0.8 : 0.55))
                            .frame(width: 1, height: yard == 5 ? 12 : 8)
                            .offset(x: geometry.size.width * CGFloat(yard) / 10)
                    }
                    Rectangle().fill(.white).frame(width: 2)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .offset(x: min(max(0, geometry.size.width * position.ballPosition - 1), max(0, geometry.size.width - 2)))
                    Image(systemName: position.advancesRight ? "arrow.right" : "arrow.left").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 1)
                        .frame(width: 12, height: 10)
                        .offset(x: min(max(2, geometry.size.width * position.ballPosition + (position.advancesRight ? -16 : 4)), max(2, geometry.size.width - 14)))
                }.frame(height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
                ZStack {
                    ForEach(0...10, id: \.self) { yard in
                        Text("\(yard <= 5 ? yard * 10 : (10 - yard) * 10)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(AppTheme.muted)
                            .position(x: min(max(5, geometry.size.width * CGFloat(yard) / 10), geometry.size.width - 5), y: 5)
                    }
                }.frame(height: 10)
            }
        }.frame(height: 27).padding(.vertical, 3)
            .environment(\.layoutDirection, .leftToRight)
    }
}

private struct SportsBaseballSituationView: View {
    let game: SportsGame
    let situation: SportsBaseballSituation
    @Environment(\.colorScheme) private var colorScheme
    private var ballColor: Color { colorScheme == .dark
        ? Color(red: 77/255, green: 207/255, blue: 149/255) : Color(red: 22/255, green: 129/255, blue: 91/255) }
    private var pitchColor: Color { colorScheme == .dark
        ? Color(red: 250/255, green: 117/255, blue: 129/255) : Color(red: 199/255, green: 71/255, blue: 85/255) }

    var body: some View {
        HStack(spacing: 16) {
            if situation.hasBaseData {
                SportsBaseballDiamond(situation: situation, gameID: game.id)
            }
            VStack(alignment: .leading, spacing: 10) {
                dots("balls", value: situation.balls, maximum: 4, color: ballColor)
                dots("strikes", value: situation.strikes, maximum: 3, color: pitchColor)
                dots("outs", value: situation.outs, maximum: 2, color: pitchColor, slots: 2)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }

    private func dots(_ name: String, value: Int?, maximum: Int, color: Color, slots: Int? = nil) -> some View {
        let filled = min(maximum, max(0, value ?? 0))
        return HStack(spacing: 6) {
            ForEach(0..<(slots ?? filled), id: \.self) { index in
                Circle().fill(index < filled ? color : .clear)
                    .overlay { Circle().strokeBorder(index < filled ? .clear : AppTheme.foreground.opacity(value == nil ? 0.25 : 0.55), lineWidth: 1.2) }
                    .frame(width: 10, height: 10)
            }
        }.frame(minWidth: 10, minHeight: 10, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name.capitalized)
            .accessibilityValue(value.map(String.init) ?? "Unknown")
            .accessibilityIdentifier("sports-baseball-\(name)-\(game.id)")
    }
}

private struct SportsBaseballDiamond: View {
    let situation: SportsBaseballSituation
    let gameID: String
    @Environment(\.colorScheme) private var colorScheme
    private var occupied: Color { colorScheme == .dark
        ? Color(red: 1, green: 0.81, blue: 0.40) : Color(red: 0.66, green: 0.35, blue: 0) }

    var body: some View {
        ZStack {
            base("first", value: situation.firstOccupied).position(x: 53, y: 35)
            base("second", value: situation.secondOccupied).position(x: 32, y: 14)
            base("third", value: situation.thirdOccupied).position(x: 11, y: 35)
        }.frame(width: 64, height: 48)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-diamond-\(gameID)")
    }

    private func base(_ name: String, value: Bool?) -> some View {
        RoundedRectangle(cornerRadius: 0.7).fill(value == true ? occupied : AppTheme.panel)
            .overlay { RoundedRectangle(cornerRadius: 0.7).strokeBorder(
                value == true ? occupied : AppTheme.foreground.opacity(value == nil ? 0.25 : 0.66),
                style: StrokeStyle(lineWidth: 1, dash: value == nil ? [1.2, 1.2] : [])) }
            .frame(width: 7.5, height: 7.5).rotationEffect(.degrees(45))
            .shadow(color: value == true ? occupied.opacity(0.22) : .clear, radius: 2)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(name.capitalized) base")
            .accessibilityValue(value.map { $0 ? "Occupied" : "Empty" } ?? "Unknown")
            .accessibilityIdentifier("sports-base-\(name)-\(gameID)")
    }
}
