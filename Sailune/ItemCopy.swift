import Foundation
import Observation
import SwiftData

enum ItemCopySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ItemCopy.self, ItemCopyHolding.self, ItemCopyHistory.self]
    }
}

/// Kept in its own store so adding a manually selected current level never
/// migrates the existing copy store or the released V5 main store.
enum ItemCopyLevelSelectionSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ItemCopyLevelSelection.self]
    }
}

/// An individually tracked instance of an Item definition.
/// It uses stable UUID links so adding copies never changes the existing V5
/// Item, CharacterItem, or ItemHistory tables.
@Model
final class ItemCopy {
    @Attribute(.unique) var id: UUID
    var itemID: UUID
    var sortOrder: Int
    /// Empty means the copy inherits its parent Item's name.
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        itemID: UUID,
        sortOrder: Int = 0,
        name: String = ""
    ) {
        self.id = id
        self.itemID = itemID
        self.sortOrder = sortOrder
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ItemCopyHolding {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var copyID: UUID
    var characterID: UUID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        copyID: UUID,
        characterID: UUID
    ) {
        self.id = id
        self.copyID = copyID
        self.characterID = characterID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ItemCopyHistory {
    @Attribute(.unique) var id: UUID
    var copyID: UUID
    var content: String
    var sortOrder: Int
    var nodeID: UUID?
    var relatedCharacterIDsData: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        copyID: UUID,
        content: String = "",
        sortOrder: Int = 0,
        nodeID: UUID? = nil,
        relatedCharacterIDs: [UUID] = []
    ) {
        self.id = id
        self.copyID = copyID
        self.content = content
        self.sortOrder = sortOrder
        self.nodeID = nodeID
        self.relatedCharacterIDsData = Self.encode(relatedCharacterIDs)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var relatedCharacterIDs: [UUID] {
        get { Self.decode(relatedCharacterIDsData) }
        set { relatedCharacterIDsData = Self.encode(newValue) }
    }

    private static func encode(_ ids: [UUID]) -> Data {
        (try? JSONEncoder().encode(ids)) ?? Data()
    }

    private static func decode(_ data: Data) -> [UUID] {
        (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }
}

/// The optional, manually chosen current level for one copy. It intentionally
/// has no automatic effect on the item's name, abilities, costs, or history.
@Model
final class ItemCopyLevelSelection {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var copyID: UUID
    var levelID: UUID
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), copyID: UUID, levelID: UUID) {
        self.id = id
        self.copyID = copyID
        self.levelID = levelID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension ItemCopy {
    func displayName(for item: Item) -> String {
        let custom = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? item.name : custom
    }
}

@MainActor
enum ItemCopyOperations {
    static func create(
        for item: Item,
        existingCopies: [ItemCopy],
        context: ModelContext,
        name: String = ""
    ) -> ItemCopy {
        let copy = ItemCopy(
            itemID: item.id,
            sortOrder: (existingCopies.map(\.sortOrder).max() ?? -1) + 1,
            name: name
        )
        context.insert(copy)
        item.updatedAt = Date()
        return copy
    }

    static func delete(
        _ copy: ItemCopy,
        holdings: [ItemCopyHolding],
        histories: [ItemCopyHistory],
        context: ModelContext
    ) {
        for holding in holdings where holding.copyID == copy.id {
            context.delete(holding)
        }
        for history in histories where history.copyID == copy.id {
            context.delete(history)
        }
        context.delete(copy)
    }
}

@MainActor
@Observable
final class ItemCopyStore {
    let container: ModelContainer
    private let context: ModelContext
    private let levelSelectionContext: ModelContext
    private(set) var copies: [ItemCopy] = []
    private(set) var holdings: [ItemCopyHolding] = []
    private(set) var histories: [ItemCopyHistory] = []
    private(set) var levelSelections: [ItemCopyLevelSelection] = []
    private(set) var persistenceErrorMessage: String?

    init(container: ModelContainer, levelSelectionContainer: ModelContainer? = nil) throws {
        self.container = container
        self.context = container.mainContext
        self.levelSelectionContext = levelSelectionContainer?.mainContext ?? container.mainContext
        context.autosaveEnabled = true
        levelSelectionContext.autosaveEnabled = true
        try refresh()
    }

    func refresh() throws {
        copies = try context.fetch(FetchDescriptor<ItemCopy>()).sorted { $0.sortOrder < $1.sortOrder }
        holdings = try context.fetch(FetchDescriptor<ItemCopyHolding>())
        histories = try context.fetch(FetchDescriptor<ItemCopyHistory>()).sorted { $0.sortOrder < $1.sortOrder }
        levelSelections = try levelSelectionContext.fetch(FetchDescriptor<ItemCopyLevelSelection>())
    }

    @discardableResult
    func createCopy(itemID: UUID, name: String = "", holderID: UUID? = nil) -> ItemCopy {
        let itemCopies = copies.filter { $0.itemID == itemID }
        let copy = ItemCopy(
            itemID: itemID,
            sortOrder: (itemCopies.map(\.sortOrder).max() ?? -1) + 1,
            name: name
        )
        context.insert(copy)
        copies.append(copy)
        if let holderID {
            let holding = ItemCopyHolding(copyID: copy.id, characterID: holderID)
            context.insert(holding)
            holdings.append(holding)
        }
        save()
        return copy
    }

    func deleteCopy(_ copy: ItemCopy) {
        for holding in holdings where holding.copyID == copy.id { context.delete(holding) }
        for history in histories where history.copyID == copy.id { context.delete(history) }
        for selection in levelSelections where selection.copyID == copy.id { levelSelectionContext.delete(selection) }
        context.delete(copy)
        holdings.removeAll { $0.copyID == copy.id }
        histories.removeAll { $0.copyID == copy.id }
        levelSelections.removeAll { $0.copyID == copy.id }
        copies.removeAll { $0.id == copy.id }
        save()
    }

    func deleteCopies(itemID: UUID) {
        for copy in copies.filter({ $0.itemID == itemID }) { deleteCopy(copy) }
    }

    func setHolder(copyID: UUID, characterID: UUID?) {
        if let existing = holdings.first(where: { $0.copyID == copyID }) {
            if let characterID {
                existing.characterID = characterID
                existing.updatedAt = Date()
            } else {
                context.delete(existing)
                holdings.removeAll { $0.id == existing.id }
            }
        } else if let characterID {
            let holding = ItemCopyHolding(copyID: copyID, characterID: characterID)
            context.insert(holding)
            holdings.append(holding)
        }
        save()
    }

    /// Removes a deleted character from every copy immediately.  Copies stay
    /// intact and become available for assignment to another character.
    func removeHoldings(characterID: UUID) {
        let removed = holdings.filter { $0.characterID == characterID }
        guard !removed.isEmpty else { return }
        for holding in removed { context.delete(holding) }
        holdings.removeAll { $0.characterID == characterID }
        save()
    }

    func currentLevelID(for copyID: UUID) -> UUID? {
        levelSelections.first(where: { $0.copyID == copyID })?.levelID
    }

    /// This is a manual selection only. It does not modify any shared item
    /// settings and does not create a history entry.
    func setCurrentLevel(copyID: UUID, levelID: UUID?) {
        if let levelID {
            if let selection = levelSelections.first(where: { $0.copyID == copyID }) {
                selection.levelID = levelID
                selection.updatedAt = Date()
            } else {
                let selection = ItemCopyLevelSelection(copyID: copyID, levelID: levelID)
                levelSelectionContext.insert(selection)
                levelSelections.append(selection)
            }
        } else {
            clearCurrentLevel(copyID: copyID, saveImmediately: false)
        }
        save()
    }

    /// Called before an ItemLevel is deleted from the main store. This keeps
    /// the separate level-selection store valid immediately, not just after
    /// the next-launch repair pass.
    func clearCurrentLevelSelections(levelID: UUID) {
        for selection in levelSelections where selection.levelID == levelID {
            levelSelectionContext.delete(selection)
        }
        levelSelections.removeAll { $0.levelID == levelID }
        save()
    }

    func moveCopy(_ copy: ItemCopy, by offset: Int) {
        let itemCopies = copies.filter { $0.itemID == copy.itemID }.sorted { $0.sortOrder < $1.sortOrder }
        guard let source = itemCopies.firstIndex(where: { $0.id == copy.id }) else { return }
        let destination = source + offset
        guard itemCopies.indices.contains(destination) else { return }
        let other = itemCopies[destination]
        let order = copy.sortOrder
        copy.sortOrder = other.sortOrder
        other.sortOrder = order
        copy.updatedAt = Date()
        other.updatedAt = Date()
        copies.sort { $0.sortOrder < $1.sortOrder }
        save()
    }

    private func clearCurrentLevel(copyID: UUID, saveImmediately: Bool) {
        for selection in levelSelections where selection.copyID == copyID {
            levelSelectionContext.delete(selection)
        }
        levelSelections.removeAll { $0.copyID == copyID }
        if saveImmediately { save() }
    }

    @discardableResult
    func addHistory(copyID: UUID, content: String = "") -> ItemCopyHistory {
        let copyHistories = histories.filter { $0.copyID == copyID }
        let history = ItemCopyHistory(
            copyID: copyID,
            content: content,
            sortOrder: (copyHistories.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(history)
        histories.append(history)
        save()
        return history
    }

    func deleteHistory(_ history: ItemCopyHistory) {
        context.delete(history)
        histories.removeAll { $0.id == history.id }
        save()
    }

    func save() {
        do {
            if context.hasChanges { try context.save() }
            if levelSelectionContext !== context, levelSelectionContext.hasChanges {
                try levelSelectionContext.save()
            }
            persistenceErrorMessage = nil
        } catch {
            let nsError = error as NSError
            persistenceErrorMessage = "\(nsError.domain) \(nsError.code)：\(nsError.localizedDescription)"
        }
    }

    func clearPersistenceError() { persistenceErrorMessage = nil }
}

@MainActor
enum ItemCopyLevelSelectionRepair {
    static func run(
        source: ModelContext,
        copyContext: ModelContext,
        selectionContext: ModelContext
    ) throws {
        let copyItemIDs = Dictionary(
            uniqueKeysWithValues: try copyContext.fetch(FetchDescriptor<ItemCopy>()).map { ($0.id, $0.itemID) }
        )
        let levelItemIDs = Dictionary(
            uniqueKeysWithValues: try source.fetch(FetchDescriptor<ItemLevel>()).map { ($0.id, $0.itemID) }
        )
        for selection in try selectionContext.fetch(FetchDescriptor<ItemCopyLevelSelection>()) {
            guard let itemID = copyItemIDs[selection.copyID], levelItemIDs[selection.levelID] == itemID else {
                selectionContext.delete(selection)
                continue
            }
        }
        if selectionContext.hasChanges { try selectionContext.save() }
    }
}

@MainActor
enum V6ItemCopyBackfill {
    /// Converts legacy quantities into individually tracked copies once.
    /// Legacy rows are retained as a rollback source but are no longer edited
    /// by the V6 UI.
    static func run(source: ModelContext, destination: ModelContext) throws {
        let items = try source.fetch(FetchDescriptor<Item>())
        let existingCopies = try destination.fetch(FetchDescriptor<ItemCopy>())
        let validItemIDs = Set(items.map(\.id))

        for copy in existingCopies where !validItemIDs.contains(copy.itemID) {
            destination.delete(copy)
        }

        let validExistingCopies = existingCopies.filter { validItemIDs.contains($0.itemID) }
        let existingCopyItemIDs = Set(validExistingCopies.map(\.itemID))
        for item in items where !existingCopyItemIDs.contains(item.id) {
            let relations = item.characterItems.sorted { $0.id.uuidString < $1.id.uuidString }
            var copies: [ItemCopy] = []

            if relations.isEmpty {
                let copy = ItemCopy(itemID: item.id)
                destination.insert(copy)
                copies.append(copy)
            } else {
                for relation in relations {
                    for _ in 0..<max(1, relation.quantity) {
                        let copy = ItemCopy(itemID: item.id, sortOrder: copies.count)
                        destination.insert(copy)
                        copies.append(copy)
                        if let character = relation.character {
                            destination.insert(ItemCopyHolding(copyID: copy.id, characterID: character.id))
                        }
                    }
                }
            }

            // Legacy ItemHistory was shared by a quantity relation. Keep it
            // on the first converted copy only; all additional copies start
            // empty and can acquire their own history from here onward.
            if let baseCopy = copies.first {
                insertLegacyHistories(item.histories, into: baseCopy, destination: destination)
            }
        }

        // V6.0 briefly copied a shared legacy history onto every converted
        // copy. Remove only exact, timestamp-matching duplicates that can be
        // proven to originate from that legacy row; user-created histories
        // are never touched.
        try removeProvenLegacyDuplicates(items: items, destination: destination)

        let validCopyIDs = Set(validExistingCopies.map(\.id)).union(
            try destination.fetch(FetchDescriptor<ItemCopy>())
                .filter { validItemIDs.contains($0.itemID) }
                .map(\.id)
        )
        let validCharacterIDs = Set(try source.fetch(FetchDescriptor<Character>()).map(\.id))
        for holding in try destination.fetch(FetchDescriptor<ItemCopyHolding>())
            where !validCopyIDs.contains(holding.copyID) || !validCharacterIDs.contains(holding.characterID) {
            destination.delete(holding)
        }
        for history in try destination.fetch(FetchDescriptor<ItemCopyHistory>())
            where !validCopyIDs.contains(history.copyID) {
            destination.delete(history)
        }

        if destination.hasChanges { try destination.save() }
    }

    private static func insertLegacyHistories(
        _ histories: [ItemHistory],
        into copy: ItemCopy,
        destination: ModelContext
    ) {
        for history in histories.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let migrated = ItemCopyHistory(
                copyID: copy.id,
                content: history.content,
                sortOrder: history.sortOrder,
                nodeID: history.node?.id,
                relatedCharacterIDs: history.relatedCharacters.map(\.id)
            )
            migrated.createdAt = history.createdAt
            migrated.updatedAt = history.updatedAt
            destination.insert(migrated)
        }
    }

    private static func removeProvenLegacyDuplicates(
        items: [Item],
        destination: ModelContext
    ) throws {
        let copies = try destination.fetch(FetchDescriptor<ItemCopy>())
        let histories = try destination.fetch(FetchDescriptor<ItemCopyHistory>())
        let historiesByCopy = Dictionary(grouping: histories, by: \.copyID)

        for item in items {
            let itemCopies = copies.filter { $0.itemID == item.id }.sorted { $0.sortOrder < $1.sortOrder }
            guard itemCopies.count > 1 else { continue }
            let legacy = item.histories
            guard !legacy.isEmpty else { continue }

            for copy in itemCopies.dropFirst() {
                for candidate in historiesByCopy[copy.id] ?? [] where legacy.contains(where: { legacyHistory in
                    candidate.content == legacyHistory.content &&
                    candidate.sortOrder == legacyHistory.sortOrder &&
                    candidate.nodeID == legacyHistory.node?.id &&
                    candidate.relatedCharacterIDs == legacyHistory.relatedCharacters.map(\.id) &&
                    candidate.createdAt == legacyHistory.createdAt &&
                    candidate.updatedAt == legacyHistory.updatedAt
                }) {
                    destination.delete(candidate)
                }
            }
        }
    }
}
