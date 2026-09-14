import Foundation
import SwiftData

struct PlanningRecordSourceReference: Equatable {
    let kind: PlanningRecordSourceKind
    let id: UUID
}

struct PlanningRecordProjection: Identifiable, Equatable {
    let sourceKind: PlanningRecordSourceKind
    let sourceID: UUID
    let bookID: UUID
    let nodeID: UUID
    let timelineID: UUID?
    let sectionID: UUID?
    let title: String
    let detail: String
    let sourceBadge: String
    let storyLineID: UUID?
    let stageID: UUID?
    let sortOrder: Int
    let updatedAt: Date

    var id: String { sourceKind.sourceKey(id: sourceID) }
}

@MainActor
enum PlanningRecordProjectionBuilder {
    static func build(
        book: Book,
        context: ModelContext,
        abilityStore: AbilityProgressStore,
        copyStore: ItemCopyStore,
        planningStore: StoryPlanningStore
    ) throws -> [PlanningRecordProjection] {
        let bookID = book.id
        let characters = try context.fetch(FetchDescriptor<Character>()).filter { $0.book?.id == bookID }
        let characterByID = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
        let items = try context.fetch(FetchDescriptor<Item>()).filter { $0.book?.id == bookID }
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let nodes = try context.fetch(FetchDescriptor<Node>()).filter { $0.timeline?.book?.id == bookID }
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result: [PlanningRecordProjection] = []

        func append(
            kind: PlanningRecordSourceKind,
            id: UUID,
            node: Node?,
            title: String,
            detail: String,
            badge: String,
            sortOrder: Int,
            updatedAt: Date
        ) {
            guard let node, node.isVisible else { return }
            let metadata = planningStore.recordMetadata(sourceKind: kind, sourceID: id)
            result.append(.init(
                sourceKind: kind,
                sourceID: id,
                bookID: bookID,
                nodeID: node.id,
                timelineID: node.timeline?.id,
                sectionID: node.section?.volume?.book?.id == bookID ? node.section?.id : nil,
                title: normalized(title, fallback: badge),
                detail: normalized(detail, fallback: "尚未填寫內容"),
                sourceBadge: badge,
                storyLineID: metadata?.storyLineID,
                stageID: metadata?.stageID,
                sortOrder: sortOrder,
                updatedAt: updatedAt
            ))
        }

        let abilities = try context.fetch(FetchDescriptor<CharacterAbility>()).filter { $0.character?.book?.id == bookID }
        for ability in abilities {
            let hasCurrentTimeline = abilityStore.connections.contains {
                $0.abilityID == ability.id && $0.characterID == ability.character?.id
            }
            guard !hasCurrentTimeline else { continue }
            let person = characterName(ability.character)
            for history in ability.history {
                append(kind: .abilityHistory, id: history.id, node: history.node,
                       title: "\(person)・\(normalized(ability.name, fallback: "未命名能力"))・\(history.stage)",
                       detail: history.descriptionText, badge: "人物・能力",
                       sortOrder: history.sortOrder, updatedAt: history.updatedAt)
            }
        }

        for appearance in try context.fetch(FetchDescriptor<CharacterAppearance>()) where appearance.character?.book?.id == bookID {
            let type = appearance.kind == .outfit ? "服裝" : "身體特徵"
            append(kind: .appearance, id: appearance.id, node: appearance.node,
                   title: "\(characterName(appearance.character))・\(type)",
                   detail: joined(appearance.descriptionText, appearance.usage, appearance.note),
                   badge: "人物・外觀", sortOrder: 0, updatedAt: appearance.updatedAt)
        }

        for psychology in try context.fetch(FetchDescriptor<CharacterPsychology>()) where psychology.character?.book?.id == bookID {
            let type: String
            switch psychology.kind { case .personality: type = "性格"; case .value: type = "價值觀"; case .motivation: type = "動機" }
            append(kind: .psychology, id: psychology.id, node: psychology.node,
                   title: "\(characterName(psychology.character))・\(type)", detail: psychology.content,
                   badge: "人物・心理", sortOrder: 0, updatedAt: psychology.updatedAt)
        }

        let characterItems = try context.fetch(FetchDescriptor<CharacterItem>()).filter {
            $0.character?.book?.id == bookID || $0.item?.book?.id == bookID
        }
        for characterItem in characterItems {
            for history in characterItem.history {
                append(kind: .characterItemHistory, id: history.id, node: history.node,
                       title: "\(characterName(characterItem.character))・\(normalized(characterItem.item?.name ?? "", fallback: "未命名物品"))",
                       detail: history.content, badge: "人物・物品",
                       sortOrder: history.sortOrder, updatedAt: history.updatedAt)
            }
        }

        for item in items {
            for history in item.histories {
                append(kind: .itemHistory, id: history.id, node: history.node,
                       title: normalized(item.name, fallback: "未命名物品"), detail: history.content,
                       badge: "物品歷史", sortOrder: history.sortOrder, updatedAt: history.updatedAt)
            }
        }

        let relationships = try context.fetch(FetchDescriptor<CharacterRelationship>()).filter {
            $0.sourceCharacter?.book?.id == bookID || $0.targetCharacter?.book?.id == bookID
        }
        for relationship in relationships {
            let pair = "\(characterName(relationship.sourceCharacter)) → \(characterName(relationship.targetCharacter))"
            for history in relationship.history {
                append(kind: .relationshipHistory, id: history.id, node: history.node,
                       title: "\(pair)・\(history.type)", detail: history.note,
                       badge: "人物・關係", sortOrder: history.sortOrder, updatedAt: history.updatedAt)
            }
        }

        let abilityByID = Dictionary(uniqueKeysWithValues: abilities.map { ($0.id, $0) })
        for history in abilityStore.histories {
            guard let connection = abilityStore.connections.first(where: { $0.id == history.connectionID }),
                  let character = characterByID[connection.characterID],
                  abilityStore.bookLinks.contains(where: { $0.abilityID == connection.abilityID && $0.bookID == bookID }) else { continue }
            let abilityName = abilityByID[connection.abilityID]?.name ?? "未命名能力"
            let levelName = UUID(uuidString: history.content).flatMap { levelID in
                abilityStore.levels.first { $0.id == levelID }?.name
            } ?? history.content
            append(kind: .abilityHistory, id: history.id, node: history.nodeID.flatMap { nodeByID[$0] },
                   title: "\(characterName(character))・\(abilityName)・\(levelName)", detail: levelName,
                   badge: "人物・能力", sortOrder: history.sortOrder, updatedAt: history.updatedAt)
        }

        let copyByID = Dictionary(uniqueKeysWithValues: copyStore.copies.map { ($0.id, $0) })
        for history in copyStore.histories {
            guard let copy = copyByID[history.copyID], let item = itemByID[copy.itemID] else { continue }
            append(kind: .itemCopyHistory, id: history.id, node: history.nodeID.flatMap { nodeByID[$0] },
                   title: copy.displayName(for: item), detail: history.content,
                   badge: "物品副本歷史", sortOrder: history.sortOrder, updatedAt: history.updatedAt)
        }

        return result.sorted {
            if $0.nodeID != $1.nodeID { return $0.nodeID.uuidString < $1.nodeID.uuidString }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id < $1.id
        }
    }

    static func validSourceKeys(_ projections: [PlanningRecordProjection]) -> Set<String> {
        Set(projections.map(\.id))
    }

    /// Metadata cleanup must consider hidden and temporarily unlocated sources,
    /// otherwise turning projection off would accidentally erase their placement.
    static func allSourceKeys(
        context: ModelContext,
        abilityStore: AbilityProgressStore,
        copyStore: ItemCopyStore
    ) throws -> Set<String> {
        var keys = Set<String>()
        func add(_ kind: PlanningRecordSourceKind, _ id: UUID) { keys.insert(kind.sourceKey(id: id)) }
        for value in try context.fetch(FetchDescriptor<CharacterAbility>()) {
            value.history.forEach { add(.abilityHistory, $0.id) }
        }
        try context.fetch(FetchDescriptor<CharacterAppearance>()).forEach { add(.appearance, $0.id) }
        try context.fetch(FetchDescriptor<CharacterPsychology>()).forEach { add(.psychology, $0.id) }
        for value in try context.fetch(FetchDescriptor<CharacterItem>()) {
            value.history.forEach { add(.characterItemHistory, $0.id) }
        }
        for value in try context.fetch(FetchDescriptor<Item>()) {
            value.histories.forEach { add(.itemHistory, $0.id) }
        }
        for value in try context.fetch(FetchDescriptor<CharacterRelationship>()) {
            value.history.forEach { add(.relationshipHistory, $0.id) }
        }
        abilityStore.histories.forEach { add(.abilityHistory, $0.id) }
        copyStore.histories.forEach { add(.itemCopyHistory, $0.id) }
        return keys
    }

    private static func characterName(_ character: Character?) -> String {
        normalized(character?.realName ?? "", fallback: "未命名角色")
    }

    private static func normalized(_ value: String, fallback: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    private static func joined(_ values: String...) -> String {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "｜")
    }
}
