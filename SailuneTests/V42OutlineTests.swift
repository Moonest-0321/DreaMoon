import XCTest
import SwiftData
@testable import Sailune

@MainActor
final class V42OutlineTests: XCTestCase {
    private func makePlanningContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StoryPlanningSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    func testBookBackgroundPersistsAndEnsureIsIdempotent() throws {
        let container = try makePlanningContainer()
        let store = try StoryPlanningStore(container: container)
        let bookID = UUID()

        let profile = try store.ensureProfile(bookID: bookID)
        profile.backgroundText = "這是一個魔法世界，故事目標是終結黑魔王。"
        profile.updatedAt = Date()
        try store.saveChanges()

        let reloadedStore = try StoryPlanningStore(container: container)
        XCTAssertEqual(reloadedStore.profile(bookID: bookID)?.backgroundText, profile.backgroundText)
        XCTAssertEqual(try reloadedStore.ensureProfile(bookID: bookID).id, profile.id)
        XCTAssertEqual(reloadedStore.bookProfiles.filter { $0.bookID == bookID }.count, 1)
    }

    func testAllStoryLineKindsAndMultipleOptionalLinesCanBeCreated() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()

        for kind in OutlineStoryLineKind.allCases {
            _ = try store.createStoryLine(bookID: bookID, kind: kind)
        }
        _ = try store.createStoryLine(bookID: bookID, kind: .prequel)
        _ = try store.createStoryLine(bookID: bookID, kind: .branch)
        _ = try store.createStoryLine(bookID: bookID, kind: .epilogue)

        let lines = store.storyLines(bookID: bookID)
        XCTAssertEqual(Set(lines.map(\.kind)), Set(OutlineStoryLineKind.allCases))
        XCTAssertEqual(lines.filter { $0.kind == .prequel }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .branch }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .epilogue }.count, 2)
    }

    func testMainStoryIsUniqueAndCanHaveAtLeastTwoOrderedStages() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let main = try store.createStoryLine(bookID: bookID, kind: .main)

        let first = try store.createStage(storyLine: main, title: "啟程")
        let second = try store.createStage(storyLine: main, title: "決戰")

        XCTAssertEqual(store.stages(storyLineID: main.id).map(\.id), [first.id, second.id])
        XCTAssertThrowsError(try store.createStoryLine(bookID: bookID, kind: .main))
        XCTAssertThrowsError(try store.createStage(
            storyLine: store.createStoryLine(bookID: main.bookID, kind: .branch)
        ))
    }

    func testOutlineItemsPersistAllStatusesAndManualOrdering() throws {
        let container = try makePlanningContainer()
        let store = try StoryPlanningStore(container: container)
        let line = try store.createStoryLine(bookID: UUID(), kind: .prequel)

        var created: [OutlineItem] = []
        for status in OutlineItemStatus.allCases {
            created.append(try store.createOutlineItem(
                storyLine: line,
                title: status.rawValue,
                status: status
            ))
        }
        created[0].sortOrder = 30
        created[1].sortOrder = 10
        created[2].sortOrder = 20
        created[3].sortOrder = 40
        try store.saveChanges()

        let reloadedStore = try StoryPlanningStore(container: container)
        XCTAssertEqual(Set(reloadedStore.items(storyLineID: line.id).map(\.status)), Set(OutlineItemStatus.allCases))
        XCTAssertEqual(reloadedStore.items(storyLineID: line.id).map(\.sortOrder), [10, 20, 30, 40])
    }

    func testNarrativeAndTimelineQueriesShareOneOutlineItem() throws {
        let container = try makePlanningContainer()
        let store = try StoryPlanningStore(container: container)
        let bookID = UUID()
        let line = try store.createStoryLine(bookID: bookID, kind: .main)
        let stage = try store.createStage(storyLine: line)
        let created = try store.createOutlineItem(storyLine: line, stage: stage, title: "進入禁林")

        let narrativeItem = try XCTUnwrap(store.items(storyLineID: line.id).first)
        let timelineItem = try XCTUnwrap(store.items(bookID: bookID).first)
        XCTAssertTrue(narrativeItem === timelineItem)

        timelineItem.title = "在禁林遇見守門人"
        timelineItem.status = .occurred
        try store.saveChanges()
        XCTAssertEqual(narrativeItem.title, "在禁林遇見守門人")
        XCTAssertEqual(narrativeItem.status, .occurred)
        XCTAssertEqual(store.outlineItems.count, 1)
        XCTAssertEqual(store.outlineItems.first?.id, created.id)
    }

    func testOutlineDoesNotRequireSectionStoryTagOrLegacyTimelineData() throws {
        let container = try makePlanningContainer()
        let store = try StoryPlanningStore(container: container)
        let bookID = UUID()
        let line = try store.createStoryLine(bookID: bookID, kind: .branch)
        _ = try store.createOutlineItem(storyLine: line, title: "沒有正文連結的事件")

        XCTAssertEqual(store.items(bookID: bookID).count, 1)
        XCTAssertTrue(store.tags(bookID: bookID).isEmpty)
        XCTAssertTrue(store.annotations.filter { $0.bookID == bookID }.isEmpty)
    }

    func testV1StoryPlanningStoreMigratesToV2WithoutChangingExistingData() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-story-planning-v1-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }
        let bookID = UUID()
        let sectionID = UUID()
        let tagID = UUID()

        do {
            let v1Schema = Schema(versionedSchema: StoryPlanningSchemaV1.self)
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: [ModelConfiguration(schema: v1Schema, url: storeURL)]
            )
            let tag = StoryTag(
                id: tagID,
                title: "保留的伏筆",
                kind: .foreshadowing,
                anchorText: "古老鑰匙",
                anchorOffset: 8,
                bookID: bookID,
                sectionID: sectionID
            )
            let annotation = ChapterAnnotation(
                sectionID: sectionID,
                bookID: bookID,
                plannedOutline: "進入遺跡",
                revisionNote: "補足動機"
            )
            v1Container.mainContext.insert(tag)
            v1Container.mainContext.insert(annotation)
            try v1Container.mainContext.save()
        }

        let v2Schema = Schema(versionedSchema: StoryPlanningSchemaV2.self)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v2Schema, url: storeURL)]
        )
        let store = try StoryPlanningStore(container: v2Container)

        XCTAssertEqual(store.tags.count, 1)
        XCTAssertEqual(store.tags.first?.id, tagID)
        XCTAssertEqual(store.tags.first?.anchorText, "古老鑰匙")
        XCTAssertEqual(store.annotation(sectionID: sectionID)?.plannedOutline, "進入遺跡")
        XCTAssertEqual(store.annotation(sectionID: sectionID)?.revisionNote, "補足動機")
        XCTAssertTrue(store.storyLines(bookID: bookID).isEmpty)

        _ = try store.ensureProfile(bookID: bookID)
        _ = try store.createStoryLine(bookID: bookID, kind: .main)
        try store.saveChanges()

        let reopened = try ModelContainer(
            for: v2Schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v2Schema, url: storeURL)]
        )
        let reopenedStore = try StoryPlanningStore(container: reopened)
        XCTAssertEqual(reopenedStore.tags.count, 1)
        XCTAssertEqual(reopenedStore.storyLines(bookID: bookID).count, 1)
        XCTAssertEqual(reopenedStore.bookProfiles.filter { $0.bookID == bookID }.count, 1)
    }

    func testFreshV2StoreReopensWithBackgroundAndStableManualOrder() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-story-planning-v2-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }
        let bookID = UUID()
        let lineID: UUID

        do {
            let schema = Schema(versionedSchema: StoryPlanningSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: StoryPlanningMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let store = try StoryPlanningStore(container: container)
            let profile = try store.ensureProfile(bookID: bookID)
            profile.backgroundText = "世界由漂浮群島構成。"
            let line = try store.createStoryLine(bookID: bookID, kind: .branch, title: "群島支線")
            lineID = line.id
            let later = try store.createOutlineItem(storyLine: line, title: "後顯示")
            let earlier = try store.createOutlineItem(storyLine: line, title: "先顯示")
            later.sortOrder = 90
            earlier.sortOrder = 10
            try store.saveChanges()
        }

        let schema = Schema(versionedSchema: StoryPlanningSchemaV2.self)
        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let reopenedStore = try StoryPlanningStore(container: reopened)
        XCTAssertEqual(reopenedStore.profile(bookID: bookID)?.backgroundText, "世界由漂浮群島構成。")
        XCTAssertEqual(reopenedStore.items(storyLineID: lineID).map(\.title), ["先顯示", "後顯示"])
        XCTAssertEqual(reopenedStore.items(storyLineID: lineID).map(\.sortOrder), [10, 90])
    }

    private func removeStoreFiles(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
