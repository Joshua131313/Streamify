import SwiftUI
import UIKit

enum SportsLiveTint {
    static let color = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.40, green: 0.83, blue: 0.59, alpha: 1)
        : UIColor(red: 0.08, green: 0.44, blue: 0.25, alpha: 1) })
}

/// Soft corner spotlights and a diagonal surface shared by every league card.
private struct SportsSpotlightBackground: View {
    let game: SportsGame
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            let dark = colorScheme == .dark
            let radius = max(geometry.size.width * 0.78, geometry.size.height * 0.95)
            ZStack {
                LinearGradient(colors: dark
                    ? [Color(red: 32/255, green: 32/255, blue: 38/255), Color(red: 25/255, green: 25/255, blue: 31/255)]
                    : [.white, Color(red: 246/255, green: 245/255, blue: 248/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [SportsTeamPalette.color(game.away, fallback: Color(red: 106/255, green: 119/255, blue: 156/255)).opacity(dark ? 0.12 : 0.07), .clear],
                    center: .topLeading, startRadius: 0, endRadius: radius)
                RadialGradient(colors: [SportsTeamPalette.color(game.home, fallback: Color(red: 128/255, green: 105/255, blue: 130/255)).opacity(dark ? 0.10 : 0.06), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: radius)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension View {
    func sportsSpotlightCard(game: SportsGame) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return background { SportsSpotlightBackground(game: game) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(AppTheme.foreground.opacity(0.07), lineWidth: 0.7).allowsHitTesting(false).accessibilityHidden(true) }
            .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 5)
    }
}

/// The field mirrors with possession while keeping both teams' ends fixed.
/// Missing feed values never imply possession or a fabricated spot.
struct SportsLiveSituationView: View {
    let game: SportsGame
    private var football: Bool { game.league.sport == "football" }
    private var teamLabel: String? { game.possessionTeam.map { $0.abbreviation.isEmpty ? $0.name : $0.abbreviation } }

    var body: some View {
        if football {
            let situation = game.isLive ? game.liveSituation : nil
            let position = game.footballFieldPosition
            VStack(alignment: .leading, spacing: 5) {
                if situation?.downDistance != nil || situation?.fieldPosition != nil {
                    HStack(spacing: 4) {
                        if let down = situation?.downDistance { Text(down).fontWeight(.semibold) }
                        if let spot = situation?.fieldPosition { Text("\(situation?.downDistance == nil ? "" : "· ")\(spot)").foregroundStyle(AppTheme.muted) }
                        Spacer(minLength: 0)
                    }.font(.system(size: 11)).lineLimit(1)
                }
                SportsFootballField(position: position,
                    offense: SportsTeamPalette.color(game.possessionTeam, fallback: AppTheme.foreground.opacity(0.30)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Football field position")
                    .accessibilityValue(position.map { field in "\(teamLabel.map { "\($0) possession. " } ?? "")\(Int((field.progress * 100).rounded())) yards from the offense’s goal line, advancing \(field.advancesRight ? "right" : "left")" } ?? "Field position unavailable")
                    .accessibilityIdentifier("sports-field-\(game.id)")
            }.accessibilityElement(children: .contain)
        } else if game.isLive, let situation = game.liveSituation {
            if game.league == .mlb, let baseball = situation.baseball {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(game.hockeySummary ?? "").font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(2)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
                }.padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: 34)
                    .background(AppTheme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(AppTheme.foreground.opacity(0.10), lineWidth: 0.7) }
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
                }.font(.caption).padding(12)
                    .background(AppTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border, lineWidth: 0.5) }
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
    let position: SportsFootballFieldPosition?
    let offense: Color
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 3) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.foreground.opacity(0.08))
                    if let position {
                        Rectangle().fill(offense).frame(width: geometry.size.width * position.progress)
                            .offset(x: geometry.size.width * position.fillStart)
                    }
                    ForEach(1..<10, id: \.self) { yard in
                        let fraction = Double(yard) / 10
                        let filled = position.map { $0.advancesRight ? fraction <= $0.ballPosition : fraction >= $0.ballPosition } ?? false
                        Rectangle().fill((filled ? Color.white : AppTheme.foreground).opacity(yard == 5 ? 0.8 : 0.55))
                            .frame(width: 1, height: yard == 5 ? 12 : 8)
                            .offset(x: geometry.size.width * CGFloat(yard) / 10)
                    }
                    if let position {
                        Rectangle().fill(.white).frame(width: 2)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .offset(x: min(max(0, geometry.size.width * position.ballPosition - 1), max(0, geometry.size.width - 2)))
                        Image(systemName: position.advancesRight ? "arrow.right" : "arrow.left").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 1)
                            .frame(width: 12, height: 10)
                            .offset(x: min(max(2, geometry.size.width * position.ballPosition + (position.advancesRight ? -16 : 4)), max(2, geometry.size.width - 14)))
                    }
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

struct SportsBaseballSituationView: View {
    let game: SportsGame
    let situation: SportsBaseballSituation
    @Environment(\.colorScheme) private var colorScheme
    private var ballColor: Color { colorScheme == .dark
        ? Color(red: 102/255, green: 212/255, blue: 150/255) : Color(red: 22/255, green: 129/255, blue: 91/255) }
    private var pitchColor: Color { colorScheme == .dark
        ? Color(red: 231/255, green: 119/255, blue: 123/255) : Color(red: 199/255, green: 71/255, blue: 85/255) }

    var body: some View {
        HStack(spacing: 9) {
            if situation.hasBaseData {
                SportsBaseballDiamond(situation: situation, gameID: game.id)
            }
            VStack(alignment: .leading, spacing: 4) {
                dots("balls", value: situation.balls, maximum: 4, color: ballColor)
                dots("strikes", value: situation.strikes, maximum: 3, color: pitchColor)
                dots("outs", value: situation.outs, maximum: 2, color: pitchColor, slots: 2)
            }
        }.frame(height: 36).fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sports-baseball-situation-\(game.id)")
    }

    private func dots(_ name: String, value: Int?, maximum: Int, color: Color, slots: Int? = nil) -> some View {
        let filled = min(maximum, max(0, value ?? 0))
        return HStack(spacing: 4) {
            ForEach(0..<(slots ?? filled), id: \.self) { index in
                Circle().fill(index < filled ? color : .clear)
                    .overlay { Circle().strokeBorder(index < filled ? .clear : AppTheme.foreground.opacity(value == nil ? 0.25 : 0.55), lineWidth: 1.2) }
                    .frame(width: 7, height: 7)
            }
        }.frame(minWidth: 29, minHeight: 7, alignment: .leading)
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
    private var occupied: Color { colorScheme == .dark ? .white : AppTheme.foreground }

    var body: some View {
        ZStack {
            base("first", value: situation.firstOccupied).position(x: 37, y: 24)
            base("second", value: situation.secondOccupied).position(x: 23, y: 10)
            base("third", value: situation.thirdOccupied).position(x: 9, y: 24)
        }.frame(width: 46, height: 34)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-diamond-\(gameID)")
    }

    private func base(_ name: String, value: Bool?) -> some View {
        RoundedRectangle(cornerRadius: 0.9).fill(value == true ? occupied : .clear)
            .overlay { RoundedRectangle(cornerRadius: 0.9).strokeBorder(
                value == true ? occupied : AppTheme.foreground.opacity(value == nil ? 0.25 : 0.45),
                style: StrokeStyle(lineWidth: 1.1, dash: value == nil ? [1.2, 1.2] : [])) }
            .frame(width: 12.5, height: 12.5).rotationEffect(.degrees(45))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(name.capitalized) base")
            .accessibilityValue(value.map { $0 ? "Occupied" : "Empty" } ?? "Unknown")
            .accessibilityIdentifier("sports-base-\(name)-\(gameID)")
    }
}

/// One footer row at normal sizes; context stays above the actions when space
/// is tight or text is enlarged. Each child keeps a single identity and tap target.
struct SportsBaseballCardFooterLayout: Layout {
    private let gap: CGFloat = 12
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let actions = subviews[1].sizeThatFits(.unspecified)
        let ideal = subviews[0].sizeThatFits(.unspecified)
        let width = proposal.width ?? ideal.width + gap + actions.width
        let context = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let inline = context.width + gap + actions.width <= width
        return CGSize(width: width, height: inline ? max(context.height, actions.height) : context.height + 6 + actions.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let context = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let actions = subviews[1].sizeThatFits(.unspecified)
        let inline = context.width + gap + actions.width <= bounds.width
        subviews[0].place(at: CGPoint(x: bounds.minX, y: inline ? bounds.midY - context.height / 2 : bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: context.width, height: context.height))
        subviews[1].place(at: CGPoint(x: bounds.maxX - actions.width, y: inline ? bounds.midY - actions.height / 2 : bounds.maxY - actions.height), anchor: .topLeading, proposal: .unspecified)
    }
}
