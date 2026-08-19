import XCTest
import SwiftData
@testable import Sailune

@MainActor
final class ItemV3Tests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testDuplicateCopiesSettingsAndLevelsOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let holder = Character(realName: "持有人", book: book)
        let source = Item(
            name: "霜紋長劍",
            itemDescription: "概要",
            category: "武器",
            appearanceAndMaterial: "深銀色劍身",
            usage: "近身戰鬥",
            positiveAbility: "舊版正向欄位",
            negativeAbility: "舊版負向欄位",
            book: book
        )
        let holding = CharacterItem(quantity: 3, character: holder, item: source)
        let history = ItemHistory(content: "在遺跡中發現。", item: source, relatedCharacters: [holder])
        let first = ItemLevel(itemID: source.id, sortOrder: 0, name: "初始", itemName: "無名鐵劍", ability: "無", cost: "容易損壞", note: "尚無霜紋")
        let second = ItemLevel(itemID: source.id, sortOrder: 1, name: "覺醒", itemName: "霜紋長劍", ability: "耐寒", cost: "消耗體力", note: "出現霜紋")
        context.insert(book)
        context.insert(holder)
        context.insert(source)
        context.insert(holding)
        context.insert(history)
        context.insert(first)
        context.insert(second)
        source.characterItems.append(holding)
        source.histories.append(history)

        let copy = ItemOperations.duplicate(source, levels: [second, first], in: book, context: context)
        try context.save()

        let copiedLevels = try context.fetch(FetchDescriptor<ItemLevel>())
            .filter { $0.itemID == copy.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(copy.category, "武器")
        XCTAssertEqual(copy.appearanceAndMaterial, "深銀色劍身")
        XCTAssertEqual(copy.usage, "近身戰鬥")
        XCTAssertTrue(copy.positiveAbility.isEmpty)
        XCTAssertTrue(copy.negativeAbility.isEmpty)
        XCTAssertEqual(copiedLevels.map(\.name), ["初始", "覺醒"])
        XCTAssertTrue(copy.characterItems.isEmpty)
        XCTAssertTrue(copy.histories.isEmpty)
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

    func testDuplicateNormalizesWhitespaceOnlySourceName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let source = Item(name: "   ", book: book)
        context.insert(book)
        context.insert(source)

        let copy = ItemOperations.duplicate(source, levels: [], in: book, context: context)

        XCTAssertEqual(copy.name, "新物品（副本）")
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

    func testWritingReferencesAreComputedAndNotCopied() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Book(title: "測試小說", author: "作者")
        let volume = Volume(title: "第一卷", book: book)
        let section = Section(title: "冰原遺跡", content: AttributedString("洛恩在遺跡中找到霜紋長劍。"), volume: volume)
        let source = Item(name: "霜紋長劍", book: book)
        book.volumes.append(volume)
        volume.sections.append(section)
        context.insert(book)
        context.insert(volume)
        context.insert(section)
        context.insert(source)

        let copy = ItemOperations.duplicate(source, levels: [], in: book, context: context)
        try context.save()

        XCTAssertEqual(WritingReferenceScanner.sections(for: source, in: book).map(\.id), [section.id])
        XCTAssertTrue(WritingReferenceScanner.sections(for: copy, in: book).isEmpty)
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
