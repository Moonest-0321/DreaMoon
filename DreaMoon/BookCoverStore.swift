import AppKit
import Foundation

/// Stores optional custom book covers outside SwiftData so existing libraries
/// remain compatible when the cover feature is introduced.
enum BookCoverStore {
    private static let directoryName = "DreaMoon/Covers"

    static func image(for book: Book) -> NSImage? {
        NSImage(contentsOf: url(for: book))
    }

    static func hasCover(for book: Book) -> Bool {
        FileManager.default.fileExists(atPath: url(for: book).path)
    }

    static func save(image: NSImage, for book: Book) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CoverStoreError.invalidImage
        }

        let directory = try coversDirectory()
        try pngData.write(to: directory.appendingPathComponent("\(book.id.uuidString).png"), options: .atomic)
    }

    static func removeCover(for book: Book) throws {
        let coverURL = url(for: book)
        guard FileManager.default.fileExists(atPath: coverURL.path) else { return }
        try FileManager.default.removeItem(at: coverURL)
    }

    private static func url(for book: Book) -> URL {
        let directory = (try? coversDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
        return directory.appendingPathComponent("\(book.id.uuidString).png")
    }

    private static func coversDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private enum CoverStoreError: LocalizedError {
        case invalidImage

        var errorDescription: String? { "無法讀取這張封面圖片。" }
    }
}
