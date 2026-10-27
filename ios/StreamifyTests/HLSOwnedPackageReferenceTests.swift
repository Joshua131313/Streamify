import Foundation
import XCTest
#if canImport(HLSResearchHost)
@testable import HLSResearchHost
#else
@testable import Streamify
#endif

/// Empty owned directories exercise public bookmark/path mechanics only.
/// These tests do not download, inspect or move any real HLS asset bundle.
final class HLSOwnedPackageReferenceTests: XCTestCase {
    func testDifferentAttemptsMayReferToTheSamePhysicalPackage() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try package(in: root)
        var first = try HLSOwnedPackageReference.nativeCallback(location: location, identity: identity())
        var second = try HLSOwnedPackageReference.nativeCallback(location: location, identity: identity())
        XCTAssertNotEqual(first.identity, second.identity)
        let firstURL = try first.resolve(expectedIdentity: first.identity)
        let secondURL = try second.resolve(expectedIdentity: second.identity)
        XCTAssertTrue(try HLSOwnedPackageReference.locationsReferToSamePackage(firstURL, secondURL),
            "An attempt ID is not evidence that a retained download occupies a different directory.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
    }

    func testPhysicalIdentityHandlesDirectoryURLHintsAndDistinguishesDifferentPackages() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try package(in: root)
        let same = URL(fileURLWithPath: first.path, isDirectory: false)
        let other = try package(in: root, name: "other.movpkg")
        XCTAssertTrue(try HLSOwnedPackageReference.locationsReferToSamePackage(first, same))
        XCTAssertFalse(try HLSOwnedPackageReference.locationsReferToSamePackage(first, other))
    }

    func testNativeNoFollowDestinationKeepsTheOriginalURLWithoutHostFilesystemIO() throws {
        let path = "/.nofollow/Users/runner/Library/Developer/CoreSimulator/Devices/opaque-device/data/Containers/Data/Application/opaque-app/Library/managed-assets/episode.movpkg"
        let callback = URL(fileURLWithPath: path, isDirectory: true)
        let owner = identity()
        let reference = try HLSOwnedPackageReference.nativeCallback(location: callback, identity: owner)
        XCTAssertEqual(reference.provisionalCallbackURL.absoluteString, callback.absoluteString)
        XCTAssertEqual(reference.provisionalCallbackURL.path, callback.path)
        XCTAssertTrue(reference.provisionalCallbackURL.path.hasPrefix("/.nofollow/"))
        XCTAssertTrue(reference.provisionalCallbackURL.hasDirectoryPath)
        XCTAssertFalse(reference.isDurable)

        var restored = try roundTrip(reference)
        XCTAssertEqual(restored.provisionalCallbackURL.absoluteString, callback.absoluteString)
        // The decoded record must fail at its provenance guard, before this
        // synthetic host-root path can reach any filesystem lookup or deletion.
        XCTAssertThrowsError(try restored.resolve(expectedIdentity: owner)) {
            XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .nativeReassociationRequired)
        }
        XCTAssertThrowsError(try restored.remove(expectedIdentity: owner)) {
            XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .nativeReassociationRequired)
        }
    }

    func testEarlyMissingNativeDestinationCanBeCapturedButNotMadeDurable() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("pending.movpkg", isDirectory: true)
        let owner = identity()
        var reference = try HLSOwnedPackageReference.nativeCallback(location: location, identity: owner)
        XCTAssertFalse(reference.isDurable)
        XCTAssertEqual(reference.provisionalCallbackURL, location)
        XCTAssertThrowsError(try reference.makeDurable(expectedIdentity: owner)) {
            XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .missingPackage)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path), "Capturing a callback must not create a package directory.")
    }

    func testDecodedProvisionalPathCannotResolveBookmarkOrDeleteWithoutNativeReassociation() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try package(in: root)
        let owner = identity()
        var restored = try roundTrip(HLSOwnedPackageReference.nativeCallback(location: location, identity: owner))
        for operation in 0..<3 {
            XCTAssertThrowsError(try {
                switch operation {
                case 0: _ = try restored.resolve(expectedIdentity: owner)
                case 1: try restored.makeDurable(expectedIdentity: owner)
                default: try restored.remove(expectedIdentity: owner)
                }
            }()) {
                XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .nativeReassociationRequired)
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
        try restored.reassociateNativeCallback(location: location, identity: owner)
        try restored.makeDurable(expectedIdentity: owner)
        XCTAssertTrue(restored.isDurable)
        XCTAssertEqual(try restored.resolve(expectedIdentity: owner).path, location.path)
    }

    func testExactOwnershipIsCheckedBeforeFilesystemAccessOrReassociation() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try package(in: root)
        let owner = identity()
        var reference = try HLSOwnedPackageReference.nativeCallback(location: location, identity: owner)
        for foreign in [
            HLSDownloadIdentity(id: UUID(), attempt: owner.attempt, taskIdentifier: owner.taskIdentifier),
            HLSDownloadIdentity(id: owner.id, attempt: UUID(), taskIdentifier: owner.taskIdentifier),
            HLSDownloadIdentity(id: owner.id, attempt: owner.attempt, taskIdentifier: owner.taskIdentifier + 1)
        ] {
            XCTAssertThrowsError(try reference.reassociateNativeCallback(location: location, identity: foreign)) {
                XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .identityMismatch)
            }
            XCTAssertThrowsError(try reference.resolve(expectedIdentity: foreign)) {
                XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .identityMismatch)
            }
            XCTAssertThrowsError(try reference.remove(expectedIdentity: foreign)) {
                XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .identityMismatch)
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
    }

    func testDurableBookmarkRoundTripPreservesDirectoryURLAndDeletesOnlyItsOwnedPackage() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try package(in: root)
        let untouched = try package(in: root, name: "untouched.movpkg")
        let owner = identity()
        var reference = try HLSOwnedPackageReference.nativeCallback(location: location, identity: owner)
        try reference.makeDurable(expectedIdentity: owner)
        var restored = try roundTrip(reference)
        XCTAssertTrue(restored.isDurable)
        XCTAssertEqual(restored.identity, owner)
        XCTAssertEqual(try restored.resolve(expectedIdentity: owner).standardizedFileURL.path, location.standardizedFileURL.path)
        try restored.remove(expectedIdentity: owner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untouched.path))
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        XCTAssertThrowsError(try restored.remove(expectedIdentity: owner)) {
            XCTAssertEqual($0 as? HLSOwnedPackageReferenceError, .nativeReassociationRequired)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path), "A consumed reference must not delete a different later directory at the same path.")
    }

    func testBookmarkTracksRenamedSyntheticContainerAndRefreshesWhenFoundationMarksItStale() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("old-container", isDirectory: true)
        let relocated = root.appendingPathComponent("new-container", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let location = try package(in: original)
        let owner = identity()
        var reference = try HLSOwnedPackageReference.nativeCallback(location: location, identity: owner)
        try reference.makeDurable(expectedIdentity: owner)
        var restored = try roundTrip(reference)
        let previous = try XCTUnwrap(restored.bookmarkData)
        // Only the empty test fixture's parent is renamed. Real downloaded
        // assets are always left at Apple's system-provided location.
        try FileManager.default.moveItem(at: original, to: relocated)
        var wasStale = false
        _ = try URL(resolvingBookmarkData: previous, options: [.withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &wasStale)
        let resolved = try restored.resolve(expectedIdentity: owner)
        XCTAssertEqual(resolved.standardizedFileURL.path, relocated.appendingPathComponent(location.lastPathComponent).standardizedFileURL.path)
        if wasStale { XCTAssertNotEqual(restored.bookmarkData, previous, "A stale but resolved reference must be renewed before persistence.") }
        XCTAssertEqual(try roundTrip(restored).isDurable, true)
    }

    func testCorruptDurableBookmarkNeverFallsBackToTheSavedCallbackPath() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try package(in: root)
        let owner = identity()
        let provisional = try HLSOwnedPackageReference.nativeCallback(location: location, identity: owner)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(provisional)) as? [String: Any])
        object["bookmarkData"] = Data("invalid bookmark".utf8).base64EncodedString()
        var restored = try JSONDecoder().decode(HLSOwnedPackageReference.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try restored.resolve(expectedIdentity: owner))
        XCTAssertThrowsError(try restored.remove(expectedIdentity: owner))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
    }

    func testNativeFactoryRejectsWebRemoteAndNonPackageLocations() throws {
        let owner = identity()
        for address in ["https://source.example.test/episode.movpkg", "file://remote.example.test/tmp/episode.movpkg",
                        "file:///", "file:///tmp/episode.mp4", "file:///tmp/episode.movpkg?query=1",
                        "file:///tmp/episode.movpkg#fragment", "file:///tmp/episode.movpkg/child"] {
            let location = try XCTUnwrap(URL(string: address))
            XCTAssertThrowsError(try HLSOwnedPackageReference.nativeCallback(location: location, identity: owner), address)
        }
    }

    private func identity() -> HLSDownloadIdentity { HLSDownloadIdentity(id: UUID(), attempt: UUID(), taskIdentifier: 42) }
    private func fixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HLSOwnedReference-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func package(in root: URL, name: String = "episode.movpkg") throws -> URL {
        let location = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        return location
    }
    private func roundTrip(_ reference: HLSOwnedPackageReference) throws -> HLSOwnedPackageReference {
        try JSONDecoder().decode(HLSOwnedPackageReference.self, from: JSONEncoder().encode(reference))
    }
}
