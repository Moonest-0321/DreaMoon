import Foundation
import SwiftData
import AppKit

enum StoryPlanningSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            StoryTag.self,
            ChapterAnnotation.self,
            BookPlanningProfile.self,
            OutlineStoryLine.self,
            OutlineStage.self,
            OutlineItem.self
        ]
    }
}

/// V2 的既有大綱模型保持不變；正文來源以新模型保存，避免回寫已發布的
/// `OutlineItem` schema snapshot。
enum StoryPlanningSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        StoryPlanningSchemaV2.models + [OutlineItemAnchor.self]
    }
}

/// V4 adds planning metadata without changing the released V3 outline models.
/// Both records link to the main book store by UUID rather than SwiftData relationships.
enum StoryPlanningSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        StoryPlanningSchemaV3.models + [OutlineStageStartAnchor.self, OutlineItemPlacement.self]
    }
}

enum StoryPlanningSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { StoryPlanningSchemaV4.models + [OutlineStageStartDetail.self] }
}

/// V6 stores timeline-card presentation metadata beside story planning. Event
/// remains in the main store, so cross-store references use stable UUIDs.
enum StoryPlanningSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] { StoryPlanningSchemaV5.models + [TimelineEventCardMetadata.self] }
}

enum StoryPlanningMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [StoryPlanningSchemaV1.self, StoryPlanningSchemaV2.self, StoryPlanningSchemaV3.self, StoryPlanningSchemaV4.self, StoryPlanningSchemaV5.self, StoryPlanningSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: StoryPlanningSchemaV1.self, toVersion: StoryPlanningSchemaV2.self),
            .lightweight(fromVersion: StoryPlanningSchemaV2.self, toVersion: StoryPlanningSchemaV3.self),
            .lightweight(fromVersion: StoryPlanningSchemaV3.self, toVersion: StoryPlanningSchemaV4.self),
            .lightweight(fromVersion: StoryPlanningSchemaV4.self, toVersion: StoryPlanningSchemaV5.self),
            .lightweight(fromVersion: StoryPlanningSchemaV5.self, toVersion: StoryPlanningSchemaV6.self)
        ]
    }
}

enum TimelineExcerptMode: String, CaseIterable, Identifiable {
    case automatic = "內文自動節錄"
    case manual = "手動自填"

    var id: String { rawValue }
}

/// Cross-store companion for a main-store Event. Deleting an outline source
/// never deletes the Event; the UI instead exposes the missing source.
@Model
final class TimelineEventCardMetadata {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var eventID: UUID
    var bookID: UUID
    var outlineItemID: UUID?
    var excerptModeRawValue: String
    var manualExcerpt: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        eventID: UUID,
        bookID: UUID,
        outlineItemID: UUID? = nil,
        excerptMode: TimelineExcerptMode = .automatic,
        manualExcerpt: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.eventID = eventID
        self.bookID = bookID
        self.outlineItemID = outlineItemID
        self.excerptModeRawValue = excerptMode.rawValue
        self.manualExcerpt = Self.limitedExcerpt(manualExcerpt)
        self.updatedAt = updatedAt
    }

    var excerptMode: TimelineExcerptMode {
        get { TimelineExcerptMode(rawValue: excerptModeRawValue) ?? .automatic }
        set { excerptModeRawValue = newValue.rawValue; updatedAt = Date() }
    }

    func setManualExcerpt(_ value: String) {
        manualExcerpt = Self.limitedExcerpt(value)
        updatedAt = Date()
    }

    static func limitedExcerpt(_ value: String) -> String {
        String(value.prefix(30))
    }
}

enum OutlineStoryLineKind: String, CaseIterable, Identifiable, Hashable {
    case prequel = "前傳"
    case main = "主線"
    case branch = "支線"
    case epilogue = "後記"

    var id: String { rawValue }
    var displayOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum OutlineItemStatus: String, CaseIterable, Identifiable, Hashable {
    case background = "背景"
    case occurred = "已發生"
    case draft = "草稿"
    case planned = "預定"

    var id: String { rawValue }

    var displayTitle: String { self == .occurred ? "已完成" : rawValue }
}

enum OutlineItemPlacementKind: String, CaseIterable, Identifiable, Hashable {
    case pending
    case stageStart
    case afterItem
    case stageEnd

    var id: String { rawValue }
}

struct OutlineStageStartLocation: Equatable {
    let volumeID: UUID
    let volumeTitle: String
    let sectionID: UUID?
    let sectionTitle: String
    let headingText: String
    let headingOffset: Int?

    var granularity: OutlineStageStartGranularity {
        if headingOffset != nil { return .heading }
        return sectionID == nil ? .volume : .section
    }

    init(
        volumeID: UUID,
        sectionID: UUID?,
        volumeTitle: String,
        sectionTitle: String,
        headingText: String = "",
        headingOffset: Int? = nil
    ) {
        self.volumeID = volumeID
        self.volumeTitle = volumeTitle
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
        self.headingText = headingText
        self.headingOffset = headingOffset
    }
}

enum OutlineStageStartGranularity: String, CaseIterable, Identifiable, Hashable {
    case volume
    case section
    case heading
    var id: String { rawValue }
}

struct ProseStructureScene: Equatable, Identifiable {
    let sectionID: UUID
    let title: String
    let startOffset: Int
    let endOffset: Int
    var id: String { "\(sectionID.uuidString):\(startOffset):\(title)" }
}

enum ProseStructureParser {
    static func scenes(in section: Section) -> [ProseStructureScene] {
        let attributed = NSAttributedString(section.content)
        let string = attributed.string as NSString
        guard string.length > 0 else {
            return [.init(sectionID: section.id, title: "尚未設定幕標題", startOffset: 0, endOffset: 0)]
        }
        var result: [ProseStructureScene] = []
        var currentTitle = "尚未設定幕標題"
        var currentStart = 0
        var offset = 0
        while offset < string.length {
            let range = string.paragraphRange(for: NSRange(location: offset, length: 0))
            let text = string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if !text.isEmpty, isSceneHeadingFont(font) {
                if range.location > currentStart {
                    result.append(.init(sectionID: section.id, title: currentTitle,
                                        startOffset: currentStart, endOffset: range.location))
                }
                currentTitle = text
                currentStart = range.location
            }
            let next = NSMaxRange(range)
            if next <= offset { break }
            offset = next
        }
        result.append(.init(sectionID: section.id, title: currentTitle,
                            startOffset: currentStart, endOffset: string.length))
        return result
    }
}

/// 寬版時間軸的唯讀投影；它只保存目前畫面需要的位置資訊，
/// 不建立第二份大綱資料，也不寫回故事規劃 store。
struct OutlineTimelineLayout: Equatable {
    struct Column: Identifiable, Equatable {
        let volumeID: UUID?
        let sectionID: UUID
        let volumeTitle: String
        let sectionTitle: String
        let headingTitle: String
        let contentStartOffset: Int?
        let contentEndOffset: Int?
        let index: Int

        var id: String { "\(sectionID.uuidString):\(contentStartOffset ?? -1)" }

        init(
            volumeID: UUID? = nil,
            sectionID: UUID,
            volumeTitle: String,
            sectionTitle: String,
            headingTitle: String = "",
            contentStartOffset: Int? = nil,
            contentEndOffset: Int? = nil,
            index: Int
        ) {
            self.volumeID = volumeID
            self.sectionID = sectionID
            self.volumeTitle = volumeTitle
            self.sectionTitle = sectionTitle
            self.headingTitle = headingTitle
            self.contentStartOffset = contentStartOffset
            self.contentEndOffset = contentEndOffset
            self.index = index
        }
    }

    struct Entry: Identifiable, Equatable {
        let itemID: UUID
        let columnIndex: Int
        let sequence: Int

        var id: UUID { itemID }
    }

    /// 主線階段在正文結構軸上的唯讀範圍。失效或尚未設定的起點不會
    /// 產生區段，避免畫面替作者猜測不存在的位置。
    struct StageBand: Identifiable, Equatable {
        let stageID: UUID
        let title: String
        let startColumnIndex: Int
        let endColumnIndex: Int

        var id: UUID { stageID }
    }

    struct Lane: Identifiable, Equatable {
        let storyLineID: UUID
        let title: String
        let kind: OutlineStoryLineKind
        let entries: [Entry]
        let pendingItemIDs: [UUID]
        let stageBands: [StageBand]

        var id: UUID { storyLineID }
    }

    let columns: [Column]
    let lanes: [Lane]
}

/// 寬版敘事大綱的精簡唯讀投影。它只描述既有故事線、階段與項目的
/// 閱讀順序，不建立副本，也不回寫任何排序資料。
struct NarrativeOutlineList: Equatable {
    struct Stage: Identifiable, Equatable {
        let id: UUID
        let title: String
        let itemIDs: [UUID]
    }

    struct StoryLine: Identifiable, Equatable {
        let id: UUID
        let title: String
        let kind: OutlineStoryLineKind
        let stages: [Stage]
        let unassignedItemIDs: [UUID]
        let pendingItemIDs: [UUID]
    }

    let storyLines: [StoryLine]

    var itemIDsInDisplayOrder: [UUID] {
        storyLines.flatMap { storyLine in
            storyLine.stages.flatMap(\.itemIDs)
                + storyLine.unassignedItemIDs
                + storyLine.pendingItemIDs
        }
    }
}

/// 將選填引導與自由文字保存於既有背景欄位，讓已發布的 schema V3 可直接讀取舊資料。
struct StoryBackgroundContent: Codable, Equatable {
    var worldBackground = ""
    var premise = ""
    var mainConflict = ""
    var protagonistGoal = ""
    var coreTheme = ""
    var otherBackground = ""

    init(storedValue: String = "") {
        if let data = storedValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            self = decoded
        } else {
            otherBackground = storedValue
        }
    }

    func encodedValue() -> String {
        guard let data = try? JSONEncoder().encode(self), let value = String(data: data, encoding: .utf8) else {
            return otherBackground
        }
        return value
    }
}

/// Whole-book planning data lives in the independent story-planning store and
/// links back to the main Book store only through this stable UUID.
@Model
final class BookPlanningProfile {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var bookID: UUID
    var backgroundText: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        backgroundText: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.backgroundText = backgroundText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class OutlineStoryLine {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var title: String
    var kindRawValue: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        title: String,
        kind: OutlineStoryLineKind,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.title = title
        self.kindRawValue = kind.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: OutlineStoryLineKind {
        get { OutlineStoryLineKind(rawValue: kindRawValue) ?? .branch }
        set { kindRawValue = newValue.rawValue; updatedAt = Date() }
    }
}

@Model
final class OutlineStage {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var storyLineID: UUID
    var title: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        storyLineID: UUID,
        title: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.storyLineID = storyLineID
        self.title = title
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class OutlineItem {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var storyLineID: UUID
    var stageID: UUID?
    var title: String
    var detail: String
    var statusRawValue: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        storyLineID: UUID,
        stageID: UUID? = nil,
        title: String,
        detail: String = "",
        status: OutlineItemStatus = .draft,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.storyLineID = storyLineID
        self.stageID = stageID
        self.title = title
        self.detail = detail
        self.statusRawValue = status.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: OutlineItemStatus {
        get { OutlineItemStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue; updatedAt = Date() }
    }
}

/// A prose source is optional: manually created outline items deliberately
/// have no anchor, while an item created from the editor has exactly one.
@Model
final class OutlineItemAnchor {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var outlineItemID: UUID
    var bookID: UUID
    var sectionID: UUID
    var anchorText: String
    var anchorOffset: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        outlineItemID: UUID,
        bookID: UUID,
        sectionID: UUID,
        anchorText: String,
        anchorOffset: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.outlineItemID = outlineItemID
        self.bookID = bookID
        self.sectionID = sectionID
        self.anchorText = anchorText
        self.anchorOffset = anchorOffset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func resolvedOffset(in text: String) -> Int {
        ProseAnchorResolver.resolvedOffset(anchorText: anchorText, anchorOffset: anchorOffset, in: text)
    }
}

/// An explicit stage start remains meaningful when its source section is later removed.
@Model
final class OutlineStageStartAnchor {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var stageID: UUID
    var bookID: UUID
    var volumeID: UUID
    var sectionID: UUID
    var volumeTitleSnapshot: String
    var sectionTitleSnapshot: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), stageID: UUID, bookID: UUID, location: OutlineStageStartLocation) {
        self.id = id
        self.stageID = stageID
        self.bookID = bookID
        self.volumeID = location.volumeID
        self.sectionID = location.sectionID ?? location.volumeID
        self.volumeTitleSnapshot = location.volumeTitle
        self.sectionTitleSnapshot = location.sectionTitle
        self.createdAt = Date()
        self.updatedAt = Date()
    }

}

/// V5 supplements the released V4 stage anchor without changing its schema snapshot.
/// Existing rows without a detail record retain V4's section-level meaning.
@Model
final class OutlineStageStartDetail {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var stageID: UUID
    var granularityRawValue: String
    var headingTextSnapshot: String
    var headingOffset: Int?
    var createdAt: Date
    var updatedAt: Date

    init(stageID: UUID, location: OutlineStageStartLocation) {
        self.id = UUID()
        self.stageID = stageID
        self.granularityRawValue = location.granularity.rawValue
        self.headingTextSnapshot = location.headingText
        self.headingOffset = location.headingOffset
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var granularity: OutlineStageStartGranularity {
        get { OutlineStageStartGranularity(rawValue: granularityRawValue) ?? .section }
        set { granularityRawValue = newValue.rawValue; updatedAt = Date() }
    }
}

/// Manual outline items use semantic placement instead of exposing numeric sort values.
@Model
final class OutlineItemPlacement {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var outlineItemID: UUID
    var kindRawValue: String
    var relativeItemID: UUID?
    var relativeItemTitleSnapshot: String
    var localOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        outlineItemID: UUID,
        kind: OutlineItemPlacementKind = .pending,
        relativeItemID: UUID? = nil,
        relativeItemTitleSnapshot: String = "",
        localOrder: Int = 0
    ) {
        self.id = id
        self.outlineItemID = outlineItemID
        self.kindRawValue = kind.rawValue
        self.relativeItemID = relativeItemID
        self.relativeItemTitleSnapshot = relativeItemTitleSnapshot
        self.localOrder = localOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: OutlineItemPlacementKind {
        get { OutlineItemPlacementKind(rawValue: kindRawValue) ?? .pending }
        set { kindRawValue = newValue.rawValue; updatedAt = Date() }
    }
}
