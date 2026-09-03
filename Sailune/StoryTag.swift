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

    /// Only these kinds remain in the tag system after V3. The other raw
    /// values stay decodable so that existing stores can be converted.
    static var allCases: [StoryTagKind] { [.foreshadowing, .revision] }
    static let outlineCreationCases: [StoryTagKind] = [.main, .branch, .plannedAddition]

    var isStructuralOutlineKind: Bool {
        switch self {
        case .main, .branch, .plannedAddition: true
        case .foreshadowing, .revision: false
        }
    }

    var editorActionTitle: String {
        switch self {
        case .main: "加入主線大綱"
        case .branch: "新增支線大綱"
        case .plannedAddition: "加入主線草稿"
        case .foreshadowing, .revision: rawValue
        }
    }
}

enum ProseAnchorResolver {
    static func resolvedOffset(anchorText: String, anchorOffset: Int, in text: String) -> Int {
        let length = (text as NSString).length
        guard !anchorText.isEmpty else { return min(max(0, anchorOffset), length) }
        let nsText = text as NSString
        var candidates: [Int] = []
        var searchRange = NSRange(location: 0, length: length)
        while searchRange.length > 0 {
            let found = nsText.range(of: anchorText, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
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
        get { StoryTagKind(rawValue: kindRawValue) ?? .foreshadowing }
        set { kindRawValue = newValue.rawValue; updatedAt = Date() }
    }

    /// Revision work applies to the whole selection. Structural story tags
    /// remain compact markers on the first character only.
    func markerLength(availableFromOffset: Int) -> Int {
        guard availableFromOffset > 0 else { return 0 }
        switch kind {
        case .revision:
            return min(max(1, (anchorText as NSString).length), availableFromOffset)
        case .main, .branch, .foreshadowing, .plannedAddition:
            return 1
        }
    }

    /// Finds the same selected text nearest to its former location. This keeps
    /// a tag at its paragraph when earlier prose is inserted or removed.
    func resolvedOffset(in text: String) -> Int {
        ProseAnchorResolver.resolvedOffset(anchorText: anchorText, anchorOffset: anchorOffset, in: text)
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
    private(set) var outlineAnchors: [OutlineItemAnchor] = []

    init(container: ModelContainer) throws {
        self.container = container
        self.context = container.mainContext
        context.autosaveEnabled = true
        try reload()
        try migrateLegacyStructuralTags()
    }

    func reload() throws {
        tags = try context.fetch(FetchDescriptor<StoryTag>())
        annotations = try context.fetch(FetchDescriptor<ChapterAnnotation>())
        bookProfiles = try context.fetch(FetchDescriptor<BookPlanningProfile>())
        storyLines = try context.fetch(FetchDescriptor<OutlineStoryLine>())
        stages = try context.fetch(FetchDescriptor<OutlineStage>())
        outlineItems = try context.fetch(FetchDescriptor<OutlineItem>())
        outlineAnchors = try context.fetch(FetchDescriptor<OutlineItemAnchor>())
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

    /// 正文來源存在時，以目前書籍中的卷／節與節內文字位置排序；其餘項目留在後方。
    func orderedItems(storyLineID: UUID, stageID: UUID?, sections: [Section]) -> [OutlineItem] {
        let items = outlineItems.filter { $0.storyLineID == storyLineID && $0.stageID == stageID }
        let sectionPositions = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($1.id, $0) })
        return items.sorted { lhs, rhs in
            let lhsPosition = prosePosition(for: lhs, sectionPositions: sectionPositions, sections: sections)
            let rhsPosition = prosePosition(for: rhs, sectionPositions: sectionPositions, sections: sections)
            switch (lhsPosition, rhsPosition) {
            case let (.some(lhsPosition), .some(rhsPosition)):
                if lhsPosition.sectionIndex != rhsPosition.sectionIndex {
                    return lhsPosition.sectionIndex < rhsPosition.sectionIndex
                }
                if lhsPosition.offset != rhsPosition.offset { return lhsPosition.offset < rhsPosition.offset }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return Self.stableOrder(lhs, rhs)
        }
    }

    func anchor(outlineItemID: UUID) -> OutlineItemAnchor? {
        outlineAnchors.first { $0.outlineItemID == outlineItemID }
    }

    func outlineMarkers(sectionID: UUID) -> [(item: OutlineItem, anchor: OutlineItemAnchor)] {
        outlineAnchors.compactMap { anchor in
            guard anchor.sectionID == sectionID,
                  let item = outlineItems.first(where: { $0.id == anchor.outlineItemID }) else { return nil }
            return (item, anchor)
        }
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
        let assignedStage = stage ?? (storyLine.kind == .main ? stages(storyLineID: storyLine.id).last : nil)
        guard assignedStage == nil || assignedStage?.storyLineID == storyLine.id else {
            throw StoryPlanningStoreError.stageDoesNotBelongToStoryLine
        }
        let peers = outlineItems.filter { $0.storyLineID == storyLine.id }
        let item = OutlineItem(
            bookID: storyLine.bookID,
            storyLineID: storyLine.id,
            stageID: assignedStage?.id,
            title: normalizedTitle(title, fallback: "新大綱項目"),
            status: status,
            sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(item)
        outlineItems.append(item)
        try context.save()
        return item
    }

    @discardableResult
    func createOutlineItemFromProse(
        kind: StoryTagKind,
        title: String,
        anchorText: String,
        anchorOffset: Int,
        bookID: UUID,
        sectionID: UUID,
        sections: [Section] = []
    ) throws -> OutlineItem {
        guard kind.isStructuralOutlineKind else { throw StoryPlanningStoreError.invalidOutlineCreationKind }
        let storyLine: OutlineStoryLine
        switch kind {
        case .main, .plannedAddition:
            storyLine = try ensureMainStoryLine(bookID: bookID)
        case .branch:
            storyLine = makeStoryLine(bookID: bookID, kind: .branch)
            context.insert(storyLine)
        case .foreshadowing, .revision:
            throw StoryPlanningStoreError.invalidOutlineCreationKind
        }
        let status: OutlineItemStatus = kind == .plannedAddition ? .draft : .occurred
        let defaultStage = kind == .main || kind == .plannedAddition
            ? stageForProse(
                storyLine: storyLine,
                anchorText: anchorText,
                anchorOffset: anchorOffset,
                sectionID: sectionID,
                sections: sections
            )
            : nil
        let item = makeOutlineItem(storyLine: storyLine, stage: defaultStage, id: UUID(), title: title, status: status)
        let anchor = OutlineItemAnchor(
            outlineItemID: item.id,
            bookID: bookID,
            sectionID: sectionID,
            anchorText: anchorText,
            anchorOffset: anchorOffset
        )
        context.insert(item)
        context.insert(anchor)
        try context.save()
        try reload()
        return item
    }

    func deleteOutlineItem(_ item: OutlineItem) throws {
        do {
            if let anchor = anchor(outlineItemID: item.id) { context.delete(anchor) }
            context.delete(item)
            try context.save()
            try reload()
            NotificationCenter.default.post(name: .sailunePlanningMarkersChanged, object: nil)
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func deleteStoryLine(_ storyLine: OutlineStoryLine) throws {
        do {
            let itemIDs = Set(outlineItems.filter { $0.storyLineID == storyLine.id }.map(\.id))
            for anchor in outlineAnchors where itemIDs.contains(anchor.outlineItemID) { context.delete(anchor) }
            for item in outlineItems where item.storyLineID == storyLine.id { context.delete(item) }
            for stage in stages where stage.storyLineID == storyLine.id { context.delete(stage) }
            context.delete(storyLine)
            try context.save()
            try reload()
            NotificationCenter.default.post(name: .sailunePlanningMarkersChanged, object: nil)
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func moveOutlineItem(_ item: OutlineItem, to stage: OutlineStage?) throws {
        guard let storyLine = storyLines.first(where: { $0.id == item.storyLineID }), storyLine.kind == .main else {
            throw StoryPlanningStoreError.outlineItemDoesNotBelongToMainStoryLine
        }
        guard stage == nil || (stage?.storyLineID == storyLine.id && stage?.bookID == item.bookID) else {
            throw StoryPlanningStoreError.stageDoesNotBelongToStoryLine
        }
        item.stageID = stage?.id
        item.updatedAt = Date()
        do {
            try context.save()
            try reload()
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func deleteStage(_ stage: OutlineStage) throws {
        do {
            for item in outlineItems where item.stageID == stage.id {
                item.stageID = nil
                item.updatedAt = Date()
            }
            context.delete(stage)
            try context.save()
            try reload()
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func deleteStoryTag(_ tag: StoryTag) throws {
        guard !tag.kind.isStructuralOutlineKind else { throw StoryPlanningStoreError.structuralStoryTagCannotBeDeleted }
        do {
            context.delete(tag)
            try context.save()
            try reload()
            NotificationCenter.default.post(name: .sailunePlanningMarkersChanged, object: nil)
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func saveChanges() throws {
        try context.save()
    }

    func save() { try? context.save() }

    private func migrateLegacyStructuralTags() throws {
        let legacyTags = tags
            .filter { $0.kind.isStructuralOutlineKind }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        guard !legacyTags.isEmpty else { return }

        do {
            for tag in legacyTags {
                let line: OutlineStoryLine
                switch tag.kind {
                case .main, .plannedAddition:
                    line = try ensureMainStoryLineForMigration(bookID: tag.bookID)
                case .branch:
                    line = makeStoryLine(bookID: tag.bookID, kind: .branch)
                    context.insert(line)
                case .foreshadowing, .revision:
                    continue
                }
                let item = outlineItems.first(where: { $0.id == tag.id })
                    ?? makeOutlineItem(
                        storyLine: line,
                        id: tag.id,
                        title: tag.title,
                        status: tag.kind == .plannedAddition ? .draft : .occurred
                    )
                if !outlineItems.contains(where: { $0.id == item.id }) {
                    context.insert(item)
                    outlineItems.append(item)
                }
                if !outlineAnchors.contains(where: { $0.outlineItemID == item.id }) {
                    let anchor = OutlineItemAnchor(
                        outlineItemID: item.id,
                        bookID: tag.bookID,
                        sectionID: tag.sectionID,
                        anchorText: tag.anchorText,
                        anchorOffset: tag.anchorOffset
                    )
                    context.insert(anchor)
                    outlineAnchors.append(anchor)
                }
                context.delete(tag)
            }
            try context.save()
            try reload()
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    private func prosePosition(
        for item: OutlineItem,
        sectionPositions: [UUID: Int],
        sections: [Section]
    ) -> (sectionIndex: Int, offset: Int)? {
        guard let anchor = anchor(outlineItemID: item.id),
              let sectionIndex = sectionPositions[anchor.sectionID] else { return nil }
        let section = sections[sectionIndex]
        return (sectionIndex, anchor.resolvedOffset(in: String(section.content.characters)))
    }

    /// 階段以其中最早的正文來源為起點；新正文項目進入最近且不晚於其位置的階段。
    private func stageForProse(
        storyLine: OutlineStoryLine,
        anchorText: String,
        anchorOffset: Int,
        sectionID: UUID,
        sections: [Section]
    ) -> OutlineStage? {
        let stages = stages(storyLineID: storyLine.id)
        guard !stages.isEmpty else { return nil }
        let sectionPositions = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($1.id, $0) })
        guard let sectionIndex = sectionPositions[sectionID] else { return stages.last }
        let newOffset = ProseAnchorResolver.resolvedOffset(
            anchorText: anchorText,
            anchorOffset: anchorOffset,
            in: String(sections[sectionIndex].content.characters)
        )
        let starts = stages.compactMap { stage -> (stage: OutlineStage, sectionIndex: Int, offset: Int)? in
            let positions = outlineItems
                .filter { $0.stageID == stage.id }
                .compactMap { prosePosition(for: $0, sectionPositions: sectionPositions, sections: sections) }
            guard let start = positions.min(by: { lhs, rhs in
                lhs.sectionIndex == rhs.sectionIndex ? lhs.offset < rhs.offset : lhs.sectionIndex < rhs.sectionIndex
            }) else { return nil }
            return (stage, start.sectionIndex, start.offset)
        }
        guard !starts.isEmpty else { return stages.last }
        let sortedStarts = starts.sorted {
            $0.sectionIndex == $1.sectionIndex ? $0.offset < $1.offset : $0.sectionIndex < $1.sectionIndex
        }
        let matching = sortedStarts.last {
            $0.sectionIndex < sectionIndex || ($0.sectionIndex == sectionIndex && $0.offset <= newOffset)
        }
        return matching?.stage ?? sortedStarts.first?.stage
    }

    private func ensureMainStoryLine(bookID: UUID) throws -> OutlineStoryLine {
        if let line = storyLines.first(where: { $0.bookID == bookID && $0.kind == .main }) { return line }
        let line = makeStoryLine(bookID: bookID, kind: .main)
        context.insert(line)
        try context.save()
        try reload()
        return line
    }

    private func ensureMainStoryLineForMigration(bookID: UUID) throws -> OutlineStoryLine {
        if let line = storyLines.first(where: { $0.bookID == bookID && $0.kind == .main }) { return line }
        let line = makeStoryLine(bookID: bookID, kind: .main)
        context.insert(line)
        storyLines.append(line)
        return line
    }

    private func makeStoryLine(bookID: UUID, kind: OutlineStoryLineKind) -> OutlineStoryLine {
        let peers = storyLines.filter { $0.bookID == bookID && $0.kind == kind }
        let line = OutlineStoryLine(
            bookID: bookID,
            title: defaultStoryLineTitle(kind: kind, count: peers.count),
            kind: kind,
            sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1
        )
        storyLines.append(line)
        return line
    }

    private func makeOutlineItem(
        storyLine: OutlineStoryLine,
        stage: OutlineStage? = nil,
        id: UUID,
        title: String,
        status: OutlineItemStatus
    ) -> OutlineItem {
        let peers = outlineItems.filter { $0.storyLineID == storyLine.id }
        return OutlineItem(
            id: id,
            bookID: storyLine.bookID,
            storyLineID: storyLine.id,
            stageID: stage?.id,
            title: normalizedTitle(title, fallback: "新大綱項目"),
            status: status,
            sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1
        )
    }

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
    case outlineItemDoesNotBelongToMainStoryLine
    case invalidOutlineCreationKind
    case structuralStoryTagCannotBeDeleted

    var errorDescription: String? {
        switch self {
        case .mainStoryLineAlreadyExists:
            return "一本書只能有一條主線；請用主線階段整理故事發展。"
        case .stagesRequireMainStoryLine:
            return "只有主線可以建立故事階段。"
        case .stageDoesNotBelongToStoryLine:
            return "選擇的故事階段不屬於這條故事線。"
        case .outlineItemDoesNotBelongToMainStoryLine:
            return "只有主線大綱項目可以移至故事階段。"
        case .invalidOutlineCreationKind:
            return "只有主線、支線與主線草稿可以從正文建立大綱。"
        case .structuralStoryTagCannotBeDeleted:
            return "結構標籤已整合至大綱，請從大綱刪除。"
        }
    }
}
