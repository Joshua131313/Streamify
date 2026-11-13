import SwiftUI

struct SportsGameField: View {
    let game: SportsGame

    private var name: String {
        switch game.league {
        case .nfl, .ncaaf: return "Football field"
        case .nba, .wnba, .ncaam, .ncaaw: return "Basketball court"
        case .nhl: return "Hockey rink"
        case .mlb: return "Baseball diamond"
        case .tennis: return "Tennis court"
        }
    }

    private var background: Color {
        switch game.league {
        case .nfl, .ncaaf, .mlb: return Color(red: 0.10, green: 0.29, blue: 0.20)
        case .nba, .wnba, .ncaam, .ncaaw: return Color(red: 0.31, green: 0.20, blue: 0.13)
        case .nhl: return Color(red: 0.14, green: 0.25, blue: 0.32)
        case .tennis: return Color(red: 0.13, green: 0.24, blue: 0.34)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.headline)
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14)
                guard bounds.width > 0, bounds.height > 0 else { return }
                let field = SportsFieldDrawing(context: context, bounds: bounds)
                switch game.league {
                case .nfl, .ncaaf: field.football(position: game.footballFieldPosition)
                case .nba, .wnba, .ncaam, .ncaaw: field.basketball()
                case .nhl: field.hockey()
                case .mlb: field.baseball(situation: game.isLive ? game.liveSituation?.baseball : nil)
                case .tennis: field.tennis()
                }
            }
            .aspectRatio(2.05, contentMode: .fit).frame(maxWidth: 620)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            if game.isLive { context }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-center-field-\(game.league.rawValue)")
    }

    @ViewBuilder private var context: some View {
        switch game.league {
        case .nfl, .ncaaf:
            if let position = game.footballFieldPosition {
                let spot = game.liveSituation?.fieldPosition ?? "\(Int((position.progress * 100).rounded())) yards from the offense’s goal line"
                Label([game.liveSituation?.downDistance, spot].compactMap { $0 }.joined(separator: " · "), systemImage: "location.fill")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        case .mlb:
            if let situation = game.liveSituation?.baseball { SportsBaseballSituationView(game: game, situation: situation) }
        case .nba, .wnba, .ncaam, .ncaaw, .nhl:
            SportsLiveSituationView(game: game)
        case .tennis:
            if let server = [game.away, game.home].first(where: { $0.id == game.tennis?.servingID }) {
                Label("\(server.name) serving", systemImage: "tennis.racket").font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
    }
}

private struct SportsFieldDrawing {
    let context: GraphicsContext
    let bounds: CGRect
    private let lineColor = Color.white.opacity(0.64)
    private let markerColor = Color(red: 1, green: 0.84, blue: 0.38)

    func football(position: SportsFootballFieldPosition?) {
        context.fill(Path(rect(0, 0, 0.0833, 1)), with: .color(.white.opacity(0.12)))
        context.fill(Path(rect(0.9167, 0, 0.0833, 1)), with: .color(.white.opacity(0.12)))
        outline()
        for yard in stride(from: 0, through: 100, by: 5) {
            let x = (CGFloat(yard) + 10) / 120
            vertical(x, color: .white.opacity(yard % 10 == 0 ? 0.65 : 0.23))
            if yard % 10 == 0, (10...90).contains(yard) {
                let label = Text("\(min(yard, 100 - yard))").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                context.draw(label, at: point(x, 0.18))
                context.draw(label, at: point(x, 0.82))
            }
        }
        guard let position else { return }
        let x = (CGFloat(position.ballPosition) * 100 + 10) / 120
        vertical(x, color: markerColor, width: 2.5)
        dot(x, 0.5, diameter: 8)
    }

    func basketball() {
        outline()
        vertical(0.5)
        circle(0.5, 0.5, radius: bounds.height * 0.14)
        context.stroke(Path(rect(0, 0.35, 0.18, 0.30)), with: .color(lineColor), lineWidth: 1)
        context.stroke(Path(rect(0.82, 0.35, 0.18, 0.30)), with: .color(lineColor), lineWidth: 1)
        circle(0.18, 0.5, radius: bounds.height * 0.13)
        circle(0.82, 0.5, radius: bounds.height * 0.13)
        circle(0.045, 0.5, radius: 3)
        circle(0.955, 0.5, radius: 3)
        arc(from: point(0, 0.09), to: point(0, 0.91), via: point(0.58, 0.5))
        arc(from: point(1, 0.09), to: point(1, 0.91), via: point(0.42, 0.5))
    }

    func hockey() {
        outline(radius: 25)
        vertical(0.5, color: .red.opacity(0.8), width: 1.6)
        for x in [0.34, 0.66] as [CGFloat] { vertical(x, color: Color(red: 0.47, green: 0.72, blue: 1), width: 1.6) }
        circle(0.5, 0.5, radius: bounds.height * 0.15)
        for x in [0.19, 0.81] as [CGFloat] {
            for y in [0.29, 0.71] as [CGFloat] { circle(x, y, radius: bounds.height * 0.13, color: .red.opacity(0.7)) }
        }
        for x in [0.07, 0.93] as [CGFloat] {
            line(point(x, 0.08), point(x, 0.92), color: .red.opacity(0.56))
            context.stroke(Path(rect(x - 0.018, 0.43, 0.036, 0.14)), with: .color(lineColor), lineWidth: 1)
        }
    }

    func baseball(situation: SportsBaseballSituation?) {
        let center = bounds.midX
        let distance = min(bounds.width * 0.30, bounds.height * 0.30)
        let plate = CGPoint(x: center, y: bounds.minY + bounds.height * 0.89)
        let first = CGPoint(x: center + distance, y: plate.y - distance)
        let second = CGPoint(x: center, y: plate.y - 2 * distance)
        let third = CGPoint(x: center - distance, y: first.y)
        let foulDistance = min(bounds.width * 0.48, bounds.height * 0.74)
        let left = CGPoint(x: center - foulDistance, y: bounds.minY + bounds.height * 0.15)
        let right = CGPoint(x: center + foulDistance, y: left.y)
        arc(from: left, to: right, via: point(0.5, -0.24))
        line(plate, left)
        line(plate, right)
        var infield = Path()
        infield.addLines([plate, first, second, third, plate])
        context.fill(infield, with: .color(Color(red: 0.52, green: 0.34, blue: 0.20)))
        context.stroke(infield, with: .color(lineColor), lineWidth: 1)
        let bases: [(CGPoint, Bool?)] = [(first, situation?.firstOccupied), (second, situation?.secondOccupied), (third, situation?.thirdOccupied), (plate, nil)]
        for (base, occupied) in bases {
            let square = Path(CGRect(x: base.x - 3, y: base.y - 3, width: 6, height: 6))
            context.fill(square, with: .color(occupied == true ? markerColor : .white.opacity(0.8)))
        }
    }

    func tennis() {
        outline()
        for y in [0.13, 0.87] as [CGFloat] { line(point(0, y), point(1, y)) }
        for x in [0.25, 0.75] as [CGFloat] { line(point(x, 0.13), point(x, 0.87)) }
        line(point(0.25, 0.5), point(0.75, 0.5))
        vertical(0.5, color: .white, width: 2.2)
    }

    private func outline(radius: CGFloat = 0) {
        let shape = RoundedRectangle(cornerRadius: radius).path(in: bounds)
        context.stroke(shape, with: .color(lineColor), lineWidth: 1)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * bounds.width, height: height * bounds.height))
    }

    private func line(_ start: CGPoint, _ end: CGPoint, color: Color? = nil, width: CGFloat = 1) {
        var path = Path()
        path.move(to: start); path.addLine(to: end)
        context.stroke(path, with: .color(color ?? lineColor), lineWidth: width)
    }

    private func vertical(_ x: CGFloat, color: Color? = nil, width: CGFloat = 1) {
        line(point(x, 0), point(x, 1), color: color, width: width)
    }

    private func arc(from: CGPoint, to: CGPoint, via control: CGPoint) {
        var path = Path()
        path.move(to: from); path.addQuadCurve(to: to, control: control)
        context.stroke(path, with: .color(lineColor), lineWidth: 1)
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, color: Color? = nil) {
        let center = point(x, y)
        let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: ring), with: .color(color ?? lineColor), lineWidth: 1)
    }

    private func dot(_ x: CGFloat, _ y: CGFloat, diameter: CGFloat) {
        let center = point(x, y)
        let marker = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.fill(Path(ellipseIn: marker), with: .color(markerColor))
    }
}
