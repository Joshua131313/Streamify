import Foundation
import Combine
import UIKit

enum AppQuickAction: String, CaseIterable, Sendable {
    case downloads = "com.streamify.app.downloads"
    case favorites = "com.streamify.app.favorites"
    case sports = "com.streamify.app.sports"

    var destination: AppQuickActionDestination {
        switch self {
        case .downloads: return .downloads
        case .favorites: return .favorites
        case .sports: return .sports
        }
    }
}

enum AppQuickActionDestination: Equatable, Sendable {
    case downloads, favorites, sports
    case watchSports(league: SportsLeague, eventID: String)

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "streamify", parts.host?.lowercased() == "sports",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { return nil }
        let query = parts.queryItems ?? []
        if parts.path.isEmpty || parts.path == "/" {
            guard query.isEmpty else { return nil }
            self = .sports
            return
        }
        guard parts.path == "/watch", query.count == 2,
              query.filter({ $0.name == "league" }).count == 1, query.filter({ $0.name == "event" }).count == 1,
              let leagueText = query.first(where: { $0.name == "league" })?.value,
              let league = SportsLeague(rawValue: leagueText),
              let event = query.first(where: { $0.name == "event" })?.value,
              Self.validEventID(event) else { return nil }
        self = .watchSports(league: league, eventID: event)
    }

    static func validEventID(_ value: String) -> Bool {
        SportsService.validEventID(value)
    }
}

/// Holds an incoming OS action until the SwiftUI scene becomes active. Taking a
/// request consumes it before navigation, so foregrounding cannot replay it.
@MainActor
final class AppQuickActionRouter: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id: UUID
        let destination: AppQuickActionDestination
    }
    static let shared = AppQuickActionRouter()
    @Published private(set) var pending: Request?

    @discardableResult func enqueue(shortcutType: String) -> Bool {
        guard let shortcut = AppQuickAction(rawValue: shortcutType) else { return false }
        enqueue(shortcut.destination)
        return true
    }
    @discardableResult func enqueue(url: URL) -> Bool {
        guard let destination = AppQuickActionDestination(url: url) else { return false }
        enqueue(destination)
        return true
    }
    func enqueue(_ destination: AppQuickActionDestination) {
        pending = Request(id: UUID(), destination: destination)
    }
    func takePending() -> Request? {
        let request = pending
        pending = nil
        return request
    }
}

/// Apple documents this delegate configuration for SwiftUI App lifecycle. It
/// receives shortcut events without creating or replacing SwiftUI's window.
@MainActor
final class AppQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcut = connectionOptions.shortcutItem {
            AppQuickActionRouter.shared.enqueue(shortcutType: shortcut.type)
        }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void) {
        completionHandler(AppQuickActionRouter.shared.enqueue(shortcutType: shortcutItem.type))
    }
}
