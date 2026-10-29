import SwiftUI
import UserNotifications
import FirebaseMessaging

enum SportsAlertTopic {
    static func topic(_ key: String) -> String? {
        let parts = key.split(separator: ":").map(String.init)
        guard parts.count == 2 else { return nil }
        let rawLeague = parts[0].lowercased()
        let league = rawLeague == "ncaaf" ? "college-football" : rawLeague
        guard SportsLeague(rawValue: league) != nil, !parts[1].isEmpty, parts[1].utf8.count <= 32,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return "streamify_live_\(league.replacingOccurrences(of: "-", with: "_"))_\(parts[1].lowercased())"
    }
}

@MainActor
final class SportsLiveAlerts: NSObject, ObservableObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let shared = SportsLiveAlerts()
    @Published var status: String?
    private var desired = Set<String>()
    private var applied = Set(UserDefaults.standard.stringArray(forKey: "streamify.ios.liveTopics") ?? [])
    private var syncing: Task<Void, Never>?
    private var currentTeams = Set<String>()
    private var enabled = false
    static var remotePushConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "StreamifyRemotePushEnabled") as? Bool == true }

    func bootstrap() {
        #if DEBUG
        if PreviewFixtures.enabled { return }
        #endif
        UNUserNotificationCenter.current().delegate = self
        guard Self.remotePushConfigured else { return }
        Messaging.messaging().delegate = self
        if !applied.isEmpty { UIApplication.shared.registerForRemoteNotifications() }
    }

    func authorize() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if granted && Self.remotePushConfigured { UIApplication.shared.registerForRemoteNotifications() }
            status = granted ? (Self.remotePushConfigured ? nil : "Alerts while Streamify is closed require Apple push signing. Live alerts can appear when the app checks scores.") : "Allow notifications for Streamify in Settings."
            return granted
        } catch { status = error.localizedDescription; return false }
    }

    func configure(teams: Set<String>, enabled: Bool) {
        #if DEBUG
        if PreviewFixtures.enabled { return }
        #endif
        currentTeams = teams; self.enabled = enabled
        desired = enabled ? Set(teams.compactMap(SportsAlertTopic.topic)) : []
        guard Self.remotePushConfigured else { return }
        Messaging.messaging().isAutoInitEnabled = enabled
        if enabled { UIApplication.shared.registerForRemoteNotifications() }
        if enabled && Messaging.messaging().apnsToken == nil { return }
        guard syncing == nil else { return }
        syncing = Task { [weak self] in
            guard let self else { return }
            defer { syncing = nil }
            do {
                while desired != applied {
                    if let topic = applied.subtracting(desired).first {
                        try await Messaging.messaging().unsubscribe(fromTopic: topic); applied.remove(topic)
                    } else if let topic = desired.subtracting(applied).first {
                        try await Messaging.messaging().subscribe(toTopic: topic); applied.insert(topic)
                    }
                    UserDefaults.standard.set(Array(applied), forKey: "streamify.ios.liveTopics")
                }
                status = nil
            } catch { status = "Live alerts could not sync. Streamify will retry when opened again." }
        }
    }

    func observe(_ games: [SportsGame], teams: Set<String>, enabled: Bool, profile: String) async {
        guard enabled, !Self.remotePushConfigured else { return }
        #if DEBUG
        if PreviewFixtures.enabled { return }
        #endif
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for game in games where game.isLive && [game.away.key(in: game.league), game.home.key(in: game.league)].contains(where: teams.contains) {
            guard let start = game.date, (0...15 * 60).contains(Date().timeIntervalSince(start)), let url = SportsWidgetPolicy.watchURL(for: game) else { continue }
            let key = "streamify.ios.liveAlert.\(profile).\(game.id)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(game.away.abbreviation) vs \(game.home.abbreviation) is live"
            content.body = "Your followed team is playing. Tap to watch."
            content.sound = .default
            content.userInfo = ["streamify_route": url.absoluteString]
            do {
                try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
                UserDefaults.standard.set(true, forKey: key)
            } catch { status = "The game alert could not be shown." }
        }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard fcmToken != nil else { return }
        Task { @MainActor in
            self.configure(teams: self.currentTeams, enabled: self.enabled)
        }
    }
    func setAPNSToken(_ token: Data) {
        guard Self.remotePushConfigured else { return }
        Messaging.messaging().apnsToken = token
        configure(teams: currentTeams, enabled: enabled)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["streamify_route"] as? String, let url = URL(string: value) else { return }
        await MainActor.run { AppQuickActionRouter.shared.enqueue(url: url) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
