import XCTest
import SwiftData
@testable import Sailune

@MainActor
final class V42OutlineTests: XCTestCase {
    private func makePlanningContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StoryPlanningSchemaV4.self)
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

    func testBookBackgroundGuidanceFieldsPersistWithExistingFreeformText() throws {
        let container = try makePlanningContainer()
        let store = try StoryPlanningStore(container: container)
        let bookID = UUID()
        let profile = try store.ensureProfile(bookID: bookID)
        var content = StoryBackgroundContent()
        content.worldBackground = "浮空群島"
        content.premise = "失去魔法的巫師踏上旅程"
        content.mainConflict = "王國即將墜落"
        content.protagonistGoal = "找回天空之核"
        content.coreTheme = "信任"
        content.otherBackground = "保留原有的自由背景筆記。"
        profile.backgroundText = content.encodedValue()
        try store.saveChanges()

        let reloaded = try XCTUnwrap(StoryPlanningStore(container: container).profile(bookID: bookID))
        let restored = StoryBackgroundContent(storedValue: reloaded.backgroundText)
        XCTAssertEqual(restored.worldBackground, "浮空群島")
        XCTAssertEqual(restored.premise, "失去魔法的巫師踏上旅程")
        XCTAssertEqual(restored.mainConflict, "王國即將墜落")
        XCTAssertEqual(restored.protagonistGoal, "找回天空之核")
        XCTAssertEqual(restored.coreTheme, "信任")
        XCTAssertEqual(restored.otherBackground, "保留原有的自由背景筆記。")
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
        for status in OutlineItemStatus.allCases.filter({ $0 != .occurred }) {
            created.append(try store.createOutlineItem(
                storyLine: line,
                title: status.rawValue,
                status: status
            ))
        }
        created[0].sortOrder = 30
        created[1].sortOrder = 10
        created[2].sortOrder = 20
        try store.saveChanges()

        let reloadedStore = try StoryPlanningStore(container: container)
        XCTAssertEqual(Set(reloadedStore.items(storyLineID: line.id).map(\.status)), Set(OutlineItemStatus.allCases.filter { $0 != .occurred }))
        XCTAssertEqual(reloadedStore.items(storyLineID: line.id).map(\.sortOrder), [10, 20, 30])
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
        timelineItem.status = .planned
        try store.saveChanges()
        XCTAssertEqual(narrativeItem.title, "在禁林遇見守門人")
        XCTAssertEqual(narrativeItem.status, .planned)
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

    func testCreatingStructuralOutlineFromProseCreatesExpectedLinesStatusesAndAnchors() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let sectionID = UUID()

        let main = try store.createOutlineItemFromProse(
            kind: .main, title: "王城陷落", anchorText: "王城陷落", anchorOffset: 3, bookID: bookID, sectionID: sectionID
        )
        let branch = try store.createOutlineItemFromProse(
            kind: .branch, title: "尋找密道", anchorText: "尋找密道", anchorOffset: 18, bookID: bookID, sectionID: sectionID
        )
        let draft = try store.createOutlineItemFromProse(
            kind: .plannedAddition, title: "補寫回憶", anchorText: "補寫回憶", anchorOffset: 31, bookID: bookID, sectionID: sectionID
        )

        XCTAssertEqual(store.storyLines(bookID: bookID).filter { $0.kind == .main }.count, 1)
        XCTAssertEqual(store.storyLines(bookID: bookID).filter { $0.kind == .branch }.count, 1)
        XCTAssertEqual(store.items(bookID: bookID).first(where: { $0.id == main.id })?.status, .occurred)
        XCTAssertEqual(store.items(bookID: bookID).first(where: { $0.id == branch.id })?.status, .occurred)
        XCTAssertEqual(store.items(bookID: bookID).first(where: { $0.id == draft.id })?.status, .draft)
        XCTAssertEqual(store.anchor(outlineItemID: draft.id)?.sectionID, sectionID)
        XCTAssertEqual(store.anchor(outlineItemID: draft.id)?.resolvedOffset(in: "前言。補寫回憶。"), 3)
        XCTAssertTrue(store.tags(bookID: bookID).isEmpty)
    }

    func testAnchoredItemsSortBySectionThenCurrentProseOffsetBeforeManualItems() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let firstSection = Section(id: UUID(), title: "第一節", content: AttributedString("甲乙丙丁"))
        let secondSection = Section(id: UUID(), title: "第二節", content: AttributedString("戊己庚辛"))
        let later = try store.createOutlineItemFromProse(kind: .main, title: "第二節", anchorText: "戊", anchorOffset: 0, bookID: bookID, sectionID: secondSection.id)
        let earlierInFirst = try store.createOutlineItemFromProse(kind: .main, title: "第一節後", anchorText: "丙", anchorOffset: 2, bookID: bookID, sectionID: firstSection.id)
        let earliest = try store.createOutlineItemFromProse(kind: .main, title: "第一節前", anchorText: "甲", anchorOffset: 0, bookID: bookID, sectionID: firstSection.id)
        let main = try XCTUnwrap(store.storyLines(bookID: bookID).first)
        let manual = try store.createOutlineItem(storyLine: main, title: "手動項目")

        XCTAssertEqual(
            store.orderedItems(storyLineID: main.id, stageID: nil, sections: [firstSection, secondSection]).map(\.id),
            [earliest.id, earlierInFirst.id, later.id, manual.id]
        )
    }

    func testProseItemsChooseStageUsingEarliestStageSourcePosition() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let section = Section(id: UUID(), title: "第一節", content: AttributedString("0123456789abcdefghij"))
        let main = try store.createStoryLine(bookID: bookID, kind: .main)
        let firstStage = try store.createStage(
            storyLine: main,
            title: "前段",
            start: OutlineStageStartLocation(volumeID: UUID(), sectionID: section.id, volumeTitle: "第一幕", sectionTitle: "第一節")
        )
        let laterSection = Section(id: UUID(), title: "第二節", content: AttributedString("abcdefghij"))
        let secondStage = try store.createStage(
            storyLine: main,
            title: "後段",
            start: OutlineStageStartLocation(volumeID: UUID(), sectionID: laterSection.id, volumeTitle: "第一幕", sectionTitle: "第二節")
        )
        let firstStart = try store.createOutlineItemFromProse(
            kind: .main, title: "前段開始", anchorText: "2", anchorOffset: 2, bookID: bookID, sectionID: section.id, sections: [section, laterSection]
        )
        try store.moveOutlineItem(firstStart, to: firstStage)
        let secondStart = try store.createOutlineItemFromProse(
            kind: .main, title: "後段開始", anchorText: "a", anchorOffset: 0, bookID: bookID, sectionID: laterSection.id, sections: [section, laterSection]
        )
        try store.moveOutlineItem(secondStart, to: secondStage)

        let beforeSecond = try store.createOutlineItemFromProse(
            kind: .main, title: "前段內容", anchorText: "5", anchorOffset: 5, bookID: bookID, sectionID: section.id, sections: [section, laterSection]
        )
        let afterSecond = try store.createOutlineItemFromProse(
            kind: .main, title: "後段內容", anchorText: "f", anchorOffset: 5, bookID: bookID, sectionID: laterSection.id, sections: [section, laterSection]
        )

        XCTAssertEqual(beforeSecond.stageID, firstStage.id)
        XCTAssertEqual(afterSecond.stageID, secondStage.id)
    }

    func testDeletingStageAlsoDeletesItsItemsAndAnchors() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let main = try store.createStoryLine(bookID: bookID, kind: .main)
        let stage = try store.createStage(storyLine: main, title: "第一階段")
        let manual = try store.createOutlineItem(storyLine: main, stage: stage, title: "手動")
        let anchored = try store.createOutlineItemFromProse(kind: .main, title: "正文來源", anchorText: "正文來源", anchorOffset: 0, bookID: bookID, sectionID: UUID())
        try store.moveOutlineItem(anchored, to: stage)

        try store.deleteStage(stage)

        XCTAssertTrue(store.stages(storyLineID: main.id).isEmpty)
        XCTAssertFalse(store.items(bookID: bookID).contains { $0.id == manual.id })
        XCTAssertFalse(store.items(bookID: bookID).contains { $0.id == anchored.id })
        XCTAssertNil(store.anchor(outlineItemID: anchored.id))
    }

    func testManualItemsCannotUseCompletedStatus() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let line = try store.createStoryLine(bookID: UUID(), kind: .branch)

        XCTAssertThrowsError(try store.createOutlineItem(storyLine: line, status: .occurred))
        let item = try store.createOutlineItem(storyLine: line, status: .draft)
        XCTAssertThrowsError(try store.setManualStatus(item, to: .occurred))
        XCTAssertEqual(item.status, .draft)
    }

    func testManualPlacementFollowsTargetAndReturnsPendingWhenTargetIsDeleted() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let section = Section(id: UUID(), title: "第一節", content: AttributedString("正文"))
        let main = try store.createStoryLine(bookID: bookID, kind: .main)
        let stage = try store.createStage(storyLine: main)
        let prose = try store.createOutlineItemFromProse(
            kind: .main, title: "正文項目", anchorText: "正文", anchorOffset: 0, bookID: bookID, sectionID: section.id, sections: [section]
        )
        try store.moveOutlineItem(prose, to: stage)
        let manual = try store.createOutlineItem(storyLine: main, stage: stage, title: "手動項目")
        try store.setPlacement(manual, kind: .afterItem, after: prose)

        XCTAssertEqual(store.orderedItems(storyLineID: main.id, stageID: stage.id, sections: [section]).map(\.id), [prose.id, manual.id])
        try store.deleteOutlineItem(prose)
        XCTAssertEqual(store.placement(outlineItemID: manual.id)?.kind, .pending)
        XCTAssertEqual(store.placement(outlineItemID: manual.id)?.relativeItemTitleSnapshot, "正文項目")
    }

    func testV3StoreMigratesToV4WithoutCreatingStageStartsOrManualPlacements() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-story-planning-v3-v4-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }
        let bookID = UUID()
        let stageID: UUID
        let itemID: UUID

        do {
            let schema = Schema(versionedSchema: StoryPlanningSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
            let context = container.mainContext
            let line = OutlineStoryLine(bookID: bookID, title: "主線", kind: .main)
            let stage = OutlineStage(bookID: bookID, storyLineID: line.id, title: "階段 1")
            let item = OutlineItem(bookID: bookID, storyLineID: line.id, stageID: stage.id, title: "舊手動項目")
            context.insert(line)
            context.insert(stage)
            context.insert(item)
            try context.save()
            stageID = stage.id
            itemID = item.id
        }

        let schema = Schema(versionedSchema: StoryPlanningSchemaV4.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let store = try StoryPlanningStore(container: container)
        XCTAssertNotNil(store.stages(storyLineID: store.storyLines(bookID: bookID)[0].id).first(where: { $0.id == stageID }))
        XCTAssertNotNil(store.items(bookID: bookID).first(where: { $0.id == itemID }))
        XCTAssertNil(store.stageStart(stageID: stageID))
        XCTAssertNil(store.placement(outlineItemID: itemID))
        let item = try XCTUnwrap(store.items(bookID: bookID).first(where: { $0.id == itemID }))
        XCTAssertEqual(store.orderedItems(storyLineID: item.storyLineID, stageID: stageID, sections: []).map(\.id), [itemID])
        try store.setPlacement(item, kind: .stageStart)
        let reopened = try StoryPlanningStore(container: container)
        XCTAssertEqual(reopened.placement(outlineItemID: itemID)?.kind, .stageStart)
    }

    func testSiblingPlacementReorderingPreservesChildren() throws {
        let container = try makePlanningContainer()
        let store = try StoryPlanningStore(container: container)
        let line = try store.createStoryLine(bookID: UUID(), kind: .branch)
        let first = try store.createOutlineItem(storyLine: line)
        let second = try store.createOutlineItem(storyLine: line)
        let child = try store.createOutlineItem(storyLine: line)
        try store.setPlacement(first, kind: .stageStart)
        try store.setPlacement(second, kind: .stageStart)
        try store.setPlacement(child, kind: .afterItem, after: first)
        try store.moveManualItem(second, earlier: true)
        let reopened = try StoryPlanningStore(container: container)
        XCTAssertEqual(reopened.orderedItems(storyLineID: line.id, stageID: nil, sections: []).map(\.id), [second.id, first.id, child.id])
        try reopened.moveManualItem(second, earlier: false)
        XCTAssertEqual(reopened.orderedItems(storyLineID: line.id, stageID: nil, sections: []).map(\.id), [first.id, child.id, second.id])
    }

    func testMovingPlacementTargetKeepsDependentsVisibleAndPending() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let line = try store.createStoryLine(bookID: UUID(), kind: .main)
        let first = try store.createStage(storyLine: line)
        let second = try store.createStage(storyLine: line)
        let target = try store.createOutlineItem(storyLine: line, stage: first)
        let child = try store.createOutlineItem(storyLine: line, stage: first)
        try store.setPlacement(child, kind: .afterItem, after: target)
        XCTAssertThrowsError(try store.setPlacement(target, kind: .afterItem, after: child))
        try store.moveOutlineItem(target, to: second)
        XCTAssertEqual(store.placement(outlineItemID: child.id)?.kind, .pending)
        XCTAssertEqual(store.orderedItems(storyLineID: line.id, stageID: first.id, sections: []).map(\.id), [child.id])
    }

    func testProseWithoutMatchingStageFallsBackToLastStage() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let line = try store.createStoryLine(bookID: bookID, kind: .main)
        _ = try store.createStage(storyLine: line)
        let last = try store.createStage(storyLine: line)
        let section = Section(id: UUID(), title: "第一節", content: AttributedString("正文"))
        let item = try store.createOutlineItemFromProse(kind: .main, title: "正文", anchorText: "正文", anchorOffset: 0, bookID: bookID, sectionID: section.id, sections: [section])
        XCTAssertEqual(item.stageID, last.id)
        let unknown = try store.createOutlineItemFromProse(kind: .plannedAddition, title: "未知位置", anchorText: "正文", anchorOffset: 0, bookID: bookID, sectionID: UUID())
        XCTAssertEqual(unknown.stageID, last.id)
    }

    func testProseBeforeAllStartsFallsBackToDisplayedLastStage() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let line = try store.createStoryLine(bookID: bookID, kind: .main)
        let early = Section(id: UUID(), title: "前", content: AttributedString("正文"))
        let middle = Section(id: UUID(), title: "中", content: AttributedString("正文"))
        let late = Section(id: UUID(), title: "後", content: AttributedString("正文"))
        let last = try store.createStage(storyLine: line, start: OutlineStageStartLocation(volumeID: UUID(), sectionID: late.id, volumeTitle: "幕", sectionTitle: late.title))
        _ = try store.createStage(storyLine: line, start: OutlineStageStartLocation(volumeID: UUID(), sectionID: middle.id, volumeTitle: "幕", sectionTitle: middle.title))
        let item = try store.createOutlineItemFromProse(kind: .main, title: "正文", anchorText: "正文", anchorOffset: 0, bookID: bookID, sectionID: early.id, sections: [early, middle, late])
        XCTAssertEqual(item.stageID, last.id)
    }

    func testDeletingOutlineItemAlsoDeletesOnlyItsAnchor() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let sectionID = UUID()
        let anchored = try store.createOutlineItemFromProse(
            kind: .main, title: "有來源", anchorText: "有來源", anchorOffset: 0, bookID: bookID, sectionID: sectionID
        )
        let line = try XCTUnwrap(store.storyLines(bookID: bookID).first)
        let retained = try store.createOutlineItem(storyLine: line, title: "保留項目")

        try store.deleteOutlineItem(anchored)

        XCTAssertNil(store.anchor(outlineItemID: anchored.id))
        XCTAssertFalse(store.items(bookID: bookID).contains { $0.id == anchored.id })
        XCTAssertTrue(store.items(bookID: bookID).contains { $0.id == retained.id })
    }

    func testDeletingStoryLineCascadesStagesItemsAndAnchors() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let main = try store.createStoryLine(bookID: bookID, kind: .main)
        _ = try store.createStage(storyLine: main)
        let mainItem = try store.createOutlineItemFromProse(
            kind: .main, title: "主線來源", anchorText: "主線來源", anchorOffset: 0, bookID: bookID, sectionID: UUID()
        )
        let branchItem = try store.createOutlineItemFromProse(
            kind: .branch, title: "支線來源", anchorText: "支線來源", anchorOffset: 0, bookID: bookID, sectionID: UUID()
        )
        let branch = try XCTUnwrap(store.storyLines(bookID: bookID).first(where: { $0.kind == .branch }))

        try store.deleteStoryLine(main)

        XCTAssertFalse(store.storyLines(bookID: bookID).contains { $0.id == main.id })
        XCTAssertTrue(store.storyLines(bookID: bookID).contains { $0.id == branch.id })
        XCTAssertFalse(store.items(bookID: bookID).contains { $0.id == mainItem.id })
        XCTAssertTrue(store.items(bookID: bookID).contains { $0.id == branchItem.id })
        XCTAssertNil(store.anchor(outlineItemID: mainItem.id))
        XCTAssertNotNil(store.anchor(outlineItemID: branchItem.id))
        XCTAssertTrue(store.stages(storyLineID: main.id).isEmpty)
    }

    func testDeletingForeshadowingAndRevisionTagsKeepsOtherPlanningData() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let bookID = UUID()
        let foreshadowing = store.createTag(title: "伏筆", kind: .foreshadowing, anchorText: "戒指", anchorOffset: 0, bookID: bookID, sectionID: UUID())
        let revision = store.createTag(title: "修改", kind: .revision, anchorText: "段落", anchorOffset: 0, bookID: bookID, sectionID: UUID())
        let item = try store.createOutlineItemFromProse(kind: .main, title: "大綱", anchorText: "大綱", anchorOffset: 0, bookID: bookID, sectionID: UUID())

        try store.deleteStoryTag(foreshadowing)
        try store.deleteStoryTag(revision)

        XCTAssertTrue(store.tags(bookID: bookID).isEmpty)
        XCTAssertTrue(store.items(bookID: bookID).contains { $0.id == item.id })
    }

    func testV2StructuralTagsMigrateToOutlineAndKeepOnlyProseMarkers() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-story-planning-v2-structural-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }
        let bookID = UUID()
        let sectionID = UUID()
        let mainID = UUID()
        let branchID = UUID()
        let draftID = UUID()
        let foreshadowingID = UUID()
        let revisionID = UUID()

        do {
            let schema = Schema(versionedSchema: StoryPlanningSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = container.mainContext
            for tag in [
                StoryTag(id: mainID, title: "主線事件", kind: .main, anchorText: "王城陷落", anchorOffset: 4, bookID: bookID, sectionID: sectionID),
                StoryTag(id: branchID, title: "支線事件", kind: .branch, anchorText: "尋找密道", anchorOffset: 16, bookID: bookID, sectionID: sectionID),
                StoryTag(id: draftID, title: "待補片段", kind: .plannedAddition, anchorText: "未完成場景", anchorOffset: 28, bookID: bookID, sectionID: sectionID),
                StoryTag(id: foreshadowingID, title: "伏筆", kind: .foreshadowing, anchorText: "銀色戒指", anchorOffset: 40, bookID: bookID, sectionID: sectionID),
                StoryTag(id: revisionID, title: "修改", kind: .revision, anchorText: "改寫這段", anchorOffset: 52, bookID: bookID, sectionID: sectionID)
            ] { context.insert(tag) }
            try context.save()
        }

        let v3Schema = Schema(versionedSchema: StoryPlanningSchemaV3.self)
        let v3Container = try ModelContainer(
            for: v3Schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v3Schema, url: storeURL)]
        )
        let store = try StoryPlanningStore(container: v3Container)

        XCTAssertEqual(store.tags(bookID: bookID).map(\.id).sorted(by: { $0.uuidString < $1.uuidString }), [foreshadowingID, revisionID].sorted(by: { $0.uuidString < $1.uuidString }))
        XCTAssertEqual(store.items(bookID: bookID).map(\.id).sorted(by: { $0.uuidString < $1.uuidString }), [mainID, branchID, draftID].sorted(by: { $0.uuidString < $1.uuidString }))
        XCTAssertEqual(store.items(bookID: bookID).first(where: { $0.id == draftID })?.status, .draft)
        XCTAssertEqual(store.items(bookID: bookID).first(where: { $0.id == mainID })?.status, .occurred)
        XCTAssertEqual(store.storyLines(bookID: bookID).filter { $0.kind == .main }.count, 1)
        XCTAssertEqual(store.storyLines(bookID: bookID).filter { $0.kind == .branch }.count, 1)
        XCTAssertEqual(store.anchor(outlineItemID: branchID)?.anchorText, "尋找密道")
        XCTAssertEqual(store.anchor(outlineItemID: branchID)?.anchorOffset, 16)

        let reopened = try ModelContainer(
            for: v3Schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v3Schema, url: storeURL)]
        )
        let reopenedStore = try StoryPlanningStore(container: reopened)
        XCTAssertEqual(reopenedStore.items(bookID: bookID).count, 3)
        XCTAssertEqual(reopenedStore.outlineAnchors.count, 3)
        XCTAssertEqual(reopenedStore.tags(bookID: bookID).count, 2)
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

    func testTimelineLayoutUsesBookSectionsAndKeepsPendingItemsOutOfColumns() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let book = Book(title: "時間軸測試", author: "作者")
        let volume = Volume(title: "第一幕", book: book)
        let firstSection = Section(title: "第一節", content: AttributedString("收到舊信"), sortOrder: 0, volume: volume)
        let secondSection = Section(title: "第二節", content: AttributedString("前往港口"), sortOrder: 1, volume: volume)
        volume.sections = [firstSection, secondSection]
        book.volumes = [volume]

        let main = try store.createStoryLine(bookID: book.id, kind: .main)
        let stage = try store.createStage(
            storyLine: main,
            title: "啟程",
            start: OutlineStageStartLocation(
                volumeID: volume.id,
                sectionID: firstSection.id,
                volumeTitle: volume.title,
                sectionTitle: firstSection.title
            )
        )
        let prose = try store.createOutlineItemFromProse(
            kind: .main,
            title: "收到舊信",
            anchorText: "收到舊信",
            anchorOffset: 0,
            bookID: book.id,
            sectionID: firstSection.id,
            sections: [firstSection, secondSection]
        )
        try store.moveOutlineItem(prose, to: stage)
        let placed = try store.createOutlineItem(storyLine: main, stage: stage, title: "決定出發")
        try store.setPlacement(placed, kind: .afterItem, after: prose)
        let atStart = try store.createOutlineItem(storyLine: main, stage: stage, title: "幕首提示")
        try store.setPlacement(atStart, kind: .stageStart)
        let atEnd = try store.createOutlineItem(storyLine: main, stage: stage, title: "幕末提示")
        try store.setPlacement(atEnd, kind: .stageEnd)
        let pending = try store.createOutlineItem(storyLine: main, stage: stage, title: "尚未安排")

        let layout = store.timelineLayout(book: book)
        XCTAssertEqual(layout.columns.map(\.sectionID), [firstSection.id, secondSection.id])
        let lane = try XCTUnwrap(layout.lanes.first(where: { $0.storyLineID == main.id }))
        XCTAssertEqual(lane.entries.map(\.itemID), [atStart.id, prose.id, placed.id, atEnd.id])
        XCTAssertEqual(lane.entries.map(\.columnIndex), [0, 0, 0, 1])
        XCTAssertEqual(lane.pendingItemIDs, [pending.id])
    }

    func testTimelineLayoutDoesNotGuessPositionForDeletedProseSource() throws {
        let store = try StoryPlanningStore(container: makePlanningContainer())
        let book = Book(title: "失效來源", author: "作者")
        let volume = Volume(title: "第一幕", book: book)
        let section = Section(title: "第一節", sortOrder: 0, volume: volume)
        volume.sections = [section]
        book.volumes = [volume]
        let item = try store.createOutlineItemFromProse(
            kind: .branch,
            title: "來源已刪除",
            anchorText: "文字",
            anchorOffset: 0,
            bookID: book.id,
            sectionID: UUID()
        )

        let layout = store.timelineLayout(book: book)
        let lane = try XCTUnwrap(layout.lanes.first)
        XCTAssertTrue(lane.entries.isEmpty)
        XCTAssertEqual(lane.pendingItemIDs, [item.id])
    }

    private func removeStoreFiles(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
