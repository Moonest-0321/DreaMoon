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
    private(set) var bookProfiles: [BookPlanningProfile] = []
    private(set) var storyLines: [OutlineStoryLine] = []
    private(set) var stages: [OutlineStage] = []
    private(set) var outlineItems: [OutlineItem] = []

    init(container: ModelContainer) throws {
        self.container = container
        self.context = container.mainContext
        context.autosaveEnabled = true
        try reload()
    }

    func reload() throws {
        tags = try context.fetch(FetchDescriptor<StoryTag>())
        annotations = try context.fetch(FetchDescriptor<ChapterAnnotation>())
        bookProfiles = try context.fetch(FetchDescriptor<BookPlanningProfile>())
        storyLines = try context.fetch(FetchDescriptor<OutlineStoryLine>())
        stages = try context.fetch(FetchDescriptor<OutlineStage>())
        outlineItems = try context.fetch(FetchDescriptor<OutlineItem>())
    }

    func tags(bookID: UUID) -> [StoryTag] { tags.filter { $0.bookID == bookID } }
    func tags(sectionID: UUID) -> [StoryTag] { tags.filter { $0.sectionID == sectionID } }
    func annotation(sectionID: UUID) -> ChapterAnnotation? { annotations.first { $0.sectionID == sectionID } }
    func profile(bookID: UUID) -> BookPlanningProfile? { bookProfiles.first { $0.bookID == bookID } }

    func storyLines(bookID: UUID) -> [OutlineStoryLine] {
        storyLines
            .filter { $0.bookID == bookID }
            .sorted {
                if $0.kind.displayOrder != $1.kind.displayOrder {
                    return $0.kind.displayOrder < $1.kind.displayOrder
                }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func stages(storyLineID: UUID) -> [OutlineStage] {
        stages
            .filter { $0.storyLineID == storyLineID }
            .sorted(by: Self.stableOrder)
    }

    func items(storyLineID: UUID) -> [OutlineItem] {
        outlineItems
            .filter { $0.storyLineID == storyLineID }
            .sorted(by: Self.stableOrder)
    }

    func items(bookID: UUID) -> [OutlineItem] {
        outlineItems
            .filter { $0.bookID == bookID }
            .sorted(by: Self.stableOrder)
    }

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

    @discardableResult
    func ensureProfile(bookID: UUID) throws -> BookPlanningProfile {
        if let existing = profile(bookID: bookID) { return existing }
        let profile = BookPlanningProfile(bookID: bookID)
        context.insert(profile)
        bookProfiles.append(profile)
        try context.save()
        return profile
    }

    @discardableResult
    func createStoryLine(bookID: UUID, kind: OutlineStoryLineKind, title: String? = nil) throws -> OutlineStoryLine {
        let peers = storyLines.filter { $0.bookID == bookID && $0.kind == kind }
        guard kind != .main || peers.isEmpty else {
            throw StoryPlanningStoreError.mainStoryLineAlreadyExists
        }
        let storyLine = OutlineStoryLine(
            bookID: bookID,
            title: normalizedTitle(title, fallback: defaultStoryLineTitle(kind: kind, count: peers.count)),
            kind: kind,
            sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(storyLine)
        storyLines.append(storyLine)
        try context.save()
        return storyLine
    }

    @discardableResult
    func createStage(storyLine: OutlineStoryLine, title: String? = nil) throws -> OutlineStage {
        guard storyLine.kind == .main else { throw StoryPlanningStoreError.stagesRequireMainStoryLine }
        let peers = stages.filter { $0.storyLineID == storyLine.id }
        let stage = OutlineStage(
            bookID: storyLine.bookID,
            storyLineID: storyLine.id,
            title: normalizedTitle(title, fallback: "階段 \(peers.count + 1)"),
            sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(stage)
        stages.append(stage)
        try context.save()
        return stage
    }

    @discardableResult
    func createOutlineItem(
        storyLine: OutlineStoryLine,
        stage: OutlineStage? = nil,
        title: String = "新大綱項目",
        status: OutlineItemStatus = .draft
    ) throws -> OutlineItem {
        guard stage == nil || stage?.storyLineID == storyLine.id else {
            throw StoryPlanningStoreError.stageDoesNotBelongToStoryLine
        }
        let peers = outlineItems.filter { $0.storyLineID == storyLine.id }
        let item = OutlineItem(
            bookID: storyLine.bookID,
            storyLineID: storyLine.id,
            stageID: stage?.id,
            title: normalizedTitle(title, fallback: "新大綱項目"),
            status: status,
            sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(item)
        outlineItems.append(item)
        try context.save()
        return item
    }

    func saveChanges() throws {
        try context.save()
    }

    func save() { try? context.save() }

    private static func stableOrder<T>(_ lhs: T, _ rhs: T) -> Bool where T: StoryPlanningOrderedModel {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func normalizedTitle(_ proposed: String?, fallback: String) -> String {
        let value = proposed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private func defaultStoryLineTitle(kind: OutlineStoryLineKind, count: Int) -> String {
        count == 0 ? kind.rawValue : "\(kind.rawValue) \(count + 1)"
    }
}

private protocol StoryPlanningOrderedModel {
    var id: UUID { get }
    var sortOrder: Int { get }
    var createdAt: Date { get }
}

extension OutlineStage: StoryPlanningOrderedModel { }
extension OutlineItem: StoryPlanningOrderedModel { }

enum StoryPlanningStoreError: LocalizedError {
    case mainStoryLineAlreadyExists
    case stagesRequireMainStoryLine
    case stageDoesNotBelongToStoryLine

    var errorDescription: String? {
        switch self {
        case .mainStoryLineAlreadyExists:
            return "一本書只能有一條主線；請用主線階段整理故事發展。"
        case .stagesRequireMainStoryLine:
            return "只有主線可以建立故事階段。"
        case .stageDoesNotBelongToStoryLine:
            return "選擇的故事階段不屬於這條故事線。"
        }
    }
}
