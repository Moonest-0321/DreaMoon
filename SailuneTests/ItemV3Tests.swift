import XCTest
import SwiftData
@testable import Sailune

@MainActor
final class ItemV3Tests: XCTestCase {
    func testCalendarDatesAndEditedEventsSurviveReopeningStore() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Sailune-calendar-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        func openStore() throws -> ModelContainer {
            let schema = Schema(versionedSchema: NovelWriterSchemaV5.self)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        func writeStore() throws {
            let container = try openStore()
            let context = container.mainContext
            let book = Book(title: "重開測試", author: "作者")
            context.insert(book)
            try TimelineEngine.Bootstrap.ensure(for: book, in: context)
            let axis = try TimelineEngine.addSecondaryTimeline(for: book, name: "前史", in: context)
            let node = Node(year: -3, month: 2)
            context.insert(node)
            node.timeline = axis
            node.era = book.currentEra
            let event = Event(title: "原標題", detail: "原內容")
            context.insert(event)
            event.node = node
            try context.save()
            event.title = "更新標題"
            event.detail = "更新內容"
            event.isVisible = false
            try context.save()
        }
        try writeStore()
        let reopened = try openStore()
        let book = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Book>()).first)
        XCTAssertEqual(book.timelines.count, 2)
        let node = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Node>()).first)
        XCTAssertEqual(node.year, -3)
        XCTAssertEqual(node.month, 2)
        XCTAssertNil(node.day)
        XCTAssertEqual(node.timeline?.name, "前史")
        XCTAssertEqual(node.era?.id, book.currentEra?.id)
        let event = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Event>()).first)
        XCTAssertEqual(event.node?.id, node.id)
        XCTAssertEqual(event.title, "更新標題")
        XCTAssertEqual(event.detail, "更新內容")
        XCTAssertFalse(event.isVisible)
    }

    func testCalendarProjectionGroupsDatesAndKeepsErasSeparate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let era = Era(name: "第一紀元")
        let otherEra = Era(name: "另一紀元")
        context.insert(era)
        context.insert(otherEra)
        let nodes = [Node(year: 1), Node(year: 1, month: 2), Node(year: 1, month: 2, day: 3), Node(year: 1, month: 2, day: 4), Node(year: 0), Node(year: 1)]
        for node in nodes { context.insert(node); node.era = era }
        nodes[5].era = otherEra
        let event = Event(title: "事件", detail: "")
        context.insert(event)
        event.node = nodes[2]
        try context.save()
        let yearCells = TimelineDateProjection.cells(nodes: nodes, events: [event], primary: true, granularity: .year)
        XCTAssertEqual(yearCells.count, 2)
        XCTAssertEqual(Set(yearCells.compactMap(\.eraID)), Set([era.id, otherEra.id]))
        XCTAssertFalse(yearCells.flatMap(\.nodes).contains { $0.year == 0 })
        XCTAssertEqual(TimelineDateProjection.cells(nodes: Array(nodes.prefix(4)), events: [event], primary: true, granularity: .month).count, 2)
        XCTAssertEqual(TimelineDateProjection.cells(nodes: Array(nodes.prefix(4)), events: [event], primary: true, granularity: .day).count, 4)
        event.isVisible = false
        XCTAssertTrue(TimelineDateProjection.cells(nodes: nodes, events: [event], primary: true, granularity: .day).flatMap(\.events).isEmpty)
        XCTAssertEqual(TimelineDateProjection.cells(nodes: nodes, events: [event], primary: false, granularity: .day).flatMap(\.events).count, 1)
        nodes[2].isVisible = false
        XCTAssertFalse(TimelineDateProjection.cells(nodes: nodes, events: [event], primary: true, granularity: .day).flatMap(\.nodes).contains { $0.id == nodes[2].id })
    }

    func testTimelineBootstrapAndEraChangeKeepExistingDates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "曆法測試", author: "作者")
        context.insert(book)
        try TimelineEngine.Bootstrap.ensure(for: book, in: context)
        let primary = try XCTUnwrap(TimelineEngine.Query.primaryTimeline(for: book))
        let era = try XCTUnwrap(book.currentEra)
        try TimelineEngine.Bootstrap.ensure(for: book, in: context)
        XCTAssertEqual(book.timelines.count, 1)
        XCTAssertEqual(book.currentEra?.id, era.id)
        let node = Node(year: 12, month: nil, day: nil)
        context.insert(node)
        node.timeline = primary
        node.era = era
        try context.save()
        let result = try TimelineEngine.EraChange.perform(for: book, input: .init(newName: "新紀元", newColor: "#2980B9"), in: context)
        XCTAssertEqual(result.era.startOrdinal, era.startOrdinal + 12)
        XCTAssertEqual(node.year, 12)
        XCTAssertNil(node.month)
        XCTAssertEqual(node.era?.id, era.id)
        XCTAssertEqual(result.node.year, 1)
        XCTAssertEqual(result.node.timeline?.id, primary.id)
    }

    func testTimelineDeletionPreservesOtherAxisAndProse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "刪除測試", author: "作者")
        context.insert(book)
        try TimelineEngine.Bootstrap.ensure(for: book, in: context)
        let primary = try XCTUnwrap(TimelineEngine.Query.primaryTimeline(for: book))
        let secondary = try TimelineEngine.addSecondaryTimeline(for: book, name: "前史", in: context)
        let section = Section(title: "正文", content: AttributedString("保留文字"))
        context.insert(section)
        let first = Node(year: 1)
        let second = Node(year: 2, month: 3, day: 4)
        context.insert(first)
        context.insert(second)
        first.timeline = primary
        second.timeline = secondary
        second.section = section
        let event = Event(title: "副軸事件", detail: "內容")
        context.insert(event)
        event.node = second
        try context.save()
        let firstID = first.id
        let sectionID = section.id
        try PersistentModelDeletion.deleteTimeline(secondary, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Node>()).map(\.id), [firstID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Event>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Section>()).first?.id, sectionID)
        XCTAssertEqual(String(section.content.characters), "保留文字")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(
            NovelWriterSchemaV5.models + [
                ItemCopy.self, ItemCopyHolding.self, ItemCopyHistory.self,
                ItemCopyLevelSelection.self
            ]
        )
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makePlanningContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StoryPlanningSchemaV5.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: StoryPlanningMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func createV5Store(at url: URL) throws {
        let schema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = container.mainContext
        let book = Book(title: "遷移測試", author: "作者")
        let character = Character(realName: "持有人", book: book)
        let item = Item(name: "制式藥水", book: book)
        context.insert(book)
        context.insert(character)
        context.insert(item)
        context.insert(CharacterItem(quantity: 2, character: character, item: item))
        try context.save()
    }

    func testExistingV5StoreOpensUnchangedBesideCopyStore() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let identifier = UUID().uuidString
        let mainURL = directory.appendingPathComponent("Sailune-v5-main-\(identifier).store")
        let copyURL = directory.appendingPathComponent("Sailune-v5-copies-\(identifier).store")
        defer {
            for url in [mainURL, copyURL] {
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.removeItem(atPath: url.path + suffix)
                }
            }
        }

        try createV5Store(at: mainURL)

        let mainSchema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        let copySchema = Schema(versionedSchema: ItemCopySchemaV1.self)
        let mainContainer: ModelContainer
        let copyContainer: ModelContainer
        do {
            mainContainer = try ModelContainer(
                for: mainSchema,
                configurations: [ModelConfiguration(schema: mainSchema, url: mainURL)]
            )
            copyContainer = try ModelContainer(
                for: copySchema,
                configurations: [ModelConfiguration(schema: copySchema, url: copyURL)]
            )
        } catch {
            let nsError = error as NSError
            XCTFail("V5 主庫與副本庫共同載入失敗：\(nsError.domain) \(nsError.code) \(nsError.userInfo)")
            return
        }
        try V6ItemCopyBackfill.run(
            source: mainContainer.mainContext,
            destination: copyContainer.mainContext
        )

        XCTAssertEqual(try mainContainer.mainContext.fetchCount(FetchDescriptor<Item>()), 1)
        XCTAssertEqual(try mainContainer.mainContext.fetchCount(FetchDescriptor<CharacterItem>()), 1)
        XCTAssertEqual(try copyContainer.mainContext.fetchCount(FetchDescriptor<ItemCopy>()), 2)
        XCTAssertEqual(try copyContainer.mainContext.fetchCount(FetchDescriptor<ItemCopyHolding>()), 2)
    }

    func testStoryTagKeepsItsAnchorWhenTextIsInsertedBeforeIt() throws {
        let tag = StoryTag(
            title: "小黑回到了家中",
            kind: .main,
            anchorText: "小黑回到了家中",
            anchorOffset: 3,
            bookID: UUID(),
            sectionID: UUID()
        )
        let rewritten = "前言。新的段落。小黑回到了家中，雨還沒有停。"
        XCTAssertEqual(tag.resolvedOffset(in: rewritten), (rewritten as NSString).range(of: "小黑回到了家中").location)
    }

    func testStoryTagKindsOnlyExposeForeshadowingAndRevision() {
        XCTAssertTrue(StoryTagKind.allCases.contains(.revision))
        XCTAssertTrue(StoryTagKind.allCases.contains(.foreshadowing))
        XCTAssertFalse(StoryTagKind.allCases.contains(.plannedAddition))
        XCTAssertEqual(StoryTagKind.revision.rawValue, "修改")
        XCTAssertEqual(StoryTagKind.plannedAddition.rawValue, "計劃加入")
    }

    func testStoryTagMarkerRangesFollowTheirKind() {
        let selectedText = "這是一段完整反白的文字"
        let selectionLength = (selectedText as NSString).length
        let common = (anchorText: selectedText, anchorOffset: 0, bookID: UUID(), sectionID: UUID())

        for kind in [StoryTagKind.revision] {
            let tag = StoryTag(title: kind.rawValue, kind: kind, anchorText: common.anchorText, anchorOffset: common.anchorOffset, bookID: common.bookID, sectionID: common.sectionID)
            XCTAssertEqual(tag.markerLength(availableFromOffset: 100), selectionLength)
        }

        for kind in [StoryTagKind.main, .branch, .foreshadowing, .plannedAddition] {
            let tag = StoryTag(title: kind.rawValue, kind: kind, anchorText: common.anchorText, anchorOffset: common.anchorOffset, bookID: common.bookID, sectionID: common.sectionID)
            XCTAssertEqual(tag.markerLength(availableFromOffset: 100), 1)
        }
    }

    func testStoryTagPersistsWithItsSectionAndClassification() throws {
        let container = try makePlanningContainer()
        let context = container.mainContext
        let bookID = UUID()
        let sectionID = UUID()
        let tag = StoryTag(title: "小黑回到了家中", kind: .foreshadowing, anchorText: "小黑", anchorOffset: 0, bookID: bookID, sectionID: sectionID)
        context.insert(tag)
        try context.save()

        let tags = try context.fetch(FetchDescriptor<StoryTag>())
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.kind, .foreshadowing)
        XCTAssertEqual(tags.first?.bookID, bookID)
        XCTAssertEqual(tags.first?.sectionID, sectionID)
    }

    func testSectionPersistsPlannedOutlineAndRevisionNote() throws {
        let container = try makePlanningContainer()
        let context = container.mainContext
        let sectionID = UUID()
        let annotation = ChapterAnnotation(sectionID: sectionID, bookID: UUID(), plannedOutline: "角色抵達舊宅", revisionNote: "補上雨夜氣氛")
        context.insert(annotation)
        try context.save()

        let saved = try context.fetch(FetchDescriptor<ChapterAnnotation>()).first
        XCTAssertEqual(saved?.plannedOutline, "角色抵達舊宅")
        XCTAssertEqual(saved?.revisionNote, "補上雨夜氣氛")
    }

    func testAddingCopyKeepsOneSharedItemAndIndependentName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let item = Item(
            name: "霜紋長劍",
            itemDescription: "概要",
            category: "武器",
            appearanceAndMaterial: "深銀色劍身",
            usage: "近身戰鬥",
            book: book
        )
        context.insert(book)
        context.insert(item)
        let first = ItemCopyOperations.create(for: item, existingCopies: [], context: context)
        let second = ItemCopyOperations.create(for: item, existingCopies: [first], context: context, name: "守衛隊長之劍")
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ItemCopy>()), 2)
        XCTAssertEqual(first.displayName(for: item), "霜紋長劍")
        XCTAssertEqual(second.displayName(for: item), "守衛隊長之劍")
        XCTAssertEqual(second.sortOrder, 1)
    }

    func testCopyKeepsItsParentItemAndManualLevel() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let firstItem = Item(name: "短劍", book: book)
        let firstLevel = ItemLevel(itemID: firstItem.id, name: "初始")
        let holder = Character(realName: "艾琳", book: book)
        context.insert(book)
        context.insert(firstItem)
        context.insert(firstLevel)
        context.insert(holder)
        try context.save()

        let store = try ItemCopyStore(container: container)
        let copy = store.createCopy(itemID: firstItem.id, name: "艾琳的劍", holderID: holder.id)
        let history = store.addHistory(copyID: copy.id, content: "在遺跡中取得。")
        store.setCurrentLevel(copyID: copy.id, levelID: firstLevel.id)
        XCTAssertEqual(store.currentLevelID(for: copy.id), firstLevel.id)

        XCTAssertEqual(copy.itemID, firstItem.id)
        XCTAssertEqual(copy.name, "艾琳的劍")
        XCTAssertEqual(store.holdings.first(where: { $0.copyID == copy.id })?.characterID, holder.id)
        XCTAssertEqual(store.histories.first(where: { $0.id == history.id })?.content, "在遺跡中取得。")
        XCTAssertEqual(store.currentLevelID(for: copy.id), firstLevel.id)
        XCTAssertTrue(store.copies.contains { $0.id == copy.id && $0.itemID == firstItem.id })
    }

    func testDeletingLevelClearsCurrentLevelImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = Item(name: "短劍")
        let level = ItemLevel(itemID: item.id, name: "初始")
        context.insert(item)
        context.insert(level)
        try context.save()

        let store = try ItemCopyStore(container: container)
        let copy = store.createCopy(itemID: item.id)
        store.setCurrentLevel(copyID: copy.id, levelID: level.id)
        store.clearCurrentLevelSelections(levelID: level.id)

        XCTAssertNil(store.currentLevelID(for: copy.id))
    }

    func testDeletingCharacterImmediatelyReleasesTheirCopies() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = Item(name: "短劍")
        let deletedCharacter = Character(realName: "艾琳")
        let remainingCharacter = Character(realName: "洛恩")
        context.insert(item)
        context.insert(deletedCharacter)
        context.insert(remainingCharacter)
        try context.save()

        let store = try ItemCopyStore(container: container)
        let releasedCopy = store.createCopy(itemID: item.id, holderID: deletedCharacter.id)
        let retainedCopy = store.createCopy(itemID: item.id, holderID: remainingCharacter.id)

        store.removeHoldings(characterID: deletedCharacter.id)

        XCTAssertNil(store.holdings.first(where: { $0.copyID == releasedCopy.id }))
        XCTAssertEqual(
            store.holdings.first(where: { $0.copyID == retainedCopy.id })?.characterID,
            remainingCharacter.id
        )
        XCTAssertTrue(store.copies.contains { $0.id == releasedCopy.id })
    }

    func testDeletingBookImmediatelyRemovesItsCopies() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let item = Item(name: "短劍", book: book)
        context.insert(book)
        context.insert(item)
        try context.save()

        let store = try ItemCopyStore(container: container)
        let copy = store.createCopy(itemID: item.id)

        try PersistentModelDeletion.deleteBook(book, in: context, copyStore: store)

        XCTAssertFalse(store.copies.contains { $0.id == copy.id })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ItemCopy>()), 0)
    }

    func testCopiesCanMoveWithoutChangingTheirParentItem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = Item(name: "短劍")
        context.insert(item)
        try context.save()

        let store = try ItemCopyStore(container: container)
        let first = store.createCopy(itemID: item.id, name: "第一把")
        let second = store.createCopy(itemID: item.id, name: "第二把")
        store.moveCopy(second, by: -1)

        XCTAssertEqual(store.copies.filter { $0.itemID == item.id }.map(\.id), [second.id, first.id])
        XCTAssertEqual(first.itemID, item.id)
        XCTAssertEqual(second.itemID, item.id)
    }

    func testLevelContentDoesNotChangeMainItemName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = Item(name: "主要名稱")
        let level = ItemLevel(itemID: item.id, name: "完全體", itemName: "階段名稱")
        context.insert(item)
        context.insert(level)
        level.itemName = "新的階段名稱"
        level.ability = "新的能力"
        level.cost = "新的代價"
        try context.save()

        XCTAssertEqual(item.name, "主要名稱")
    }

    func testInvalidHoldingQuantityIsNormalized() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = Item(name: "藥水")
        let character = Character(realName: "角色")
        let holding = CharacterItem(quantity: 0, character: character, item: item)
        context.insert(item)
        context.insert(character)
        context.insert(holding)
        try context.save()

        try V5DataBackfill.removeOrphanedItemLevels(in: context)

        XCTAssertEqual(holding.quantity, 1)
    }

    func testBackfillRepairsRequiredTextAndRemovesOnlyOrphanLevels() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = Item(name: "   ")
        let validLevel = ItemLevel(itemID: item.id, name: "\n")
        let orphanLevel = ItemLevel(itemID: UUID(), name: "孤兒")
        let history = ItemHistory(content: "  ", item: item)
        context.insert(item)
        context.insert(validLevel)
        context.insert(orphanLevel)
        context.insert(history)
        try context.save()

        try V5DataBackfill.removeOrphanedItemLevels(in: context)

        XCTAssertEqual(item.name, "未命名物品")
        XCTAssertEqual(validLevel.name, "未命名等級")
        XCTAssertEqual(history.content, "未填寫描述")
        let levels = try context.fetch(FetchDescriptor<ItemLevel>())
        XCTAssertEqual(Set(levels.map(\.id)), Set([validLevel.id]))
    }

    func testLegacyQuantityBecomesIndependentCopies() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let holder = Character(realName: "艾琳", book: book)
        let source = Item(name: "治療藥水", book: book)
        let holding = CharacterItem(quantity: 3, character: holder, item: source)
        let history = ItemHistory(content: "在藥房取得。", item: source, relatedCharacters: [holder])
        context.insert(book)
        context.insert(holder)
        context.insert(source)
        context.insert(holding)
        context.insert(history)
        try context.save()

        try V6ItemCopyBackfill.run(source: context, destination: context)

        let copies = try context.fetch(FetchDescriptor<ItemCopy>()).filter { $0.itemID == source.id }
        let copyIDs = Set(copies.map(\.id))
        let copyHoldings = try context.fetch(FetchDescriptor<ItemCopyHolding>()).filter { copyIDs.contains($0.copyID) }
        let histories = try context.fetch(FetchDescriptor<ItemCopyHistory>()).filter { copyIDs.contains($0.copyID) }
        XCTAssertEqual(copies.count, 3)
        XCTAssertEqual(copyHoldings.count, 3)
        XCTAssertTrue(copyHoldings.allSatisfy { $0.characterID == holder.id })
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(histories.first?.copyID, copies.sorted { $0.sortOrder < $1.sortOrder }.first?.id)
        XCTAssertEqual(histories.first?.content, "在藥房取得。")
    }

    func testMultipleHoldersAndUnifiedHistoryPersistTogether() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let firstCharacter = Character(realName: "洛恩", book: book)
        let secondCharacter = Character(realName: "艾琳", book: book)
        let item = Item(name: "霜紋長劍", book: book)
        let firstHolding = CharacterItem(quantity: 1, character: firstCharacter, item: item)
        let secondHolding = CharacterItem(quantity: 3, character: secondCharacter, item: item)
        let node = Node(year: 417)
        let history = ItemHistory(
            content: "洛恩將長劍交給艾琳保管。",
            node: node,
            item: item,
            relatedCharacters: [firstCharacter, secondCharacter]
        )
        context.insert(book)
        context.insert(firstCharacter)
        context.insert(secondCharacter)
        context.insert(item)
        context.insert(firstHolding)
        context.insert(secondHolding)
        context.insert(node)
        context.insert(history)
        try context.save()

        XCTAssertEqual(Set(item.characterItems.map(\.quantity)), Set([1, 3]))
        XCTAssertEqual(Set(history.relatedCharacters.map(\.realName)), Set(["洛恩", "艾琳"]))
        XCTAssertEqual(history.node?.year, 417)
        XCTAssertEqual(item.histories.map(\.id), [history.id])
    }

    func testWritingReferencesRemainOnSharedItemDefinition() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let volume = Volume(title: "第一卷", book: book)
        let section = Section(title: "冰原遺跡", content: AttributedString("洛恩在遺跡中找到霜紋長劍。"), volume: volume)
        let item = Item(name: "霜紋長劍", book: book)
        book.volumes.append(volume)
        volume.sections.append(section)
        context.insert(book)
        context.insert(volume)
        context.insert(section)
        context.insert(item)

        let copy = ItemCopyOperations.create(for: item, existingCopies: [], context: context, name: "洛恩之劍")
        try context.save()

        XCTAssertEqual(WritingReferenceScanner.sections(for: item, in: book).map(\.id), [section.id])
        XCTAssertEqual(copy.displayName(for: item), "洛恩之劍")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
    }

    func testLevelCompactOverviewUsesExistingFieldsOnly() throws {
        let level = ItemLevel(
            itemID: UUID(),
            name: "覺醒",
            itemName: "霜紋長劍",
            ability: "提高寒冷耐受力",
            cost: "持續消耗體力",
            note: "劍身出現白色紋路"
        )

        XCTAssertEqual(
            level.compactOverview,
            "名稱：霜紋長劍 · 能力：提高寒冷耐受力 · 代價：持續消耗體力 · 其他：劍身出現白色紋路"
        )
        XCTAssertEqual(ItemLevel(itemID: UUID(), name: "初始").compactOverview, "尚未填寫概述")
    }
}
