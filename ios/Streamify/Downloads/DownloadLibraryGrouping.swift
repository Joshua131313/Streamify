import Foundation

/// The toolbar summarizes each active transfer equally, including native HLS
/// transfers whose progress is reported as downloaded media time, not bytes.
enum DownloadToolbarProgress {
    static func average(in items: [DownloadItem]) -> Double? {
        let active = items.filter { $0.status == .downloading }
        guard !active.isEmpty else { return nil }
        let fractions = active.compactMap(\.progress)
        guard fractions.count == active.count else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }
}

/// A presentation of the existing records, never a second download catalog.
/// File UUIDs, transfer state and artwork remain owned by DownloadStore.
struct DownloadSeriesGroup: Identifiable {
    let id: Int
    let title: String
    let episodes: [DownloadItem]

    var readyCount: Int { episodes.filter { $0.status == .completed }.count }
    var active: [DownloadItem] { episodes.filter { $0.status == .downloading } }
    var retryable: [DownloadItem] {
        episodes.filter { $0.source != nil && ($0.status == .failed || $0.status == .cancelled) }
    }
    var seasons: [Int] { Array(Set(episodes.map { max(1, $0.catalog?.season ?? 1) })).sorted() }
    var bytesWritten: Int64 {
        episodes.reduce(0) { total, item in
            let sum = total.addingReportingOverflow(max(0, item.bytesWritten))
            return sum.overflow ? Int64.max : sum.partialValue
        }
    }
    /// Only actual active byte totals contribute to the transfer ring. One
    /// unknown total keeps it indeterminate, as on the main Downloads button.
    var progress: Double? {
        let transfers = active
        if transfers.count == 1 { return transfers.first?.progress }
        guard !transfers.isEmpty, transfers.allSatisfy({ $0.expectedBytes > 0 }) else { return nil }
        let total = transfers.reduce(0.0) { $0 + Double($1.expectedBytes) }
        let written = transfers.reduce(0.0) { $0 + Double(min(max(0, $1.bytesWritten), $1.expectedBytes)) }
        guard total.isFinite, written.isFinite, total > 0 else { return nil }
        return min(1, max(0, written / total))
    }
}

enum DownloadLibraryEntry: Identifiable {
    case video(DownloadItem)
    case series(DownloadSeriesGroup)

    var id: String {
        switch self {
        case .video(let item): return "video:\(item.id.uuidString)"
        case .series(let group): return "tv:\(group.id)"
        }
    }
    var title: String {
        switch self {
        case .video(let item): return item.catalog?.title ?? item.title
        case .series(let group): return group.title
        }
    }
}

enum DownloadLibraryGrouping {
    static func entries(in items: [DownloadItem]) -> [DownloadLibraryEntry] {
        var shows: [Int: [DownloadItem]] = [:]
        var entries: [DownloadLibraryEntry] = []
        for item in items {
            if let catalog = item.catalog, catalog.kind == MediaKind.tv.rawValue, catalog.id > 0 {
                shows[catalog.id, default: []].append(item)
            } else {
                // Imported files and older records without a catalog identity
                // remain playable files; a title never guesses their show.
                entries.append(.video(item))
            }
        }
        entries += shows.map { .series(makeSeries(id: $0.key, items: $0.value)) }
        return entries.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    static func series(id: Int, in items: [DownloadItem]) -> DownloadSeriesGroup? {
        let episodes = items.filter { $0.catalog?.kind == MediaKind.tv.rawValue && $0.catalog?.id == id && id > 0 }
        return episodes.isEmpty ? nil : makeSeries(id: id, items: episodes)
    }

    private static func makeSeries(id: Int, items: [DownloadItem]) -> DownloadSeriesGroup {
        let title = items.compactMap { $0.catalog?.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? items.first?.title ?? "Downloaded show"
        let episodes = items.sorted {
            let lhs = $0.catalog!, rhs = $1.catalog!
            if lhs.season != rhs.season { return lhs.season < rhs.season }
            if lhs.episode != rhs.episode { return lhs.episode < rhs.episode }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        return DownloadSeriesGroup(id: id, title: title, episodes: episodes)
    }
}
