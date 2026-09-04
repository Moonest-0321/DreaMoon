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
    private(set) var stageStartAnchors: [OutlineStageStartAnchor] = []
    private(set) var itemPlacements: [OutlineItemPlacement] = []

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
        stageStartAnchors = try context.fetch(FetchDescriptor<OutlineStageStartAnchor>())
        itemPlacements = try context.fetch(FetchDescriptor<OutlineItemPlacement>())
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

    func orderedStages(storyLineID: UUID, sections: [Section]) -> [OutlineStage] {
        let positions = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($1.id, $0) })
        return stages(storyLineID: storyLineID).sorted { lhs, rhs in
            let lhsPosition = stageStart(stageID: lhs.id).flatMap { positions[$0.sectionID] }
            let rhsPosition = stageStart(stageID: rhs.id).flatMap { positions[$0.sectionID] }
            switch (lhsPosition, rhsPosition) {
            case let (.some(left), .some(right)) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return Self.stableOrder(lhs, rhs)
            }
        }
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

    /// 正文來源依位置排序；手動項目則遵從其語意化安置位置。
    func orderedItems(storyLineID: UUID, stageID: UUID?, sections: [Section]) -> [OutlineItem] {
        let items = outlineItems.filter { $0.storyLineID == storyLineID && $0.stageID == stageID }
        let sectionPositions = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($1.id, $0) })
        let manual = items.filter { anchor(outlineItemID: $0.id) == nil }
        let prose = items.filter { anchor(outlineItemID: $0.id) != nil }.sorted {
            let lhs = prosePosition(for: $0, sectionPositions: sectionPositions, sections: sections)
            let rhs = prosePosition(for: $1, sectionPositions: sectionPositions, sections: sections)
            switch (lhs, rhs) {
            case let (.some(left), .some(right)) where left.sectionIndex != right.sectionIndex: return left.sectionIndex < right.sectionIndex
            case let (.some(left), .some(right)) where left.offset != right.offset: return left.offset < right.offset
            case (.some, .none): return true
            case (.none, .some): return false
            default: return Self.stableOrder($0, $1)
            }
        }
        func placed(_ kind: OutlineItemPlacementKind, after itemID: UUID? = nil) -> [OutlineItem] {
            manual.filter { item in
                let placement = placement(outlineItemID: item.id)
                return placement?.kind == kind && placement?.relativeItemID == itemID
            }
            .sorted { lhs, rhs in
                let leftOrder = placement(outlineItemID: lhs.id)?.localOrder ?? 0
                let rightOrder = placement(outlineItemID: rhs.id)?.localOrder ?? 0
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return Self.stableOrder(lhs, rhs)
            }
        }
        var result: [OutlineItem] = []
        var appended = Set<UUID>()
        func appendWithChildren(_ item: OutlineItem) {
            guard appended.insert(item.id).inserted else { return }
            result.append(item)
            for child in placed(.afterItem, after: item.id) { appendWithChildren(child) }
        }
        for item in placed(.stageStart) { appendWithChildren(item) }
        for item in prose {
            appendWithChildren(item)
        }
        for item in placed(.stageEnd) { appendWithChildren(item) }
        for item in manual.filter({ placement(outlineItemID: $0.id)?.kind == .pending }).sorted(by: Self.stableOrder) {
            appendWithChildren(item)
        }
        // 舊版未設定安置、失效掛點或循環資料都必須保留可見，不能因排序遺失。
        for item in manual.sorted(by: Self.stableOrder) { appendWithChildren(item) }
        return result
    }

    func anchor(outlineItemID: UUID) -> OutlineItemAnchor? {
        outlineAnchors.first { $0.outlineItemID == outlineItemID }
    }

    func stageStart(stageID: UUID) -> OutlineStageStartAnchor? {
        stageStartAnchors.first { $0.stageID == stageID }
    }

    func placement(outlineItemID: UUID) -> OutlineItemPlacement? {
        itemPlacements.first { $0.outlineItemID == outlineItemID }
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
    func createStage(
        storyLine: OutlineStoryLine,
        title: String? = nil,
        start: OutlineStageStartLocation
    ) throws -> OutlineStage {
        guard storyLine.kind == .main else { throw StoryPlanningStoreError.stagesRequireMainStoryLine }
        let peers = stages.filter { $0.storyLineID == storyLine.id }
        let stage = OutlineStage(bookID: storyLine.bookID, storyLineID: storyLine.id,
                                 title: normalizedTitle(title, fallback: "階段 \(peers.count + 1)"),
                                 sortOrder: (peers.map(\.sortOrder).max() ?? -1) + 1)
        // 階段與開始定位一併儲存，避免定位失敗後留下半成品。
        context.insert(stage)
        context.insert(OutlineStageStartAnchor(stageID: stage.id, bookID: stage.bookID, location: start))
        do {
            try context.save()
            try reload()
            return stage
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func setStageStart(_ stage: OutlineStage, to location: OutlineStageStartLocation) throws {
        let anchor = stageStart(stageID: stage.id) ?? OutlineStageStartAnchor(stageID: stage.id, bookID: stage.bookID, location: location)
        if stageStart(stageID: stage.id) == nil { context.insert(anchor) }
        anchor.volumeID = location.volumeID
        anchor.sectionID = location.sectionID
        anchor.volumeTitleSnapshot = location.volumeTitle
        anchor.sectionTitleSnapshot = location.sectionTitle
        anchor.updatedAt = Date()
        stage.updatedAt = Date()
        do {
            try context.save()
            try reload()
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    @discardableResult
    func createOutlineItem(
        storyLine: OutlineStoryLine,
        stage: OutlineStage? = nil,
        title: String = "新大綱項目",
        status: OutlineItemStatus = .draft
    ) throws -> OutlineItem {
        guard status != .occurred else { throw StoryPlanningStoreError.manualItemCannotBeCompleted }
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
        let placement = OutlineItemPlacement(outlineItemID: item.id, localOrder: peers.count)
        context.insert(placement)
        outlineItems.append(item)
        itemPlacements.append(placement)
        try context.save()
        return item
    }

    func setManualStatus(_ item: OutlineItem, to status: OutlineItemStatus) throws {
        guard anchor(outlineItemID: item.id) == nil else { throw StoryPlanningStoreError.proseItemStatusIsReadOnly }
        guard status != .occurred else { throw StoryPlanningStoreError.manualItemCannotBeCompleted }
        item.status = status
        do {
            try context.save()
            try reload()
        } catch {
            context.rollback()
            try reload()
            throw error
        }
    }

    func setPlacement(_ item: OutlineItem, kind: OutlineItemPlacementKind, after relativeItem: OutlineItem? = nil) throws {
        guard anchor(outlineItemID: item.id) == nil else { throw StoryPlanningStoreError.proseItemCannotBePlaced }
        guard kind != .afterItem || relativeItem != nil else { throw StoryPlanningStoreError.placementTargetRequired }
        guard kind == .afterItem || relativeItem == nil else { throw StoryPlanningStoreError.invalidPlacementTarget }
        if let relativeItem {
            guard outlineItems.contains(where: { $0.id == relativeItem.id }), relativeItem.bookID == item.bookID, relativeItem.storyLineID == item.storyLineID, relativeItem.stageID == item.stageID, relativeItem.id != item.id else {
                throw StoryPlanningStoreError.invalidPlacementTarget
            }
            guard !wouldCreatePlacementCycle(itemID: item.id, targetID: relativeItem.id) else {
                throw StoryPlanningStoreError.placementCycle
            }
        }
        let placement = placement(outlineItemID: item.id) ?? OutlineItemPlacement(outlineItemID: item.id)
        if self.placement(outlineItemID: item.id) == nil { context.insert(placement) }
        placement.kind = kind
        placement.relativeItemID = relativeItem?.id
        placement.relativeItemTitleSnapshot = relativeItem?.title ?? ""
        placement.localOrder = nextPlacementOrder(kind: kind, relativeItemID: relativeItem?.id)
        placement.updatedAt = Date()
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

    /// 只調整同一安置位置的兄弟項目，不改動正文順序或子項目的掛點。
    func moveManualItem(_ item: OutlineItem, earlier: Bool) throws {
        guard anchor(outlineItemID: item.id) == nil else { throw StoryPlanningStoreError.proseItemCannotBePlaced }
        guard let current = placement(outlineItemID: item.id), current.kind != .pending else { return }
        let peers = outlineItems.filter {
            guard $0.storyLineID == item.storyLineID, $0.stageID == item.stageID,
                  anchor(outlineItemID: $0.id) == nil,
                  let value = placement(outlineItemID: $0.id) else { return false }
            return value.kind == current.kind && value.relativeItemID == current.relativeItemID
        }.sorted {
            let left = placement(outlineItemID: $0.id)?.localOrder ?? 0
            let right = placement(outlineItemID: $1.id)?.localOrder ?? 0
            return left == right ? Self.stableOrder($0, $1) : left < right
        }
        guard let index = peers.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + (earlier ? -1 : 1)
        guard peers.indices.contains(destination) else { return }
        var reordered = peers
        reordered.swapAt(index, destination)
        for (order, peer) in reordered.enumerated() {
            placement(outlineItemID: peer.id)?.localOrder = order
            placement(outlineItemID: peer.id)?.updatedAt = Date()
        }
        do {
            try context.save()
            try reload()
        } catch {
            context.rollback()
            try reload()
            throw error
        }
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
            moveDependentPlacementsToPending(for: item)
            if let placement = placement(outlineItemID: item.id) { context.delete(placement) }
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
            for placement in itemPlacements where itemIDs.contains(placement.outlineItemID) { context.delete(placement) }
            for placement in itemPlacements where placement.relativeItemID.map(itemIDs.contains) == true {
                placement.kind = .pending
                placement.relativeItemID = nil
            }
            for item in outlineItems where item.storyLineID == storyLine.id { context.delete(item) }
            let stageIDs = Set(stages.filter { $0.storyLineID == storyLine.id }.map(\.id))
            for start in stageStartAnchors where stageIDs.contains(start.stageID) { context.delete(start) }
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
        if item.stageID != stage?.id { moveDependentPlacementsToPending(for: item) }
        item.stageID = stage?.id
        if let placement = placement(outlineItemID: item.id),
           placement.kind == .afterItem,
           let targetID = placement.relativeItemID,
           outlineItems.first(where: { $0.id == targetID })?.stageID != stage?.id {
            placement.kind = .pending
            placement.relativeItemID = nil
            placement.updatedAt = Date()
        }
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
            let itemsToDelete = outlineItems.filter { $0.stageID == stage.id }
            for item in itemsToDelete {
                moveDependentPlacementsToPending(for: item)
                if let placement = placement(outlineItemID: item.id) { context.delete(placement) }
                if let anchor = anchor(outlineItemID: item.id) { context.delete(anchor) }
                context.delete(item)
            }
            if let start = stageStart(stageID: stage.id) { context.delete(start) }
            context.delete(stage)
            try context.save()
            try reload()
            NotificationCenter.default.post(name: .sailunePlanningMarkersChanged, object: nil)
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

    /// 正文優先分派至對應起點；無法對應時放入畫面最後階段，不改寫階段定位。
    private func stageForProse(
        storyLine: OutlineStoryLine,
        anchorText: String,
        anchorOffset: Int,
        sectionID: UUID,
        sections: [Section]
    ) -> OutlineStage? {
        let stages = orderedStages(storyLineID: storyLine.id, sections: sections)
        guard !stages.isEmpty else { return nil }
        let sectionPositions = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($1.id, $0) })
        guard let sectionIndex = sectionPositions[sectionID] else { return stages.last }
        let starts = stages.compactMap { stage -> (stage: OutlineStage, sectionIndex: Int)? in
            guard let start = stageStart(stageID: stage.id), let index = sectionPositions[start.sectionID] else { return nil }
            return (stage, index)
        }
        guard !starts.isEmpty else { return stages.last }
        let sortedStarts = starts.sorted {
            if $0.sectionIndex != $1.sectionIndex { return $0.sectionIndex < $1.sectionIndex }
            return Self.stableOrder($0.stage, $1.stage)
        }
        let matching = sortedStarts.last {
            $0.sectionIndex <= sectionIndex
        }
        return matching?.stage ?? stages.last
    }

    private func moveDependentPlacementsToPending(for item: OutlineItem) {
        for placement in itemPlacements where placement.relativeItemID == item.id {
            placement.kind = .pending
            placement.relativeItemID = nil
            placement.relativeItemTitleSnapshot = item.title
            placement.updatedAt = Date()
        }
    }

    private func nextPlacementOrder(kind: OutlineItemPlacementKind, relativeItemID: UUID?) -> Int {
        itemPlacements
            .filter { $0.kind == kind && $0.relativeItemID == relativeItemID }
            .map(\.localOrder)
            .max()
            .map { $0 + 1 } ?? 0
    }

    private func wouldCreatePlacementCycle(itemID: UUID, targetID: UUID) -> Bool {
        var currentID: UUID? = targetID
        var visited = Set<UUID>()
        while let current = currentID, visited.insert(current).inserted {
            if current == itemID { return true }
            currentID = placement(outlineItemID: current)?.relativeItemID
        }
        return false
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
    case manualItemCannotBeCompleted
    case proseItemStatusIsReadOnly
    case proseItemCannotBePlaced
    case missingManualPlacement
    case placementTargetRequired
    case invalidPlacementTarget
    case placementCycle

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
        case .manualItemCannotBeCompleted:
            return "已完成只能由正文選取建立的大綱項目使用。"
        case .proseItemStatusIsReadOnly:
            return "正文來源項目的完成狀態會由正文維持，不能手動修改。"
        case .proseItemCannotBePlaced:
            return "正文來源項目會依正文位置排列，不能手動安置。"
        case .missingManualPlacement:
            return "找不到手動項目的安置資料；請重新開啟後再試。"
        case .placementTargetRequired:
            return "請選擇要接在其後的大綱項目。"
        case .invalidPlacementTarget:
            return "手動項目只能接在同一階段的其他項目後。"
        case .placementCycle:
            return "不能把項目安置在自己的後續項目之後。"
        }
    }
}
