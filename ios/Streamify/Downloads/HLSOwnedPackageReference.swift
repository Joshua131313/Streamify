import Foundation

enum HLSOwnedPackageReferenceError: Error, LocalizedError, Equatable {
    case invalidLocation, identityMismatch, nativeReassociationRequired, missingPackage, invalidBookmark

    var errorDescription: String? {
        switch self {
        case .invalidLocation: return "The native download did not provide a valid package location."
        case .identityMismatch: return "This package belongs to a different native download attempt."
        case .nativeReassociationRequired: return "Reconnect the native download before using its provisional location."
        case .missingPackage: return "The downloaded video package is no longer available."
        case .invalidBookmark: return "The saved video package reference could not be restored."
        }
    }
}

/// An identity-bound persistent reference for a system-managed HLS destination.
///
/// Trust boundary: `nativeCallback` and `reassociateNativeCallback` are ONLY for
/// an AVAssetDownloadDelegate destination whose exact task/attempt identity was
/// checked by its native session owner. Never pass a source, webpage, imported
/// path, or an external URL read from metadata to either method.
///
/// A reference does not certify completion, quality, audio or offline playback.
/// The caller must still require native success and AVFoundation validation.
struct HLSOwnedPackageReference: Codable, Sendable {
    let identity: HLSDownloadIdentity
    private(set) var provisionalCallbackURL: URL
    private(set) var bookmarkData: Data?
    private var confirmedInCurrentProcess: Bool

    var isDurable: Bool { bookmarkData != nil }

    private init(location: URL, identity: HLSDownloadIdentity) {
        self.identity = identity
        provisionalCallbackURL = location
        bookmarkData = nil
        confirmedInCurrentProcess = true
    }

    /// The destination may not exist at willDownloadTo time. Capture provenance
    /// without touching or creating the package or requiring a bookmark yet.
    static func nativeCallback(location: URL, identity: HLSDownloadIdentity) throws -> Self {
        guard identity.taskIdentifier > 0 else { throw HLSOwnedPackageReferenceError.identityMismatch }
        return Self(location: try validatedLocation(location), identity: identity)
    }

    /// Decoding intentionally loses provisional authority. Only a NEW actual
    /// callback for this same native identity may restore it. A changed native
    /// destination discards old durability and requires validation/bookmarking
    /// again; an arbitrary saved path cannot perform this reassociation.
    mutating func reassociateNativeCallback(location: URL, identity expected: HLSDownloadIdentity) throws {
        try requireIdentity(expected)
        let nativeLocation = try Self.validatedLocation(location)
        if bookmarkData != nil,
           nativeLocation.standardizedFileURL.resolvingSymlinksInPath().path !=
            provisionalCallbackURL.standardizedFileURL.resolvingSymlinksInPath().path {
            bookmarkData = nil
        }
        provisionalCallbackURL = nativeLocation
        confirmedInCurrentProcess = true
    }

    /// Call after native completion/validation, while the real directory exists.
    /// Default bookmarks preserve more relocation information than minimal ones.
    mutating func makeDurable(expectedIdentity expected: HLSDownloadIdentity) throws {
        try requireIdentity(expected)
        guard confirmedInCurrentProcess else { throw HLSOwnedPackageReferenceError.nativeReassociationRequired }
        let location = try Self.existingDirectory(provisionalCallbackURL)
        let data = try Self.bookmark(for: location)
        bookmarkData = data
    }

    /// A durable record may resolve after relaunch. A decoded provisional record
    /// may not use its persisted external URL until a real callback reassociates
    /// it. There is deliberately no fallback from a failed bookmark to that URL.
    mutating func resolve(expectedIdentity expected: HLSDownloadIdentity) throws -> URL {
        try requireIdentity(expected)
        guard let bookmarkData else {
            guard confirmedInCurrentProcess else { throw HLSOwnedPackageReferenceError.nativeReassociationRequired }
            return try Self.existingDirectory(provisionalCallbackURL)
        }
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        let location = try Self.existingDirectory(resolved)
        if stale { self.bookmarkData = try Self.bookmark(for: location) }
        provisionalCallbackURL = location
        return location
    }

    /// Remove the entire owned bundle, never its internal files. No package is
    /// moved. Foreign identities are rejected before any filesystem access.
    mutating func remove(expectedIdentity expected: HLSDownloadIdentity) throws {
        let location = try resolve(expectedIdentity: expected)
        try FileManager.default.removeItem(at: location)
        bookmarkData = nil
        confirmedInCurrentProcess = false
    }

    /// Call only with already-owned package URLs. File identity also handles
    /// different valid URL representations of the same system directory.
    /// A failure is unknown identity, never permission to delete either item.
    static func locationsReferToSamePackage(_ first: URL, _ second: URL) throws -> Bool {
        _ = try validatedLocation(first); _ = try validatedLocation(second)
        if first.absoluteURL == second.absoluteURL { return true }
        let left = try FileManager.default.attributesOfItem(atPath: first.path)
        let right = try FileManager.default.attributesOfItem(atPath: second.path)
        guard let leftDevice = left[.systemNumber] as? NSNumber,
              let rightDevice = right[.systemNumber] as? NSNumber,
              let leftFile = left[.systemFileNumber] as? NSNumber,
              let rightFile = right[.systemFileNumber] as? NSNumber else {
            throw HLSOwnedPackageReferenceError.invalidLocation
        }
        return leftDevice == rightDevice && leftFile == rightFile
    }

    private func requireIdentity(_ expected: HLSDownloadIdentity) throws {
        guard identity == expected else { throw HLSOwnedPackageReferenceError.identityMismatch }
    }

    private static func validatedLocation(_ location: URL) throws -> URL {
        guard location.isFileURL, location.user == nil, location.password == nil,
              location.host == nil || location.host == "" || location.host == "localhost",
              location.query == nil, location.fragment == nil,
              !location.path.unicodeScalars.contains(where: { $0.value == 0 }),
              !location.pathComponents.contains(".."),
              location.pathExtension.lowercased() == "movpkg",
              location.standardizedFileURL.path != "/" else {
            throw HLSOwnedPackageReferenceError.invalidLocation
        }
        // Preserve the actual URL object supplied by the system, including any
        // normal access context. A reconstructed path is not an access grant.
        return location
    }

    private static func existingDirectory(_ location: URL) throws -> URL {
        _ = try validatedLocation(location)
        guard let values = try? location.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              FileManager.default.isReadableFile(atPath: location.path) else {
            throw HLSOwnedPackageReferenceError.missingPackage
        }
        return location
    }

    private static func bookmark(for location: URL) throws -> Data {
        let data = try location.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard !data.isEmpty, data.count <= 64 * 1024 else { throw HLSOwnedPackageReferenceError.invalidBookmark }
        return data
    }

    private enum CodingKeys: String, CodingKey { case identity, provisionalCallbackURL, bookmarkData }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identity = try values.decode(HLSDownloadIdentity.self, forKey: .identity)
        guard identity.taskIdentifier > 0 else { throw HLSOwnedPackageReferenceError.identityMismatch }
        provisionalCallbackURL = try Self.validatedLocation(values.decode(URL.self, forKey: .provisionalCallbackURL))
        bookmarkData = try values.decodeIfPresent(Data.self, forKey: .bookmarkData)
        if let bookmarkData, bookmarkData.isEmpty || bookmarkData.count > 64 * 1024 {
            throw HLSOwnedPackageReferenceError.invalidBookmark
        }
        confirmedInCurrentProcess = false
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(identity, forKey: .identity)
        try values.encode(provisionalCallbackURL, forKey: .provisionalCallbackURL)
        try values.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
    }
}
