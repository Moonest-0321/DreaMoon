import Foundation
import Observation
import SwiftData

/// The settings catalog is intentionally small in V5. New setting types can be
/// added later without changing the meaning of the saved visibility rows.
enum SidebarSettingKey: String, CaseIterable, Codable, Hashable, Identifiable {
    case character
    case power
    case item
    case ability
    case storyTag
    case place
    case worldTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "角色"
        case .power: "勢力"
        case .item: "物品"
        case .ability: "能力"
        case .storyTag: "標籤"
        case .place: "地點"
        case .worldTerm: "世界條目"
        }
    }

    var systemImage: String {
        switch self {
        case .character: "person.2"
        case .power: "building.2"
        case .item: "shippingbox"
        case .ability: "sparkles"
        case .storyTag: "tag"
        case .place: "mappin.and.ellipse"
        case .worldTerm: "book.closed"
        }
    }

    var isDefaultVisible: Bool {
        switch self {
        case .character, .power, .item, .ability, .storyTag: true
        case .place, .worldTerm: false
        }
    }

    static var defaultOrder: [SidebarSettingKey] {
        [.character, .power, .item, .ability, .storyTag, .place, .worldTerm]
    }

    static var optionalKeys: [SidebarSettingKey] { [.place, .worldTerm] }
}

/// V5 settings live in their own store. Keeping them out of the released main
/// schema means enabling the feature never migrates or rewrites prose, books,
/// characters, items, abilities, or timeline data.
enum V5SettingsSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            BookSidebarSetting.self,
            PowerUnit.self,
            PowerSubordination.self,
            Place.self,
            WorldTerm.self
        ]
    }
}

extension V5SettingsSchemaV1 {
@Model
final class BookSidebarSetting {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var keyRawValue: String
    var sortOrder: Int
    var isVisible: Bool

    init(
        id: UUID = UUID(),
        bookID: UUID,
        key: SidebarSettingKey,
        sortOrder: Int,
        isVisible: Bool
    ) {
        self.id = id
        self.bookID = bookID
        self.keyRawValue = key.rawValue
        self.sortOrder = sortOrder
        self.isVisible = isVisible
    }

    var key: SidebarSettingKey? {
        SidebarSettingKey(rawValue: keyRawValue)
    }
}

@Model
final class PowerUnit {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var powerDescription: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String = "",
        powerDescription: String = ""
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.powerDescription = powerDescription
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// One direct edge: the lower power belongs to the upper power. No transitive
/// edges are generated or stored.
@Model
final class PowerSubordination {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var lowerPowerID: UUID
    var upperPowerID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        lowerPowerID: UUID,
        upperPowerID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.lowerPowerID = lowerPowerID
        self.upperPowerID = upperPowerID
        self.createdAt = createdAt
    }
}

@Model
final class Place {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var placeDescription: String
    var sortOrder: Int

    init(id: UUID = UUID(), bookID: UUID, name: String = "", placeDescription: String = "", sortOrder: Int = 0) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.placeDescription = placeDescription
        self.sortOrder = sortOrder
    }
}

@Model
final class WorldTerm {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var termDescription: String
    var sortOrder: Int

    init(id: UUID = UUID(), bookID: UUID, name: String = "", termDescription: String = "", sortOrder: Int = 0) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.termDescription = termDescription
        self.sortOrder = sortOrder
    }
}
}

/// V2 adds author-defined power levels. `PowerUnit.levelID` remains optional so
/// V1 powers can migrate without inventing a hierarchy the author did not name.
enum V5SettingsSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            BookSidebarSetting.self,
            PowerLevel.self,
            PowerUnit.self,
            PowerSubordination.self,
            Place.self,
            WorldTerm.self
        ]
    }
}

extension V5SettingsSchemaV2 {
@Model
final class BookSidebarSetting {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var keyRawValue: String
    var sortOrder: Int
    var isVisible: Bool

    init(
        id: UUID = UUID(),
        bookID: UUID,
        key: SidebarSettingKey,
        sortOrder: Int,
        isVisible: Bool
    ) {
        self.id = id
        self.bookID = bookID
        self.keyRawValue = key.rawValue
        self.sortOrder = sortOrder
        self.isVisible = isVisible
    }

    var key: SidebarSettingKey? {
        SidebarSettingKey(rawValue: keyRawValue)
    }
}

@Model
final class PowerLevel {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    /// Smaller values are higher levels.
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

@Model
final class PowerUnit {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var powerDescription: String
    /// UUID link to `PowerLevel` in the same settings store and book.
    var levelID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String = "",
        powerDescription: String = "",
        levelID: UUID? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.powerDescription = powerDescription
        self.levelID = levelID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// One direct edge. Its endpoints must have levels and the lower endpoint's
/// order must be greater than the upper endpoint's order.
@Model
final class PowerSubordination {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var lowerPowerID: UUID
    var upperPowerID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        lowerPowerID: UUID,
        upperPowerID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.lowerPowerID = lowerPowerID
        self.upperPowerID = upperPowerID
        self.createdAt = createdAt
    }
}

@Model
final class Place {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var placeDescription: String
    var sortOrder: Int

    init(id: UUID = UUID(), bookID: UUID, name: String = "", placeDescription: String = "", sortOrder: Int = 0) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.placeDescription = placeDescription
        self.sortOrder = sortOrder
    }
}

@Model
final class WorldTerm {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var termDescription: String
    var sortOrder: Int

    init(id: UUID = UUID(), bookID: UUID, name: String = "", termDescription: String = "", sortOrder: Int = 0) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.termDescription = termDescription
        self.sortOrder = sortOrder
    }
}
}

/// V3 restores the complete first-version power notebook fields while keeping
/// all lists as free text. They intentionally do not create links to characters
/// or other setting entities.
enum V5SettingsSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            BookSidebarSetting.self,
            PowerLevel.self,
            PowerUnit.self,
            PowerSubordination.self,
            Place.self,
            WorldTerm.self
        ]
    }
}

extension V5SettingsSchemaV3 {
@Model
final class BookSidebarSetting {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var keyRawValue: String
    var sortOrder: Int
    var isVisible: Bool

    init(
        id: UUID = UUID(),
        bookID: UUID,
        key: SidebarSettingKey,
        sortOrder: Int,
        isVisible: Bool
    ) {
        self.id = id
        self.bookID = bookID
        self.keyRawValue = key.rawValue
        self.sortOrder = sortOrder
        self.isVisible = isVisible
    }

    var key: SidebarSettingKey? {
        SidebarSettingKey(rawValue: keyRawValue)
    }
}

@Model
final class PowerLevel {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    /// Smaller values are higher levels.
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

@Model
final class PowerUnit {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var powerDescription: String
    var seniorManagers: String = ""
    var otherRoster: String = ""
    var relationshipNotes: String = ""
    var politics: String = ""
    var religion: String = ""
    /// UUID link to `PowerLevel` in the same settings store and book.
    var levelID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String = "",
        powerDescription: String = "",
        seniorManagers: String = "",
        otherRoster: String = "",
        relationshipNotes: String = "",
        politics: String = "",
        religion: String = "",
        levelID: UUID? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.powerDescription = powerDescription
        self.seniorManagers = seniorManagers
        self.otherRoster = otherRoster
        self.relationshipNotes = relationshipNotes
        self.politics = politics
        self.religion = religion
        self.levelID = levelID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class PowerSubordination {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var lowerPowerID: UUID
    var upperPowerID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        lowerPowerID: UUID,
        upperPowerID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.lowerPowerID = lowerPowerID
        self.upperPowerID = upperPowerID
        self.createdAt = createdAt
    }
}

@Model
final class Place {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var placeDescription: String
    var sortOrder: Int

    init(id: UUID = UUID(), bookID: UUID, name: String = "", placeDescription: String = "", sortOrder: Int = 0) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.placeDescription = placeDescription
        self.sortOrder = sortOrder
    }
}

@Model
final class WorldTerm {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var termDescription: String
    var sortOrder: Int

    init(id: UUID = UUID(), bookID: UUID, name: String = "", termDescription: String = "", sortOrder: Int = 0) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.termDescription = termDescription
        self.sortOrder = sortOrder
    }
}
}

/// V1 edges have no level information and therefore cannot be validated under
/// V2 semantics. V3 then restores the original notebook fields and gives each
/// already-initialized book two editable generic levels if it has none.
enum V5SettingsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [V5SettingsSchemaV1.self, V5SettingsSchemaV2.self, V5SettingsSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: V5SettingsSchemaV1.self,
                toVersion: V5SettingsSchemaV2.self,
                willMigrate: { context in
                    try context.fetch(FetchDescriptor<V5SettingsSchemaV1.PowerSubordination>())
                        .forEach(context.delete)
                    try context.save()
                },
                didMigrate: nil
            ),
            .custom(
                fromVersion: V5SettingsSchemaV2.self,
                toVersion: V5SettingsSchemaV3.self,
                willMigrate: nil,
                didMigrate: { context in
                    let rows = try context.fetch(FetchDescriptor<V5SettingsSchemaV3.BookSidebarSetting>())
                    let powers = try context.fetch(FetchDescriptor<V5SettingsSchemaV3.PowerUnit>())
                    let existingLevels = try context.fetch(FetchDescriptor<V5SettingsSchemaV3.PowerLevel>())
                    let bookIDs = Set(rows.map(\.bookID) + powers.map(\.bookID))
                    for bookID in bookIDs where !existingLevels.contains(where: { $0.bookID == bookID }) {
                        context.insert(V5SettingsSchemaV3.PowerLevel(bookID: bookID, name: "層級 1", sortOrder: 0))
                        context.insert(V5SettingsSchemaV3.PowerLevel(bookID: bookID, name: "層級 2", sortOrder: 1))
                    }
                    try context.save()
                }
            )
        ]
    }
}

typealias BookSidebarSetting = V5SettingsSchemaV3.BookSidebarSetting
typealias PowerLevel = V5SettingsSchemaV3.PowerLevel
typealias PowerUnit = V5SettingsSchemaV3.PowerUnit
typealias PowerSubordination = V5SettingsSchemaV3.PowerSubordination
typealias Place = V5SettingsSchemaV3.Place
typealias WorldTerm = V5SettingsSchemaV3.WorldTerm

enum PowerHierarchyError: LocalizedError {
    case invalidBook
    case invalidLevelName
    case duplicateLevelName(String)
    case levelInUse(String)
    case levelNotAssigned(String)
    case duplicateRelation
    case invalidDirection
    case invalidLevelOrder
    case conflictingRelations([String])

    var errorDescription: String? {
        switch self {
        case .invalidBook:
            "勢力與層級必須屬於同一本書。"
        case .invalidLevelName:
            "層級名稱不可空白。"
        case .duplicateLevelName(let name):
            "同一本書已經有「\(name)」層級。"
        case .levelInUse(let name):
            "「\(name)」仍有勢力使用，無法刪除。"
        case .levelNotAssigned(let name):
            "「\(name)」尚未指定層級，不能建立隸屬關係。"
        case .duplicateRelation:
            "這項直屬關係已經存在。"
        case .invalidDirection:
            "只有較低層級的勢力可以隸屬較高層級的勢力。"
        case .invalidLevelOrder:
            "層級順序不完整，無法儲存。"
        case .conflictingRelations(let relations):
            "這項變更會破壞既有隸屬：\(relations.joined(separator: "、"))"
        }
    }
}

@MainActor
@Observable
final class V5SettingsStore {
    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored let context: ModelContext
    private(set) var revision = 0
    private(set) var persistenceErrorMessage: String?

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        context.autosaveEnabled = true
    }

    func sidebarRows(for bookID: UUID) -> [BookSidebarSetting] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<BookSidebarSetting>()))?
            .filter { $0.bookID == bookID }
            .sorted { $0.sortOrder < $1.sortOrder } ?? []
    }

    func powers(for bookID: UUID) -> [PowerUnit] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<PowerUnit>()))?
            .filter { $0.bookID == bookID } ?? []
    }

    func levels(for bookID: UUID) -> [PowerLevel] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<PowerLevel>()))?
            .filter { $0.bookID == bookID }
            .sorted { $0.sortOrder < $1.sortOrder } ?? []
    }

    func edges(for bookID: UUID) -> [PowerSubordination] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<PowerSubordination>()))?
            .filter { $0.bookID == bookID } ?? []
    }

    func places(for bookID: UUID) -> [Place] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<Place>()))?
            .filter { $0.bookID == bookID } ?? []
    }

    func worldTerms(for bookID: UUID) -> [WorldTerm] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<WorldTerm>()))?
            .filter { $0.bookID == bookID } ?? []
    }

    @discardableResult
    func ensureDefaults(for bookID: UUID) -> [BookSidebarSetting] {
        do {
            let isNewBookConfiguration = sidebarRows(for: bookID).isEmpty
            let rows = try SidebarSettingCatalog.ensureDefaults(for: bookID, in: context)
            if isNewBookConfiguration && levels(for: bookID).isEmpty {
                try PowerHierarchyStore.ensureDefaultLevels(bookID: bookID, context: context)
            }
            didSave()
            return rows
        } catch {
            record(error)
            return sidebarRows(for: bookID)
        }
    }

    func save() {
        do {
            try context.save()
            didSave()
        } catch {
            record(error)
        }
    }

    @discardableResult
    func createLevel(bookID: UUID) throws -> PowerLevel {
        let level = try PowerHierarchyStore.createLevel(
            bookID: bookID,
            levels: levels(for: bookID),
            context: context
        )
        didSave()
        return level
    }

    func renameLevel(_ level: PowerLevel, to name: String, bookID: UUID) throws {
        try PowerHierarchyStore.renameLevel(
            level,
            to: name,
            bookID: bookID,
            levels: levels(for: bookID),
            context: context
        )
        didSave()
    }

    func reorderLevels(bookID: UUID, orderedIDs: [UUID]) throws {
        try PowerHierarchyStore.reorderLevels(
            bookID: bookID,
            orderedIDs: orderedIDs,
            levels: levels(for: bookID),
            powers: powers(for: bookID),
            edges: edges(for: bookID),
            context: context
        )
        didSave()
    }

    func deleteLevel(_ level: PowerLevel, bookID: UUID) throws {
        try PowerHierarchyStore.deleteLevel(
            level,
            bookID: bookID,
            powers: powers(for: bookID),
            context: context
        )
        didSave()
    }

    func changeLevel(of power: PowerUnit, to level: PowerLevel, bookID: UUID) throws {
        try PowerHierarchyStore.changeLevel(
            of: power,
            to: level,
            bookID: bookID,
            levels: levels(for: bookID),
            powers: powers(for: bookID),
            edges: edges(for: bookID),
            context: context
        )
        didSave()
    }

    func addSubordination(lower: PowerUnit, upper: PowerUnit, bookID: UUID) throws {
        var currentEdges = edges(for: bookID)
        try PowerGraphStore.addDirectSubordination(
            lower: lower,
            upper: upper,
            bookID: bookID,
            levels: levels(for: bookID),
            edges: &currentEdges,
            context: context
        )
        didSave()
    }

    func removeRelations(between power: PowerUnit, and other: PowerUnit, bookID: UUID) {
        edges(for: bookID).filter {
            ($0.lowerPowerID == power.id && $0.upperPowerID == other.id) ||
            ($0.lowerPowerID == other.id && $0.upperPowerID == power.id)
        }.forEach(context.delete)
        save()
    }

    func deletePower(_ power: PowerUnit, bookID: UUID) {
        do {
            try PowerGraphStore.delete(power, edges: edges(for: bookID), context: context)
            didSave()
        } catch {
            record(error)
        }
    }

    func deleteBookData(bookID: UUID) throws {
        try context.fetch(FetchDescriptor<BookSidebarSetting>()).filter { $0.bookID == bookID }.forEach(context.delete)
        try context.fetch(FetchDescriptor<PowerSubordination>()).filter { $0.bookID == bookID }.forEach(context.delete)
        try context.fetch(FetchDescriptor<PowerUnit>()).filter { $0.bookID == bookID }.forEach(context.delete)
        try context.fetch(FetchDescriptor<PowerLevel>()).filter { $0.bookID == bookID }.forEach(context.delete)
        try context.fetch(FetchDescriptor<Place>()).filter { $0.bookID == bookID }.forEach(context.delete)
        try context.fetch(FetchDescriptor<WorldTerm>()).filter { $0.bookID == bookID }.forEach(context.delete)
        try context.save()
        didSave()
    }

    func didSave() {
        persistenceErrorMessage = nil
        revision &+= 1
    }

    func clearPersistenceError() {
        persistenceErrorMessage = nil
    }

    private func record(_ error: Error) {
        persistenceErrorMessage = error.localizedDescription
        revision &+= 1
    }

}

@MainActor
enum SidebarSettingCatalog {
    static func rows(for bookID: UUID, in context: ModelContext) throws -> [BookSidebarSetting] {
        let rows = try context.fetch(FetchDescriptor<BookSidebarSetting>())
            .filter { $0.bookID == bookID }
        if !rows.isEmpty { return rows.sorted { $0.sortOrder < $1.sortOrder } }
        return try ensureDefaults(for: bookID, in: context)
    }

    @discardableResult
    static func ensureDefaults(for bookID: UUID, in context: ModelContext) throws -> [BookSidebarSetting] {
        var rows = try context.fetch(FetchDescriptor<BookSidebarSetting>()).filter { $0.bookID == bookID }
        let existing = Set(rows.compactMap(\.key))
        for (index, key) in SidebarSettingKey.defaultOrder.enumerated() where !existing.contains(key) {
            let row = BookSidebarSetting(bookID: bookID, key: key, sortOrder: index, isVisible: key.isDefaultVisible)
            context.insert(row)
            rows.append(row)
        }
        try context.save()
        return rows.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func visibleKeys(rows: [BookSidebarSetting]) -> [SidebarSettingKey] {
        rows.sorted { $0.sortOrder < $1.sortOrder }.compactMap { $0.isVisible ? $0.key : nil }
    }

    static func resolvedSelection(
        _ current: SidebarSettingKey,
        visibleKeys: [SidebarSettingKey]
    ) -> SidebarSettingKey {
        visibleKeys.contains(current) ? current : (visibleKeys.first ?? current)
    }
}

@MainActor
enum PowerHierarchyStore {
    static func ensureDefaultLevels(bookID: UUID, context: ModelContext) throws {
        context.insert(PowerLevel(bookID: bookID, name: "層級 1", sortOrder: 0))
        context.insert(PowerLevel(bookID: bookID, name: "層級 2", sortOrder: 1))
        try context.save()
    }

    static func createLevel(
        bookID: UUID,
        levels: [PowerLevel],
        context: ModelContext
    ) throws -> PowerLevel {
        var suffix = levels.count + 1
        var name = "新層級 \(suffix)"
        while levels.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            suffix += 1
            name = "新層級 \(suffix)"
        }
        let nextOrder = (levels.map(\.sortOrder).max() ?? -1) + 1
        let level = PowerLevel(bookID: bookID, name: name, sortOrder: nextOrder)
        context.insert(level)
        try context.save()
        return level
    }

    static func renameLevel(
        _ level: PowerLevel,
        to proposedName: String,
        bookID: UUID,
        levels: [PowerLevel],
        context: ModelContext
    ) throws {
        guard level.bookID == bookID else { throw PowerHierarchyError.invalidBook }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PowerHierarchyError.invalidLevelName }
        guard !levels.contains(where: {
            $0.id != level.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw PowerHierarchyError.duplicateLevelName(name)
        }
        let oldName = level.name
        level.name = name
        do {
            try context.save()
        } catch {
            level.name = oldName
            throw error
        }
    }

    static func deleteLevel(
        _ level: PowerLevel,
        bookID: UUID,
        powers: [PowerUnit],
        context: ModelContext
    ) throws {
        guard level.bookID == bookID else { throw PowerHierarchyError.invalidBook }
        guard !powers.contains(where: { $0.levelID == level.id }) else {
            throw PowerHierarchyError.levelInUse(level.name)
        }
        context.delete(level)
        try context.save()
    }

    static func changeLevel(
        of power: PowerUnit,
        to level: PowerLevel,
        bookID: UUID,
        levels: [PowerLevel],
        powers: [PowerUnit],
        edges: [PowerSubordination],
        context: ModelContext
    ) throws {
        guard power.bookID == bookID, level.bookID == bookID else {
            throw PowerHierarchyError.invalidBook
        }
        let levelOrders = Dictionary(uniqueKeysWithValues: levels.map { ($0.id, $0.sortOrder) })
        let conflicts = conflictingRelations(
            powers: powers,
            edges: edges,
            levelOrders: levelOrders,
            overridingPowerID: power.id,
            withLevelID: level.id
        )
        guard conflicts.isEmpty else { throw PowerHierarchyError.conflictingRelations(conflicts) }

        let oldLevelID = power.levelID
        power.levelID = level.id
        power.updatedAt = Date()
        do {
            try context.save()
        } catch {
            power.levelID = oldLevelID
            throw error
        }
    }

    static func reorderLevels(
        bookID: UUID,
        orderedIDs: [UUID],
        levels: [PowerLevel],
        powers: [PowerUnit],
        edges: [PowerSubordination],
        context: ModelContext
    ) throws {
        guard Set(orderedIDs) == Set(levels.map(\.id)), orderedIDs.count == levels.count else {
            throw PowerHierarchyError.invalidLevelOrder
        }
        let proposedOrders = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        let conflicts = conflictingRelations(
            powers: powers,
            edges: edges,
            levelOrders: proposedOrders
        )
        guard conflicts.isEmpty else { throw PowerHierarchyError.conflictingRelations(conflicts) }

        let oldOrders = Dictionary(uniqueKeysWithValues: levels.map { ($0.id, $0.sortOrder) })
        for level in levels {
            level.sortOrder = proposedOrders[level.id] ?? level.sortOrder
        }
        do {
            try context.save()
        } catch {
            for level in levels {
                level.sortOrder = oldOrders[level.id] ?? level.sortOrder
            }
            throw error
        }
    }

    static func upperCandidates(
        for power: PowerUnit,
        powers: [PowerUnit],
        levels: [PowerLevel]
    ) -> [PowerUnit] {
        candidates(for: power, powers: powers, levels: levels) { $0 < $1 }
    }

    static func lowerCandidates(
        for power: PowerUnit,
        powers: [PowerUnit],
        levels: [PowerLevel]
    ) -> [PowerUnit] {
        candidates(for: power, powers: powers, levels: levels) { $0 > $1 }
    }

    static func level(for power: PowerUnit, levels: [PowerLevel]) -> PowerLevel? {
        guard let levelID = power.levelID else { return nil }
        return levels.first { $0.id == levelID }
    }

    private static func candidates(
        for power: PowerUnit,
        powers: [PowerUnit],
        levels: [PowerLevel],
        matches: (Int, Int) -> Bool
    ) -> [PowerUnit] {
        let levelOrders = Dictionary(uniqueKeysWithValues: levels.map { ($0.id, $0.sortOrder) })
        guard let currentLevelID = power.levelID,
              let currentOrder = levelOrders[currentLevelID] else { return [] }
        return powers.filter { candidate in
            guard candidate.id != power.id,
                  let candidateLevelID = candidate.levelID,
                  let candidateOrder = levelOrders[candidateLevelID] else { return false }
            return matches(candidateOrder, currentOrder)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func conflictingRelations(
        powers: [PowerUnit],
        edges: [PowerSubordination],
        levelOrders: [UUID: Int],
        overridingPowerID: UUID? = nil,
        withLevelID: UUID? = nil
    ) -> [String] {
        let powerByID = Dictionary(uniqueKeysWithValues: powers.map { ($0.id, $0) })
        return edges.compactMap { edge in
            guard let lower = powerByID[edge.lowerPowerID],
                  let upper = powerByID[edge.upperPowerID] else { return nil }
            let lowerLevelID = lower.id == overridingPowerID ? withLevelID : lower.levelID
            let upperLevelID = upper.id == overridingPowerID ? withLevelID : upper.levelID
            guard let lowerLevelID,
                  let upperLevelID,
                  let lowerOrder = levelOrders[lowerLevelID],
                  let upperOrder = levelOrders[upperLevelID],
                  lowerOrder > upperOrder else {
                return "\(displayName(lower)) → \(displayName(upper))"
            }
            return nil
        }
    }

    private static func displayName(_ power: PowerUnit) -> String {
        power.name.isEmpty ? "未命名勢力" : power.name
    }
}

@MainActor
enum PowerGraphStore {
    static func directUpperPowers(of power: PowerUnit, edges: [PowerSubordination], powers: [PowerUnit]) -> [PowerUnit] {
        let ids = Set(edges.filter { $0.lowerPowerID == power.id }.map(\.upperPowerID))
        return powers.filter { ids.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func directLowerPowers(of power: PowerUnit, edges: [PowerSubordination], powers: [PowerUnit]) -> [PowerUnit] {
        let ids = Set(edges.filter { $0.upperPowerID == power.id }.map(\.lowerPowerID))
        return powers.filter { ids.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func addDirectSubordination(
        lower: PowerUnit,
        upper: PowerUnit,
        bookID: UUID,
        levels: [PowerLevel],
        edges: inout [PowerSubordination],
        context: ModelContext
    ) throws {
        guard lower.id != upper.id,
              lower.bookID == bookID,
              upper.bookID == bookID else { throw PowerHierarchyError.invalidBook }
        guard !edges.contains(where: { $0.lowerPowerID == lower.id && $0.upperPowerID == upper.id }) else {
            throw PowerHierarchyError.duplicateRelation
        }
        guard let lowerLevel = PowerHierarchyStore.level(for: lower, levels: levels) else {
            throw PowerHierarchyError.levelNotAssigned(lower.name.isEmpty ? "未命名勢力" : lower.name)
        }
        guard let upperLevel = PowerHierarchyStore.level(for: upper, levels: levels) else {
            throw PowerHierarchyError.levelNotAssigned(upper.name.isEmpty ? "未命名勢力" : upper.name)
        }
        guard lowerLevel.sortOrder > upperLevel.sortOrder else {
            throw PowerHierarchyError.invalidDirection
        }
        let edge = PowerSubordination(bookID: bookID, lowerPowerID: lower.id, upperPowerID: upper.id)
        context.insert(edge)
        edges.append(edge)
        try context.save()
    }

    static func delete(
        _ power: PowerUnit,
        edges: [PowerSubordination],
        context: ModelContext
    ) throws {
        edges.filter { $0.lowerPowerID == power.id || $0.upperPowerID == power.id }
            .forEach(context.delete)
        context.delete(power)
        try context.save()
    }
}
