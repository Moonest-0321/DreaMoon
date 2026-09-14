import XCTest
import SwiftData
@testable import Sailune

@MainActor
final class V5SettingsTests: XCTestCase {
    func testSidebarDefaultsIncludeFiveVisibleAndTwoOptionalRows() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let store = V5SettingsStore(container: container)
        let bookID = UUID()

        let rows = store.ensureDefaults(for: bookID)

        XCTAssertEqual(rows.count, SidebarSettingKey.defaultOrder.count)
        XCTAssertEqual(Set(SidebarSettingCatalog.visibleKeys(rows: rows)), Set([.character, .power, .item, .ability, .storyTag]))
        XCTAssertEqual(Set(rows.filter { $0.key?.isDefaultVisible == false }.compactMap(\.key)), Set([.place, .worldTerm]))

        rows.first(where: { $0.key == .character })?.isVisible = false
        try context.save()
        let reloaded = try SidebarSettingCatalog.rows(for: bookID, in: context)
        XCTAssertFalse(SidebarSettingCatalog.visibleKeys(rows: reloaded).contains(.character))
        XCTAssertEqual(try context.fetch(FetchDescriptor<BookSidebarSetting>()).count, rows.count)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerLevel>()).sorted { $0.sortOrder < $1.sortOrder }.map(\.name), ["層級 1", "層級 2"])
    }

    func testPowerGraphStoresCrossLevelEdgesAndRejectsWrongDirection() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let bookID = UUID()
        let allianceLevel = PowerLevel(bookID: bookID, name: "聯盟", sortOrder: 0)
        let countryLevel = PowerLevel(bookID: bookID, name: "國家", sortOrder: 1)
        let localLevel = PowerLevel(bookID: bookID, name: "地方", sortOrder: 2)
        let alliance = PowerUnit(bookID: bookID, name: "聯盟", levelID: allianceLevel.id)
        let countryA = PowerUnit(bookID: bookID, name: "國家 A", levelID: countryLevel.id)
        let countryB = PowerUnit(bookID: bookID, name: "國家 B", levelID: countryLevel.id)
        let province = PowerUnit(bookID: bookID, name: "直屬下層", levelID: localLevel.id)
        [allianceLevel, countryLevel, localLevel].forEach(context.insert)
        [alliance, countryA, countryB, province].forEach(context.insert)
        try context.save()

        var edges: [PowerSubordination] = []
        let levels = [allianceLevel, countryLevel, localLevel]
        try PowerGraphStore.addDirectSubordination(lower: countryA, upper: alliance, bookID: bookID, levels: levels, edges: &edges, context: context)
        try PowerGraphStore.addDirectSubordination(lower: countryB, upper: alliance, bookID: bookID, levels: levels, edges: &edges, context: context)
        try PowerGraphStore.addDirectSubordination(lower: province, upper: alliance, bookID: bookID, levels: levels, edges: &edges, context: context)
        XCTAssertEqual(edges.count, 3)
        XCTAssertEqual(PowerGraphStore.directLowerPowers(of: alliance, edges: edges, powers: [alliance, countryA, countryB, province]).count, 3)
        XCTAssertEqual(PowerGraphStore.directUpperPowers(of: province, edges: edges, powers: [alliance, countryA, countryB, province]).map(\.name), ["聯盟"])

        XCTAssertThrowsError(
            try PowerGraphStore.addDirectSubordination(lower: alliance, upper: province, bookID: bookID, levels: levels, edges: &edges, context: context)
        )
        XCTAssertEqual(edges.count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerSubordination>()).count, 3)
    }

    func testDeletingPowerRemovesOnlyItsDirectEdges() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let bookID = UUID()
        let otherBookID = UUID()
        let upper = PowerUnit(bookID: bookID, name: "上層")
        let deleted = PowerUnit(bookID: bookID, name: "待刪除")
        let lower = PowerUnit(bookID: bookID, name: "下層")
        let unrelatedA = PowerUnit(bookID: otherBookID, name: "其他 A")
        let unrelatedB = PowerUnit(bookID: otherBookID, name: "其他 B")
        [upper, deleted, lower, unrelatedA, unrelatedB].forEach(context.insert)
        let upperEdge = PowerSubordination(bookID: bookID, lowerPowerID: deleted.id, upperPowerID: upper.id)
        let lowerEdge = PowerSubordination(bookID: bookID, lowerPowerID: lower.id, upperPowerID: deleted.id)
        let unrelatedEdge = PowerSubordination(bookID: otherBookID, lowerPowerID: unrelatedA.id, upperPowerID: unrelatedB.id)
        [upperEdge, lowerEdge, unrelatedEdge].forEach(context.insert)
        try context.save()

        try PowerGraphStore.delete(deleted, edges: [upperEdge, lowerEdge, unrelatedEdge], context: context)

        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<PowerUnit>()).map(\.id)), Set([upper.id, lower.id, unrelatedA.id, unrelatedB.id]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerSubordination>()).map(\.id), [unrelatedEdge.id])
    }

    func testHiddenSelectedSettingFallsBackToFirstVisibleSetting() {
        XCTAssertEqual(
            SidebarSettingCatalog.resolvedSelection(.character, visibleKeys: [.power, .item]),
            .power
        )
        XCTAssertEqual(
            SidebarSettingCatalog.resolvedSelection(.item, visibleKeys: [.power, .item]),
            .item
        )
        XCTAssertEqual(
            SidebarSettingCatalog.resolvedSelection(.character, visibleKeys: []),
            .character
        )
    }

    func testLevelCandidatesAllowSkippingIntermediateLevels() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let bookID = UUID()
        let top = PowerLevel(bookID: bookID, name: "聯盟", sortOrder: 0)
        let middle = PowerLevel(bookID: bookID, name: "國家", sortOrder: 1)
        let bottom = PowerLevel(bookID: bookID, name: "地方", sortOrder: 2)
        let alliance = PowerUnit(bookID: bookID, name: "聯邦", levelID: top.id)
        let country = PowerUnit(bookID: bookID, name: "北國", levelID: middle.id)
        let local = PowerUnit(bookID: bookID, name: "北境教會", levelID: bottom.id)
        let unassigned = PowerUnit(bookID: bookID, name: "未分級")
        [top, middle, bottom].forEach(context.insert)
        [alliance, country, local, unassigned].forEach(context.insert)
        try context.save()

        XCTAssertEqual(
            Set(PowerHierarchyStore.upperCandidates(for: local, powers: [alliance, country, local, unassigned], levels: [top, middle, bottom]).map(\.id)),
            Set([alliance.id, country.id])
        )
        XCTAssertEqual(
            Set(PowerHierarchyStore.lowerCandidates(for: alliance, powers: [alliance, country, local, unassigned], levels: [top, middle, bottom]).map(\.id)),
            Set([country.id, local.id])
        )
    }

    func testChangingLevelIsBlockedWithoutChangingExistingRelations() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let bookID = UUID()
        let top = PowerLevel(bookID: bookID, name: "聯盟", sortOrder: 0)
        let middle = PowerLevel(bookID: bookID, name: "國家", sortOrder: 1)
        let bottom = PowerLevel(bookID: bookID, name: "地方", sortOrder: 2)
        let alliance = PowerUnit(bookID: bookID, name: "聯邦", levelID: top.id)
        let country = PowerUnit(bookID: bookID, name: "北國", levelID: middle.id)
        let local = PowerUnit(bookID: bookID, name: "北境", levelID: bottom.id)
        let upperEdge = PowerSubordination(bookID: bookID, lowerPowerID: country.id, upperPowerID: alliance.id)
        let lowerEdge = PowerSubordination(bookID: bookID, lowerPowerID: local.id, upperPowerID: country.id)
        [top, middle, bottom].forEach(context.insert)
        [alliance, country, local].forEach(context.insert)
        [upperEdge, lowerEdge].forEach(context.insert)
        try context.save()

        XCTAssertThrowsError(
            try PowerHierarchyStore.changeLevel(
                of: country,
                to: top,
                bookID: bookID,
                levels: [top, middle, bottom],
                powers: [alliance, country, local],
                edges: [upperEdge, lowerEdge],
                context: context
            )
        )
        XCTAssertEqual(country.levelID, middle.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerSubordination>()).count, 2)
    }

    func testHierarchyConflictDoesNotAlsoSetGlobalPersistenceError() throws {
        let container = try makeMainContainer()
        let store = V5SettingsStore(container: container)
        let context = container.mainContext
        let bookID = UUID()
        let top = PowerLevel(bookID: bookID, name: "聯盟", sortOrder: 0)
        let bottom = PowerLevel(bookID: bookID, name: "國家", sortOrder: 1)
        let alliance = PowerUnit(bookID: bookID, name: "聯邦", levelID: top.id)
        let country = PowerUnit(bookID: bookID, name: "北國", levelID: bottom.id)
        let edge = PowerSubordination(bookID: bookID, lowerPowerID: country.id, upperPowerID: alliance.id)
        [top, bottom].forEach(context.insert)
        [alliance, country].forEach(context.insert)
        context.insert(edge)
        try context.save()

        XCTAssertThrowsError(try store.changeLevel(of: country, to: top, bookID: bookID))
        XCTAssertNil(store.persistenceErrorMessage)
        XCTAssertEqual(country.levelID, bottom.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerSubordination>()).map(\.id), [edge.id])
    }

    func testReorderingLevelsIsAtomicAndUsedLevelCannotBeDeleted() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let bookID = UUID()
        let top = PowerLevel(bookID: bookID, name: "聯盟", sortOrder: 0)
        let bottom = PowerLevel(bookID: bookID, name: "國家", sortOrder: 1)
        let alliance = PowerUnit(bookID: bookID, name: "聯邦", levelID: top.id)
        let country = PowerUnit(bookID: bookID, name: "北國", levelID: bottom.id)
        let edge = PowerSubordination(bookID: bookID, lowerPowerID: country.id, upperPowerID: alliance.id)
        [top, bottom].forEach(context.insert)
        [alliance, country].forEach(context.insert)
        context.insert(edge)
        try context.save()

        XCTAssertThrowsError(
            try PowerHierarchyStore.reorderLevels(
                bookID: bookID,
                orderedIDs: [bottom.id, top.id],
                levels: [top, bottom],
                powers: [alliance, country],
                edges: [edge],
                context: context
            )
        )
        XCTAssertEqual(top.sortOrder, 0)
        XCTAssertEqual(bottom.sortOrder, 1)
        XCTAssertThrowsError(
            try PowerHierarchyStore.deleteLevel(top, bookID: bookID, powers: [alliance, country], context: context)
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerLevel>()).count, 2)
    }

    func testLevelNamesRejectBlankAndCaseInsensitiveDuplicates() throws {
        let container = try makeMainContainer()
        let context = container.mainContext
        let bookID = UUID()
        let alliance = PowerLevel(bookID: bookID, name: "Alliance", sortOrder: 0)
        let country = PowerLevel(bookID: bookID, name: "Country", sortOrder: 1)
        [alliance, country].forEach(context.insert)
        try context.save()

        XCTAssertThrowsError(
            try PowerHierarchyStore.renameLevel(
                country,
                to: "  ",
                bookID: bookID,
                levels: [alliance, country],
                context: context
            )
        )
        XCTAssertEqual(country.name, "Country")
        XCTAssertThrowsError(
            try PowerHierarchyStore.renameLevel(
                country,
                to: "alliance",
                bookID: bookID,
                levels: [alliance, country],
                context: context
            )
        )
        XCTAssertEqual(country.name, "Country")
    }

    func testV1SettingsMigrationPreservesSettingsAndPowersButRemovesLegacyEdges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-settings-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("settings.store")
        let bookID = UUID()
        let lowerID = UUID()
        let upperID = UUID()
        let placeID = UUID()
        let termID = UUID()
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: V5SettingsSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = container.mainContext
            context.insert(V5SettingsSchemaV1.BookSidebarSetting(id: rowID, bookID: bookID, key: .power, sortOrder: 0, isVisible: true))
            context.insert(V5SettingsSchemaV1.PowerUnit(id: lowerID, bookID: bookID, name: "舊下級", powerDescription: "保留簡介"))
            context.insert(V5SettingsSchemaV1.PowerUnit(id: upperID, bookID: bookID, name: "舊上級"))
            context.insert(V5SettingsSchemaV1.PowerSubordination(bookID: bookID, lowerPowerID: lowerID, upperPowerID: upperID))
            context.insert(V5SettingsSchemaV1.Place(id: placeID, bookID: bookID, name: "保留地點"))
            context.insert(V5SettingsSchemaV1.WorldTerm(id: termID, bookID: bookID, name: "保留條目"))
            try context.save()
        }

        let schema = Schema(versionedSchema: V5SettingsSchemaV3.self)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: V5SettingsMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = migrated.mainContext

        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<PowerUnit>()).map(\.id)), Set([lowerID, upperID]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerUnit>()).first(where: { $0.id == lowerID })?.powerDescription, "保留簡介")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PowerUnit>()).allSatisfy { $0.levelID == nil })
        XCTAssertTrue(try context.fetch(FetchDescriptor<PowerSubordination>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BookSidebarSetting>()).map(\.id), [rowID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Place>()).map(\.id), [placeID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorldTerm>()).map(\.id), [termID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerLevel>()).sorted { $0.sortOrder < $1.sortOrder }.map(\.name), ["層級 1", "層級 2"])
    }

    func testV2SettingsMigrationPreservesLevelsAndRestoresNotebookFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-settings-v3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("settings.store")
        let bookID = UUID()
        let levelID = UUID()
        let powerID = UUID()

        do {
            let schema = Schema(versionedSchema: V5SettingsSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
            let context = container.mainContext
            context.insert(V5SettingsSchemaV2.BookSidebarSetting(bookID: bookID, key: .power, sortOrder: 0, isVisible: true))
            context.insert(V5SettingsSchemaV2.PowerLevel(id: levelID, bookID: bookID, name: "自訂層級", sortOrder: 0))
            context.insert(V5SettingsSchemaV2.PowerUnit(id: powerID, bookID: bookID, name: "保留勢力", powerDescription: "保留簡介", levelID: levelID))
            try context.save()
        }

        let schema = Schema(versionedSchema: V5SettingsSchemaV3.self)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: V5SettingsMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = migrated.mainContext
        let power = try XCTUnwrap(context.fetch(FetchDescriptor<PowerUnit>()).first)

        XCTAssertEqual(power.id, powerID)
        XCTAssertEqual(power.levelID, levelID)
        XCTAssertEqual(power.powerDescription, "保留簡介")
        XCTAssertEqual(power.seniorManagers, "")
        XCTAssertEqual(power.otherRoster, "")
        XCTAssertEqual(power.relationshipNotes, "")
        XCTAssertEqual(power.politics, "")
        XCTAssertEqual(power.religion, "")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PowerLevel>()).map(\.name), ["自訂層級"])

        power.seniorManagers = "議長：艾琳"
        power.otherRoster = "顧問：羅恩"
        power.relationshipNotes = "與北國合作"
        power.politics = "議會制"
        power.religion = "月神信仰"
        try context.save()
        XCTAssertEqual(power.seniorManagers, "議長：艾琳")
        XCTAssertEqual(power.otherRoster, "顧問：羅恩")
        XCTAssertEqual(power.relationshipNotes, "與北國合作")
        XCTAssertEqual(power.politics, "議會制")
        XCTAssertEqual(power.religion, "月神信仰")
    }

    func testLegacyOrganizationCleanupPreservesCharacter() throws {
        let container = try makeLegacyMainContainer()
        let context = container.mainContext
        let book = Book(title: "測試書", author: "作者")
        let character = Character(realName: "角色", book: book)
        let organization = Organization(name: "舊組織", book: book)
        let membership = CharacterOrganization(character: character, organization: organization)
        let identity = OrganizationIdentityHistory(identity: "舊身分", membership: membership)
        membership.identityHistory.append(identity)
        context.insert(book)
        context.insert(character)
        context.insert(organization)
        context.insert(membership)
        context.insert(identity)
        try context.save()

        try V5DataCleanup.removeLegacyOrganizations(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Organization>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CharacterOrganization>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OrganizationIdentityHistory>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Character>()).map(\.realName), ["角色"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Book>()).count, 1)
    }

    func testLegacyPlanningMetadataCleanup() throws {
        let schema = Schema(versionedSchema: StoryPlanningSchemaV7.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = try StoryPlanningStore(container: container)
        _ = try store.setRecordPlacement(
            sourceKind: .organizationJoin,
            sourceID: UUID(),
            bookID: UUID(),
            storyLineID: nil,
            stageID: nil
        )

        try store.removeLegacyOrganizationMetadata()
        XCTAssertTrue(store.planningRecordMetadata.isEmpty)
    }

    func testReleasedMainStoreOpensBesideSettingsStoreAndPreservesCoreData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sailune-V5-split-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mainURL = directory.appendingPathComponent("Sailune-v5.store")
        let settingsURL = directory.appendingPathComponent("Sailune-v5-settings.store")
        let bookID = UUID()
        let characterID = UUID()
        let sectionID = UUID()
        let itemID = UUID()
        let abilityID = UUID()
        let timelineID = UUID()
        let nodeID = UUID()
        let eventID = UUID()

        do {
            let schema = Schema(versionedSchema: NovelWriterSchemaV5.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: mainURL)]
            )
            let context = container.mainContext
            let book = Book(id: bookID, title: "必須保留", author: "作者")
            let volume = Volume(title: "第一卷", book: book)
            let section = Section(id: sectionID, title: "正文", content: AttributedString("不可刪除"), volume: volume)
            let character = Character(realName: "保留角色", book: book)
            character.id = characterID
            let item = Item(id: itemID, name: "保留物品", book: book)
            let ability = CharacterAbility(id: abilityID, name: "保留能力", character: character)
            let timeline = Timeline(id: timelineID, name: "保留時間軸", isPrimary: true)
            timeline.book = book
            let node = Node(id: nodeID, year: 1)
            node.timeline = timeline
            node.section = section
            let event = Event(id: eventID, title: "保留事件")
            event.node = node
            event.section = section
            let organization = Organization(name: "允許刪除的舊組織", book: book)
            let membership = CharacterOrganization(character: character, organization: organization)
            context.insert(book)
            context.insert(volume)
            context.insert(section)
            context.insert(character)
            context.insert(item)
            context.insert(ability)
            context.insert(timeline)
            context.insert(node)
            context.insert(event)
            context.insert(organization)
            context.insert(membership)
            try context.save()
        }

        do {
            let mainSchema = Schema(versionedSchema: NovelWriterSchemaV5.self)
            let settingsSchema = Schema(versionedSchema: V5SettingsSchemaV3.self)
            let mainContainer = try ModelContainer(
                for: mainSchema,
                configurations: [ModelConfiguration(schema: mainSchema, url: mainURL)]
            )
            let settingsContainer = try ModelContainer(
                for: settingsSchema,
                migrationPlan: V5SettingsMigrationPlan.self,
                configurations: [ModelConfiguration(schema: settingsSchema, url: settingsURL)]
            )
            try V5DataCleanup.removeLegacyOrganizations(in: mainContainer.mainContext)
            settingsContainer.mainContext.insert(PowerUnit(bookID: bookID, name: "新勢力"))
            try settingsContainer.mainContext.save()

            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Book>()).map(\.id), [bookID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Character>()).map(\.id), [characterID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Section>()).map(\.id), [sectionID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Item>()).map(\.id), [itemID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<CharacterAbility>()).map(\.id), [abilityID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Timeline>()).map(\.id), [timelineID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Node>()).map(\.id), [nodeID])
            XCTAssertEqual(try mainContainer.mainContext.fetch(FetchDescriptor<Event>()).map(\.id), [eventID])
            XCTAssertEqual(String(try XCTUnwrap(mainContainer.mainContext.fetch(FetchDescriptor<Section>()).first).content.characters), "不可刪除")
            XCTAssertTrue(try mainContainer.mainContext.fetch(FetchDescriptor<Organization>()).isEmpty)
            XCTAssertTrue(try mainContainer.mainContext.fetch(FetchDescriptor<CharacterOrganization>()).isEmpty)
            XCTAssertEqual(try settingsContainer.mainContext.fetch(FetchDescriptor<PowerUnit>()).map(\.name), ["新勢力"])
        }

        let releasedSchema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        let reopened = try ModelContainer(
            for: releasedSchema,
            configurations: [ModelConfiguration(schema: releasedSchema, url: mainURL)]
        )
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Book>()).map(\.id), [bookID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Character>()).map(\.id), [characterID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Section>()).map(\.id), [sectionID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Item>()).map(\.id), [itemID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CharacterAbility>()).map(\.id), [abilityID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Timeline>()).map(\.id), [timelineID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Node>()).map(\.id), [nodeID])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Event>()).map(\.id), [eventID])
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<Organization>()).isEmpty)
    }

    private func makeMainContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: V5SettingsSchemaV3.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: V5SettingsMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func makeLegacyMainContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

}
