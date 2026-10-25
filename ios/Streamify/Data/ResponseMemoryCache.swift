import Foundation

/// Session-only public catalog data. Requests with different credentials or URL
/// sessions never share entries; nothing (including search terms) goes to disk.
actor ResponseMemoryCache {
    static let shared = ResponseMemoryCache()
    private static let sessions = ResponseSessionIdentities()
    private struct Entry {
        let data: Data
        let expires: Date
        var touched: Date
    }
    private struct Flight {
        let id: UUID
        let task: Task<Data, Error>
    }
    private var entries: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private let entryLimit: Int
    private let byteLimit: Int
    private let now: @Sendable () -> Date

    init(entryLimit: Int = 192, byteLimit: Int = 16 * 1024 * 1024,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.entryLimit = max(1, entryLimit)
        self.byteLimit = max(1, byteLimit)
        self.now = now
    }

    static func key(for request: URLRequest, session: URLSession) -> String {
        [sessions.identity(for: session), request.httpMethod ?? "GET",
         request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Authorization") ?? "",
         request.httpBody?.base64EncodedString() ?? ""].joined(separator: "\n")
    }

    func data(key: String, lifetime: TimeInterval, reload: Bool = false,
              operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        let date = now()
        if !reload, var entry = entries[key], entry.expires > date {
            entry.touched = date
            entries[key] = entry
            return entry.data
        }
        // A refresh joins an already running request. Cancelling one view must
        // not cancel work another tab/search consumer is awaiting.
        let flight: Flight
        if let existing = flights[key] { flight = existing }
        else {
            flight = Flight(id: UUID(), task: Task { try await operation() })
            flights[key] = flight
        }
        do {
            let data = try await flight.task.value
            if flights[key]?.id == flight.id {
                flights[key] = nil
                if data.count <= byteLimit {
                    let completed = now()
                    entries[key] = Entry(data: data, expires: completed.addingTimeInterval(max(0, lifetime)), touched: completed)
                    trim()
                }
            }
            try Task.checkCancellation()
            return data
        } catch {
            if flights[key]?.id == flight.id { flights[key] = nil }
            throw error
        }
    }

    private func trim() {
        var bytes = entries.values.reduce(0) { $0 + $1.data.count }
        for key in entries.sorted(by: { $0.value.touched < $1.value.touched }).map(\.key) {
            guard entries.count > entryLimit || bytes > byteLimit else { break }
            if let removed = entries.removeValue(forKey: key) { bytes -= removed.data.count }
        }
    }
}

/// A recycled object address must never make two independent URLSessions share
/// fixtures, credentials, or responses. Weak references keep this registry small.
private final class ResponseSessionIdentities: @unchecked Sendable {
    private final class Entry {
        weak var session: URLSession?
        let identity = UUID().uuidString
        init(_ session: URLSession) { self.session = session }
    }
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]
    func identity(for session: URLSession) -> String {
        lock.lock(); defer { lock.unlock() }
        entries = entries.filter { $0.value.session != nil }
        let key = ObjectIdentifier(session)
        if let entry = entries[key], entry.session === session { return entry.identity }
        let entry = Entry(session); entries[key] = entry
        return entry.identity
    }
}
