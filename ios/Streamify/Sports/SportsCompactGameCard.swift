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
    private var football: Bool { game.league.sport == "football" }
    private var teamLabel: String? { game.possessionTeam.map { $0.abbreviation.isEmpty ? $0.name : $0.abbreviation } }
    private var opponent: SportsTeam? {
        guard let offense = game.possessionTeam else { return nil }
        return offense.id == game.home.id ? game.away : game.home
    }

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
                                Image(systemName: "arrow.right").foregroundStyle(AppTheme.foreground)
                            }
                        }.font(.system(size: 11)).lineLimit(1)
                        if let progress = situation.fieldProgress, progress.isFinite {
                            SportsFootballField(progress: min(1, max(0, progress)),
                                offense: SportsTeamPalette.color(game.possessionTeam, fallback: AppTheme.foreground.opacity(0.30)),
                                opponent: SportsTeamPalette.color(opponent, fallback: AppTheme.foreground.opacity(0.10)))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Football field position")
                                .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) yards from the offense’s goal line")
                                .accessibilityIdentifier("sports-field-\(game.id)")
                        }
                    }.accessibilityElement(children: .contain)
                }
            } else if game.league == .mlb, let baseball = situation.baseball {
                SportsBaseballSituationView(game: game, situation: baseball)
            } else if let teamLabel {
                Text("\(teamLabel) possession").font(.system(size: 11, weight: .medium))
                    .accessibilityIdentifier("sports-possession-\(game.id)")
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
    let progress: Double
    let offense: Color
    let opponent: Color
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 3) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(opponent)
                    Rectangle().fill(offense).frame(width: geometry.size.width * progress)
                    ForEach(1..<10, id: \.self) { yard in
                        Rectangle().fill(.white.opacity(yard == 5 ? 0.8 : 0.55))
                            .frame(width: 1, height: yard == 5 ? 16 : 11)
                            .offset(x: geometry.size.width * CGFloat(yard) / 10)
                    }
                    Rectangle().fill(.white).frame(width: 2)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .offset(x: min(max(0, geometry.size.width * progress - 1), max(0, geometry.size.width - 2)))
                }.frame(height: 18).clipShape(RoundedRectangle(cornerRadius: 3))
                ZStack {
                    ForEach(0...10, id: \.self) { yard in
                        Text("\(yard <= 5 ? yard * 10 : (10 - yard) * 10)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(AppTheme.muted)
                            .position(x: min(max(5, geometry.size.width * CGFloat(yard) / 10), geometry.size.width - 5), y: 5)
                    }
                }.frame(height: 10)
            }
        }.frame(height: 31).padding(.vertical, 3)
    }
}

private struct SportsBaseballSituationView: View {
    let game: SportsGame
    let situation: SportsBaseballSituation
    private var battingTeam: SportsTeam? {
        situation.half == .top ? game.away : situation.half == .bottom ? game.home : nil
    }

    var body: some View {
        HStack(spacing: 14) {
            if situation.hasBaseData {
                SportsBaseballDiamond(situation: situation, gameID: game.id,
                    occupied: SportsTeamPalette.color(battingTeam, fallback: AppTheme.foreground))
            }
            VStack(alignment: .leading, spacing: 7) {
                if let inning = situation.inning, let half = situation.half {
                    Text("\(half.rawValue) \(inning)").font(.caption.weight(.semibold))
                }
                HStack(spacing: 12) {
                    if let balls = situation.balls { count("Balls", value: balls) }
                    if let strikes = situation.strikes { count("Strikes", value: strikes) }
                    if let outs = situation.outs { count("Outs", value: outs) }
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }

    private func count(_ title: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(AppTheme.muted)
            Text(String(value)).fontWeight(.semibold).monospacedDigit()
        }.font(.caption2).accessibilityElement(children: .combine)
    }
}

private struct SportsBaseballDiamond: View {
    let situation: SportsBaseballSituation
    let gameID: String
    let occupied: Color

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 32, y: 56))
                path.addLines([CGPoint(x: 56, y: 32), CGPoint(x: 32, y: 8), CGPoint(x: 8, y: 32), CGPoint(x: 32, y: 56)])
            }.stroke(AppTheme.muted.opacity(0.55), lineWidth: 1)
            base("first", value: situation.firstOccupied).position(x: 56, y: 32)
            base("second", value: situation.secondOccupied).position(x: 32, y: 8)
            base("third", value: situation.thirdOccupied).position(x: 8, y: 32)
            SportsHomePlate().fill(AppTheme.panel)
                .overlay { SportsHomePlate().stroke(AppTheme.foreground.opacity(0.7), lineWidth: 1) }
                .frame(width: 10, height: 10).position(x: 32, y: 56)
                .accessibilityElement(children: .ignore).accessibilityLabel("Home plate")
                .accessibilityIdentifier("sports-homeplate-\(gameID)")
        }.frame(width: 64, height: 64)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-diamond-\(gameID)")
    }

    private func base(_ name: String, value: Bool?) -> some View {
        Rectangle().fill(value == true ? occupied : AppTheme.panel)
            .overlay { Rectangle().stroke(value == true ? AppTheme.foreground.opacity(0.75) : AppTheme.muted.opacity(value == nil ? 0.35 : 0.9), lineWidth: 1) }
            .frame(width: 10, height: 10).rotationEffect(.degrees(45))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(name.capitalized) base")
            .accessibilityValue(value.map { $0 ? "Occupied" : "Empty" } ?? "Unknown")
            .accessibilityIdentifier("sports-base-\(name)-\(gameID)")
    }
}

private struct SportsHomePlate: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLines([CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                           CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)])
            path.closeSubpath()
        }
    }
}
