import AppKit
import Foundation

/// Stores optional custom book covers outside SwiftData so existing libraries
/// remain compatible when the cover feature is introduced.
@MainActor
enum BookCoverStore {
    private static let directoryName = "DreaMoon/Covers"
    private static let imageCache = NSCache<NSUUID, NSImage>()
    private static var missingCoverIDs = Set<UUID>()

    static func image(for book: Book) -> NSImage? {
        let key = book.id as NSUUID
        if let cached = imageCache.object(forKey: key) { return cached }
        guard !missingCoverIDs.contains(book.id),
              let image = NSImage(contentsOf: url(for: book)) else {
            missingCoverIDs.insert(book.id)
            return nil
        }
        imageCache.setObject(image, forKey: key)
        return image
    }

    static func hasCover(for book: Book) -> Bool {
        hasCover(forID: book.id)
    }

    static func hasCover(forID bookID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(forID: bookID).path)
    }

    static func save(image: NSImage, for book: Book) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CoverStoreError.invalidImage
        }

        let directory = try coversDirectory()
        try pngData.write(to: directory.appendingPathComponent("\(book.id.uuidString).png"), options: .atomic)
        imageCache.setObject(image, forKey: book.id as NSUUID)
        missingCoverIDs.remove(book.id)
    }

    static func removeCover(for book: Book) throws {
        try removeCover(forID: book.id)
    }

    static func removeCover(forID bookID: UUID) throws {
        let coverURL = url(forID: bookID)
        imageCache.removeObject(forKey: bookID as NSUUID)
        missingCoverIDs.insert(bookID)
        guard FileManager.default.fileExists(atPath: coverURL.path) else { return }
        try FileManager.default.removeItem(at: coverURL)
    }

    private static func url(for book: Book) -> URL {
        url(forID: book.id)
    }

    private static func url(forID bookID: UUID) -> URL {
        let directory = coversDirectoryURL()
        return directory.appendingPathComponent("\(bookID.uuidString).png")
    }

    private static func coversDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func coversDirectory() throws -> URL {
        let directory = coversDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private enum CoverStoreError: LocalizedError {
        case invalidImage

        var errorDescription: String? { "無法讀取這張封面圖片。" }
    }
}
