import Foundation
import SwiftData
import Observation

enum AbilityProgressSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [AbilityLevel.self, CharacterAbilityConnection.self, CharacterAbilityHistory.self, AbilityBookLink.self]
    }
}

@Model final class AbilityLevel {
    @Attribute(.unique) var id: UUID
    var abilityID: UUID; var sortOrder: Int; var name: String
    var descriptionText: String; var cost: String; var note: String
    var createdAt: Date; var updatedAt: Date
    init(id: UUID = UUID(), abilityID: UUID, sortOrder: Int = 0, name: String = "", descriptionText: String = "", cost: String = "", note: String = "") {
        self.id = id; self.abilityID = abilityID; self.sortOrder = sortOrder; self.name = name
        self.descriptionText = descriptionText; self.cost = cost; self.note = note; self.createdAt = Date(); self.updatedAt = Date()
    }
}

@Model final class CharacterAbilityConnection {
    @Attribute(.unique) var id: UUID
    var characterID: UUID; var abilityID: UUID; var currentLevelID: UUID?
    var createdAt: Date; var updatedAt: Date
    init(id: UUID = UUID(), characterID: UUID, abilityID: UUID, currentLevelID: UUID? = nil) {
        self.id = id; self.characterID = characterID; self.abilityID = abilityID; self.currentLevelID = currentLevelID; self.createdAt = Date(); self.updatedAt = Date()
    }
}

@Model final class CharacterAbilityHistory {
    @Attribute(.unique) var id: UUID
    var connectionID: UUID; var content: String; var sortOrder: Int; var nodeID: UUID?
    var createdAt: Date; var updatedAt: Date
    init(id: UUID = UUID(), connectionID: UUID, content: String = "", sortOrder: Int = 0, nodeID: UUID? = nil) {
        self.id = id; self.connectionID = connectionID; self.content = content; self.sortOrder = sortOrder; self.nodeID = nodeID; self.createdAt = Date(); self.updatedAt = Date()
    }
}

@Model final class AbilityBookLink {
    @Attribute(.unique) var id: UUID
    var abilityID: UUID; var bookID: UUID
    init(id: UUID = UUID(), abilityID: UUID, bookID: UUID) { self.id = id; self.abilityID = abilityID; self.bookID = bookID }
}

@MainActor @Observable final class AbilityProgressStore {
    /// Keep the container alive for as long as any of its model instances are
    /// displayed. Releasing it resets the context and invalidates those models.
    let container: ModelContainer
    private let context: ModelContext
    private(set) var levels: [AbilityLevel] = []; private(set) var connections: [CharacterAbilityConnection] = []
    private(set) var histories: [CharacterAbilityHistory] = []; private(set) var bookLinks: [AbilityBookLink] = []
    init(container: ModelContainer) throws { self.container = container; context = container.mainContext; context.autosaveEnabled = true; try reload() }
    func reload() throws { levels = try context.fetch(FetchDescriptor<AbilityLevel>()); connections = try context.fetch(FetchDescriptor<CharacterAbilityConnection>()); histories = try context.fetch(FetchDescriptor<CharacterAbilityHistory>()); bookLinks = try context.fetch(FetchDescriptor<AbilityBookLink>()) }
    func save() { try? context.save() }
    func register(abilityID: UUID, bookID: UUID) { guard !bookLinks.contains(where: { $0.abilityID == abilityID }) else { return }; let link = AbilityBookLink(abilityID: abilityID, bookID: bookID); context.insert(link); bookLinks.append(link); save() }
    func addLevel(abilityID: UUID) { let level = AbilityLevel(abilityID: abilityID, sortOrder: (levels.filter { $0.abilityID == abilityID }.map(\.sortOrder).max() ?? -1) + 1, name: "新等級"); context.insert(level); levels.append(level); save() }
    func deleteAbilityLevel(_ level: AbilityLevel) { connections.filter { $0.currentLevelID == level.id }.forEach { $0.currentLevelID = nil }; context.delete(level); levels.removeAll { $0.id == level.id }; save() }
    func connect(characterID: UUID, abilityID: UUID) { guard !connections.contains(where: { $0.characterID == characterID && $0.abilityID == abilityID }) else { return }; let connection = CharacterAbilityConnection(characterID: characterID, abilityID: abilityID); context.insert(connection); connections.append(connection); save() }
    func deleteConnection(_ connection: CharacterAbilityConnection) { histories.filter { $0.connectionID == connection.id }.forEach(context.delete); histories.removeAll { $0.connectionID == connection.id }; context.delete(connection); connections.removeAll { $0.id == connection.id }; save() }
    func addHistory(connectionID: UUID) { let history = CharacterAbilityHistory(connectionID: connectionID, sortOrder: (histories.filter { $0.connectionID == connectionID }.map(\.sortOrder).max() ?? -1) + 1); context.insert(history); histories.append(history); save() }
    func deleteHistory(_ history: CharacterAbilityHistory) { context.delete(history); histories.removeAll { $0.id == history.id }; save() }
    func deleteAbility(abilityID: UUID) { levels.filter { $0.abilityID == abilityID }.forEach(context.delete); connections.filter { $0.abilityID == abilityID }.forEach(deleteConnection); bookLinks.filter { $0.abilityID == abilityID }.forEach(context.delete); save() }
    func migrateLegacy(_ abilities: [CharacterAbility]) {
        for ability in abilities {
            guard let character = ability.character else { continue }
            register(abilityID: ability.id, bookID: character.book?.id ?? UUID())
            guard !connections.contains(where: { $0.abilityID == ability.id && $0.characterID == character.id }) else { continue }
            connect(characterID: character.id, abilityID: ability.id)
            guard let connection = connections.first(where: { $0.abilityID == ability.id && $0.characterID == character.id }) else { continue }
            for entry in ability.history where !histories.contains(where: { $0.connectionID == connection.id && $0.sortOrder == entry.sortOrder }) {
                context.insert(CharacterAbilityHistory(connectionID: connection.id, content: [entry.stage, entry.descriptionText].filter { !$0.isEmpty }.joined(separator: "："), sortOrder: entry.sortOrder, nodeID: entry.node?.id))
            }
        }
        save()
    }
}
