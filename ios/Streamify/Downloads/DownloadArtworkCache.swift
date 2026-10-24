import Foundation
import ImageIO
import UIKit

enum DownloadArtworkCache {
    static let maximumBytes = 5 * 1024 * 1024

    static func fetch(_ url: URL) async throws -> Data {
        guard secureURL(url.absoluteString) != nil else { throw DownloadError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = http.url,
              secureURL(finalURL.absoluteString) != nil,
              (200...299).contains(http.statusCode),
              http.mimeType?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= Int64(maximumBytes) else { throw DownloadError.invalidResponse }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw DownloadError.invalidResponse }
            data.append(byte)
            if data.count.isMultiple(of: 65_536) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return try thumbnail(data: data, response: http)
    }

    static func thumbnail(data: Data, response: HTTPURLResponse) throws -> Data {
        guard (200...299).contains(response.statusCode),
              response.mimeType?.lowercased().hasPrefix("image/") == true,
              !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { throw DownloadError.invalidResponse }
        return jpeg
    }

    /// A thumbnail may only reference its own generated filename, never another download.
    static func fileURL(fileName: String, itemID: UUID, directory: URL) -> URL? {
        let prefix = "\(itemID.uuidString)-artwork-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".jpg"),
              !fileName.contains("/"), !fileName.contains("\\"),
              UUID(uuidString: String(fileName.dropFirst(prefix.count).dropLast(4))) != nil else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func remove(fileName: String, itemID: UUID, directory: URL) throws {
        guard let url = fileURL(fileName: fileName, itemID: itemID, directory: directory),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
