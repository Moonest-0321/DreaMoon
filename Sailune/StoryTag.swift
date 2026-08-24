import Foundation
import Observation
import SwiftData

enum StoryPlanningSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StoryTag.self, ChapterAnnotation.self] }
}

/// A lightweight story-planning marker attached to selected prose. It lives
/// beside the prose rather than changing its meaning: the editor only draws a
/// transient colour cue at the saved location.
enum StoryTagKind: String, CaseIterable, Identifiable, Hashable {
    case main = "主軸"
    case branch = "支線"
    case foreshadowing = "伏筆"
    case revision = "修改"
    case plannedAddition = "計劃加入"

    var id: String { rawValue }
}

@Model
final class StoryTag {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRawValue: String
    /// The selected text is a resilient anchor when text is inserted above it.
    var anchorText: String
    /// UTF-16 position, used to choose the nearest repeated anchor text.
    var anchorOffset: Int
    var createdAt: Date
    var updatedAt: Date
    var bookID: UUID
    var sectionID: UUID

    init(
        id: UUID = UUID(),
        title: String,
        kind: StoryTagKind,
        anchorText: String,
        anchorOffset: Int,
        bookID: UUID,
        sectionID: UUID
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.anchorText = anchorText
        self.anchorOffset = anchorOffset
        self.createdAt = Date()
        self.updatedAt = Date()
        self.bookID = bookID
        self.sectionID = sectionID
    }

    var kind: StoryTagKind {
        get { StoryTagKind(rawValue: kindRawValue) ?? .main }
        set { kindRawValue = newValue.rawValue; updatedAt = Date() }
    }

    /// Revision work applies to the whole selection. Structural story tags
    /// remain compact markers on the first character only.
    func markerLength(availableFromOffset: Int) -> Int {
        guard availableFromOffset > 0 else { return 0 }
        switch kind {
        case .revision, .plannedAddition:
            return min(max(1, (anchorText as NSString).length), availableFromOffset)
        case .main, .branch, .foreshadowing:
            return 1
        }
    }

    /// Finds the same selected text nearest to its former location. This keeps
    /// a tag at its paragraph when earlier prose is inserted or removed.
    func resolvedOffset(in text: String) -> Int {
        let source = anchorText
        let length = (text as NSString).length
        guard !source.isEmpty else { return min(max(0, anchorOffset), length) }
        let nsText = text as NSString
        let sourceRange = NSRange(location: 0, length: length)
        var candidates: [Int] = []
        var searchRange = sourceRange
        while searchRange.length > 0 {
            let found = nsText.range(of: source, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            candidates.append(found.location)
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: max(0, length - next))
        }
        return candidates.min(by: { abs($0 - anchorOffset) < abs($1 - anchorOffset) })
            ?? min(max(0, anchorOffset), length)
    }
}

@Model
final class ChapterAnnotation {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sectionID: UUID
    var bookID: UUID
    var plannedOutline: String
    var revisionNote: String
    var updatedAt: Date

    init(id: UUID = UUID(), sectionID: UUID, bookID: UUID, plannedOutline: String = "", revisionNote: String = "") {
        self.id = id
        self.sectionID = sectionID
        self.bookID = bookID
        self.plannedOutline = plannedOutline
        self.revisionNote = revisionNote
        self.updatedAt = Date()
    }
}

@MainActor
@Observable
final class StoryPlanningStore {
    let container: ModelContainer
    private let context: ModelContext
    private(set) var tags: [StoryTag] = []
    private(set) var annotations: [ChapterAnnotation] = []

    init(container: ModelContainer) throws {
        self.container = container
        self.context = container.mainContext
        context.autosaveEnabled = true
        try reload()
    }

    func reload() throws {
        tags = try context.fetch(FetchDescriptor<StoryTag>())
        annotations = try context.fetch(FetchDescriptor<ChapterAnnotation>())
    }

    func tags(bookID: UUID) -> [StoryTag] { tags.filter { $0.bookID == bookID } }
    func tags(sectionID: UUID) -> [StoryTag] { tags.filter { $0.sectionID == sectionID } }
    func annotation(sectionID: UUID) -> ChapterAnnotation? { annotations.first { $0.sectionID == sectionID } }

    @discardableResult
    func createTag(title: String, kind: StoryTagKind, anchorText: String, anchorOffset: Int, bookID: UUID, sectionID: UUID) -> StoryTag {
        let tag = StoryTag(title: title, kind: kind, anchorText: anchorText, anchorOffset: anchorOffset, bookID: bookID, sectionID: sectionID)
        context.insert(tag)
        tags.append(tag)
        save()
        return tag
    }

    @discardableResult
    func ensureAnnotation(sectionID: UUID, bookID: UUID) -> ChapterAnnotation {
        if let existing = annotation(sectionID: sectionID) { return existing }
        let annotation = ChapterAnnotation(sectionID: sectionID, bookID: bookID)
        context.insert(annotation)
        annotations.append(annotation)
        save()
        return annotation
    }

    func save() { try? context.save() }
}
