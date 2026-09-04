import Foundation
import SwiftData

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

enum StoryPlanningMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [StoryPlanningSchemaV1.self, StoryPlanningSchemaV2.self, StoryPlanningSchemaV3.self, StoryPlanningSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: StoryPlanningSchemaV1.self, toVersion: StoryPlanningSchemaV2.self),
            .lightweight(fromVersion: StoryPlanningSchemaV2.self, toVersion: StoryPlanningSchemaV3.self),
            .lightweight(fromVersion: StoryPlanningSchemaV3.self, toVersion: StoryPlanningSchemaV4.self)
        ]
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
    let sectionID: UUID
    let volumeTitle: String
    let sectionTitle: String
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
        self.sectionID = location.sectionID
        self.volumeTitleSnapshot = location.volumeTitle
        self.sectionTitleSnapshot = location.sectionTitle
        self.createdAt = Date()
        self.updatedAt = Date()
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
