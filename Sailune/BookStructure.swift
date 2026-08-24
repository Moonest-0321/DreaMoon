import Foundation

/// Read-only projections of the writing hierarchy used by multiple screens.
/// Keeping ordering and aggregation here avoids rebuilding the same nested
/// arrays several times during a single SwiftUI render pass.
enum BookStructure {
    struct Metrics {
        let wordCount: Int
        let sectionCount: Int
    }

    static func orderedVolumes(in book: Book) -> [Volume] {
        book.volumes.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func orderedSections(in volume: Volume) -> [Section] {
        volume.sections.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func orderedSections(in book: Book) -> [Section] {
        orderedVolumes(in: book).flatMap { orderedSections(in: $0) }
    }

    static func position(of section: Section) -> (Int, Int) {
        guard let volume = section.volume, let book = volume.book else { return (Int.max, Int.max) }
        let volumes = orderedVolumes(in: book)
        guard let volumeIndex = volumes.firstIndex(where: { $0.id == volume.id }) else { return (Int.max, Int.max) }
        let sections = orderedSections(in: volume)
        let sectionIndex = sections.firstIndex(where: { $0.id == section.id }) ?? Int.max
        return (volumeIndex, sectionIndex)
    }

    static func metrics(for book: Book) -> Metrics {
        var wordCount = 0
        var sectionCount = 0
        for volume in book.volumes {
            sectionCount += volume.sections.count
            for section in volume.sections {
                wordCount += section.wordCount
            }
        }
        return Metrics(wordCount: wordCount, sectionCount: sectionCount)
    }
}
