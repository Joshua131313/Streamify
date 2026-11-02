import Foundation
import SwiftUI

/// Keep revealed rows stable across refreshes and returning to a recent filter.
struct SportsPageWindow {
    let pageSize: Int
    private let maximumScopes: Int
    private var limits: [String: Int] = [:]
    private var recent: [String] = []
    init(pageSize: Int = 24, maximumScopes: Int = 24) {
        self.pageSize = max(1, pageSize); self.maximumScopes = max(1, maximumScopes)
    }
    func count(total: Int, scope: String) -> Int { min(max(0, total), limits[scope] ?? pageSize) }
    @discardableResult mutating func advance(total: Int, scope: String, expectedCount: Int) -> Bool {
        let current = count(total: total, scope: scope)
        guard current == expectedCount, current < total else { return false }
        limits[scope] = min(total, current + pageSize)
        recent.removeAll { $0 == scope }; recent.append(scope)
        while recent.count > maximumScopes { limits.removeValue(forKey: recent.removeFirst()) }
        return true
    }
    static func nearViewport(_ frame: CGRect, viewport: CGRect, axis: Axis = .vertical) -> Bool {
        guard viewport.width > 0, viewport.height > 0, frame.width > 0, frame.height > 0 else { return false }
        if axis == .horizontal {
            return frame.maxY >= viewport.minY && frame.minY <= viewport.maxY &&
                frame.maxX >= viewport.minX && frame.minX <= viewport.maxX + 160
        }
        return frame.maxX >= viewport.minX && frame.minX <= viewport.maxX &&
            frame.maxY >= viewport.minY && frame.minY <= viewport.maxY + 160
    }
}

private struct SportsPagingViewportKey: EnvironmentKey { static let defaultValue: CGRect = .zero }
private extension EnvironmentValues {
    var sportsPagingViewport: CGRect {
        get { self[SportsPagingViewportKey.self] }
        set { self[SportsPagingViewportKey.self] = newValue }
    }
}
private struct SportsPagingViewportModifier: ViewModifier {
    @State private var viewport: CGRect = .zero
    func body(content: Content) -> some View {
        content.environment(\.sportsPagingViewport, viewport)
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear.onAppear { viewport = frame }.onChange(of: frame) { _, value in viewport = value }
                }.allowsHitTesting(false)
            }
    }
}
extension View {
    func sportsPagingViewport() -> some View { modifier(SportsPagingViewportModifier()) }
}

/// A lazy stack can prefetch views. Geometry, rather than onAppear alone, gates
/// automatic expansion; a stale footer cannot reveal the same page twice.
struct SportsLoadMoreRows: View {
    let label: String
    let remaining: Int
    let pageID: String
    var axis: Axis = .vertical
    var automatic = true
    let load: () -> Void
    @Environment(\.sportsPagingViewport) private var viewport
    @State private var frame: CGRect = .zero
    @State private var requestedPage: String?
    var body: some View {
        Button(action: load) {
            HStack(spacing: 8) {
                Text("More \(label)")
                Text("\(remaining) remaining").foregroundStyle(AppTheme.muted)
            }.font(.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(HapticPlainButtonStyle())
            .accessibilityIdentifier("sports-load-more-\(label)")
            .background {
                GeometryReader { geometry in
                    let position = geometry.frame(in: .global)
                    Color.clear.onAppear { frame = position; revealIfVisible() }
                        .onChange(of: position) { _, value in frame = value; revealIfVisible() }
                }.allowsHitTesting(false)
            }
            .onChange(of: viewport) { _, _ in revealIfVisible() }
    }
    private func revealIfVisible() {
        guard automatic, remaining > 0, requestedPage != pageID,
              SportsPageWindow.nearViewport(frame, viewport: viewport, axis: axis) else { return }
        requestedPage = pageID; load()
    }
}

/// Calendar dots retain no team artwork, rosters, scoring or player models.
struct SportsCalendarEventMarker: Sendable {
    let id: String
    let league: SportsLeague
    let date: Date?
    let state: String
    init(game: SportsGame) { id = game.id; league = game.league; date = game.date; state = game.state }
    private init(id: String, league: SportsLeague, date: Date?, state: String) {
        self.id = "\(league.rawValue):\(id)"; self.league = league; self.date = date; self.state = state
    }
    var phase: Int { state == "post" ? 2 : state == "in" ? 1 : 0 }
    static func parse(_ data: Data, league: SportsLeague) throws -> [Self] {
        let feed = try JSONDecoder().decode(MarkerFeed.self, from: data)
        return feed.events.compactMap { event in
            guard let id = event.id, !id.isEmpty else { return nil }
            let competition = event.competitions?.first
            return Self(id: id, league: league,
                date: (event.date ?? competition?.date).flatMap(SportsService.parseDate),
                state: (competition?.status ?? event.status)?.type?.state ?? "")
        }
    }
    static func days(_ values: [Self], now: Date, calendar: Calendar, first: Date, last: Date) -> [Date: Set<SportsLeague>] {
        var canonical: [String: Self] = [:]
        for value in values {
            if let prior = canonical[value.id], prior.phase > value.phase { continue }
            canonical[value.id] = value
        }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var result: [Date: Set<SportsLeague>] = [:]
        for value in canonical.values {
            guard let date = value.date else { continue }
            let day = value.state == "in" && date >= yesterday && date < today ? today : calendar.startOfDay(for: date)
            if day >= first && day <= last { result[day, default: []].insert(value.league) }
        }
        return result
    }
    private struct MarkerFeed: Decodable { let events: [Event] }
    private struct Event: Decodable {
        let id: String?; let date: String?; let status: Status?; let competitions: [Competition]?
    }
    private struct Competition: Decodable { let date: String?; let status: Status? }
    private struct Status: Decodable { let type: Kind?; struct Kind: Decodable { let state: String? } }
}
