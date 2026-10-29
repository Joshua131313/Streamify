import Foundation
import SwiftUI
import UIKit

private enum SideStoreLinks {
    static let source = link(action: "source", address: URL(string: "https://raw.githubusercontent.com/Joshua131313/Streamify/refs/heads/codex/native-ios/ios/sideload-source.json")!)
    static func link(action: String, address: URL) -> URL {
        var components = URLComponents()
        components.scheme = "sidestore"
        components.host = action
        components.queryItems = [URLQueryItem(name: "url", value: address.absoluteString)]
        return components.url!
    }
}

struct AppUpdate: Equatable {
    let version: String
    let downloadURL: URL
    let releaseURL: URL
    let size: Int64
    let notes: String
}

enum AppUpdateCheck: Equatable {
    case noRelease
    case upToDate
    case available(AppUpdate)
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case limited
    case unavailable
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The update information could not be read. Please try again later."
        case .limited: return "Update checks are temporarily limited. Please try again later."
        case .unavailable: return "Cannot check for updates right now. Please try again."
        case .offline: return "Connect to the internet, then check for updates again."
        }
    }
}

/// Stable release versions use numeric components; 1.10.0 is newer than 1.9.0.
/// Build metadata does not affect precedence. Prerelease tags are not offered.
struct AppUpdateVersion: Comparable {
    private let components: [UInt64]

    init?(_ value: String) {
        let pieces = value.split(separator: "+", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), value.utf8.count <= 80 else { return nil }
        if pieces.count == 2 {
            let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard identifiers.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy(Self.identifierByte) }) else { return nil }
        }
        let numbers = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(numbers.count) else { return nil }
        var values: [UInt64] = []
        for number in numbers {
            guard !number.isEmpty, number.utf8.allSatisfy({ (48...57).contains($0) }),
                  number.count == 1 || number.first != "0", let value = UInt64(number) else { return nil }
            values.append(value)
        }
        components = values + Array(repeating: 0, count: 3 - values.count)
    }

    private static func identifierByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

/// Reads public release metadata only. The signer/store handles IPA installation.
struct AppUpdateClient {
    static let endpoint = URL(string: "https://api.github.com/repos/Joshua131313/Streamify/releases?per_page=30")!
    static let maximumResponseBytes = 1024 * 1024
    static let maximumIPABytes: Int64 = 512 * 1024 * 1024
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func latest(currentVersion: String) async throws -> AppUpdate? {
        if case .available(let update) = try await check(currentVersion: currentVersion) { return update }
        return nil
    }

    func check(currentVersion: String) async throws -> AppUpdateCheck {
        try Task.checkCancellation()
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Streamify-iOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: AppUpdateRedirectPolicy())
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.url == Self.endpoint else { throw AppUpdateError.invalidResponse }
            if http.statusCode == 403 || http.statusCode == 429 { throw AppUpdateError.limited }
            guard http.statusCode == 200 else { throw AppUpdateError.unavailable }
            guard response.expectedContentLength <= Int64(Self.maximumResponseBytes) else { throw AppUpdateError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumResponseBytes else { throw AppUpdateError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try Self.evaluate(data: data, currentVersion: currentVersion)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let error = error as? AppUpdateError { throw error }
            if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
                throw AppUpdateError.offline
            }
            throw AppUpdateError.unavailable
        }
    }

    static func evaluate(data: Data, currentVersion: String) throws -> AppUpdateCheck {
        guard data.count <= maximumResponseBytes, let installed = AppUpdateVersion(currentVersion),
              let releases = try? JSONDecoder().decode([Release].self, from: data), releases.count <= 30 else {
            throw AppUpdateError.invalidResponse
        }
        let ordered = releases.compactMap { release -> (Release, String, AppUpdateVersion)? in
            guard !release.draft, !release.prerelease, release.tag.hasPrefix("ios-v") else { return nil }
            let version = String(release.tag.dropFirst(5))
            guard let parsed = AppUpdateVersion(version) else { return nil }
            return (release, version, parsed)
        }.sorted { $0.2 > $1.2 }
        guard let (release, version, parsed) = ordered.first else { return .noRelease }
        guard parsed > installed else { return .upToDate }
        guard let releaseURL = trustedReleaseURL(release.page, tag: release.tag),
              let asset = release.assets.first(where: { asset in
                  asset.size > 0 && asset.size <= maximumIPABytes && trustedAssetURL(asset.address, name: asset.name, tag: release.tag) != nil
              }), let url = trustedAssetURL(asset.address, name: asset.name, tag: release.tag) else {
            throw AppUpdateError.invalidResponse
        }
        let notes = String((release.notes ?? "").filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) || $0 == "\n" || $0 == "\t" }.prefix(2000))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .available(AppUpdate(version: version, downloadURL: url, releaseURL: releaseURL, size: asset.size, notes: notes))
    }

    static func trustedAssetURL(_ value: String, name: String, tag: String) -> URL? {
        guard name.utf8.count <= 120, name.lowercased().hasSuffix(".ipa"), !name.contains(".."),
              name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
              let components = trustedComponents(value),
              components.path.lowercased().hasPrefix("/joshua131313/streamify/releases/download/"),
              Array(components.path.split(separator: "/").suffix(2)).map(String.init) == [tag, name],
              components.path.split(separator: "/").count == 6 else { return nil }
        return components.url
    }

    private static func trustedReleaseURL(_ value: String, tag: String) -> URL? {
        guard let components = trustedComponents(value),
              components.path.lowercased().hasPrefix("/joshua131313/streamify/releases/tag/"),
              components.path.split(separator: "/").count == 5,
              components.path.split(separator: "/").last == Substring(tag) else { return nil }
        return components.url
    }

    private static func trustedComponents(_ value: String) -> URLComponents? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com", components.user == nil, components.password == nil,
              components.port == nil, components.query == nil, components.fragment == nil,
              components.percentEncodedPath == components.path else { return nil }
        return components
    }

    private struct Release: Decodable {
        let tag: String
        let draft: Bool
        let prerelease: Bool
        let page: String
        let notes: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tag = "tag_name", draft, prerelease, page = "html_url", notes = "body", assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let size: Int64
        let address: String
        enum CodingKeys: String, CodingKey { case name, size, address = "browser_download_url" }
    }
}

private final class AppUpdateRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
struct AppUpdatesView: View {
    @State private var phase = Phase.idle
    @State private var checkTask: Task<Void, Never>?
    @State private var sideStoreAvailable = false
    @Environment(\.scenePhase) private var scenePhase
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    private enum Phase {
        case idle, checking, checked(AppUpdateCheck), failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "App updates", subtitle: "Installed \(currentVersion)")
                    Text(status).font(.subheadline).foregroundStyle(AppTheme.muted)
                        .accessibilityIdentifier("ios-update-status")
                    if case .checking = phase { ProgressView().tint(AppTheme.accent) }
                    if case .checked(.available(let update)) = phase {
                        if !update.notes.isEmpty { Text(verbatim: update.notes).font(.footnote).textSelection(.enabled) }
                        Text(ByteCountFormatter.string(fromByteCount: update.size, countStyle: .file)).font(.caption).foregroundStyle(AppTheme.muted)
                        if sideStoreAvailable {
                            Link(destination: SideStoreLinks.link(action: "install", address: update.downloadURL)) {
                                Label("Install with SideStore", systemImage: "arrow.down.app")
                            }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("install-ios-update")
                        }
                        Link(destination: update.downloadURL) { Label("Download IPA", systemImage: "arrow.down.circle") }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("download-ios-update")
                        ShareLink(item: update.downloadURL) { Label("Share IPA link", systemImage: "square.and.arrow.up") }
                            .buttonStyle(SecondaryButtonStyle())
                        Link("Release details", destination: update.releaseURL).font(.subheadline)
                    }
                    Button(action: check) { Label(isFailure ? "Retry" : "Check for updates", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(SecondaryButtonStyle()).disabled(isChecking).accessibilityIdentifier("check-ios-updates")
                }
                .padding(20).background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.border, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Installing an update", systemImage: AdaptiveLayout.deviceSymbol).font(.headline)
                    Text("Install the IPA with SideStore on iPhone or iPad, or iLoader on your computer. Keep the existing app installed.")
                    Text("SideStore needs one initial computer setup. A free Apple Account needs its apps refreshed within seven days.")
                        .foregroundStyle(AppTheme.muted)
                    if sideStoreAvailable {
                        Link(destination: SideStoreLinks.source) { Label("Add Streamify to SideStore", systemImage: "plus.app") }
                            .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("add-sidestore-source")
                        Text("Add the source once to see future Streamify releases in SideStore’s update list.").foregroundStyle(AppTheme.muted)
                    }
                    Link("SideStore setup guide", destination: URL(string: "https://docs.sidestore.io/docs/installation/prerequisites")!)
                }.font(.subheadline).padding(20).streamifyControlSurface(cornerRadius: 16)
            }.padding(20).streamifyReadableWidth()
        }
        .background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
        .navigationTitle("App updates").navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSideStoreAvailability() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshSideStoreAvailability() } }
        .onDisappear {
            checkTask?.cancel(); checkTask = nil
            if isChecking { phase = .idle }
        }
    }

    private func refreshSideStoreAvailability() {
        sideStoreAvailable = UIApplication.shared.canOpenURL(SideStoreLinks.source)
    }

    private var isChecking: Bool { if case .checking = phase { return true }; return false }
    private var isFailure: Bool { if case .failed = phase { return true }; return false }
    private var status: String {
        switch phase {
        case .idle: return "Check for the latest iOS release."
        case .checking: return "Checking GitHub releases…"
        case .checked(.noRelease): return "No iOS updates have been published yet."
        case .checked(.upToDate): return "You’re up to date."
        case .checked(.available(let update)): return "Version \(update.version) is available."
        case .failed(let message): return message
        }
    }

    private func check() {
        guard !isChecking else { return }
        phase = .checking
        checkTask = Task {
            do {
                let result = try await AppUpdateClient().check(currentVersion: currentVersion)
                try Task.checkCancellation()
                phase = .checked(result)
            } catch is CancellationError {
                if isChecking { phase = .idle }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
