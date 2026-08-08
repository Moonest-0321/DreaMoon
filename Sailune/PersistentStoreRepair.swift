import Foundation
import SwiftData
import AppKit

private protocol StoreUUIDModel {
    var id: UUID { get }
}

extension Book: StoreUUIDModel { }
extension Volume: StoreUUIDModel { }
extension Section: StoreUUIDModel { }
extension Timeline: StoreUUIDModel { }
extension Node: StoreUUIDModel { }
extension Character: StoreUUIDModel { }
extension Item: StoreUUIDModel { }
extension Organization: StoreUUIDModel { }
extension CharacterProfile: StoreUUIDModel { }
extension CharacterAlias: StoreUUIDModel { }
extension CharacterOrganization: StoreUUIDModel { }
extension OrganizationIdentityHistory: StoreUUIDModel { }
extension CharacterAbility: StoreUUIDModel { }
extension AbilityStageHistory: StoreUUIDModel { }
extension CharacterAppearance: StoreUUIDModel { }
extension CharacterPsychology: StoreUUIDModel { }
extension CharacterItem: StoreUUIDModel { }
extension CharacterItemHistory: StoreUUIDModel { }
extension CharacterRelationship: StoreUUIDModel { }
extension RelationshipHistory: StoreUUIDModel { }
extension CharacterSummary: StoreUUIDModel { }
extension KinshipRelation: StoreUUIDModel { }

/// Repairs relationships that point at rows already removed from the V4 store.
/// SwiftData traps when such a relationship is read, so this runs before views
/// and other backfills fetch relationship-backed models.
@MainActor
enum PersistentStoreRepair {
    static func run(in context: ModelContext) throws {
        try repairBookHierarchy(in: context)
        try repairCharacterHierarchy(in: context)
        try repairOwnedHistories(in: context)
        try repairOptionalReferences(in: context)
    }

    private static func repairBookHierarchy(in context: ModelContext) throws {
        let books = try context.fetch(FetchDescriptor<Book>())

        let validVolumeIDs = try linkedIDs(books) { bookID in
            try context.fetch(FetchDescriptor<Volume>(predicate: #Predicate { $0.book?.id == bookID })).map(\.id)
        }
        let validTimelineIDs = try linkedIDs(books) { bookID in
            try context.fetch(FetchDescriptor<Timeline>(predicate: #Predicate { $0.book?.id == bookID })).map(\.id)
        }
        let validCharacterIDs = try linkedIDs(books) { bookID in
            try context.fetch(FetchDescriptor<Character>(predicate: #Predicate { $0.book?.id == bookID })).map(\.id)
        }

        try deleteModelsNotIn(validVolumeIDs, from: context.fetch(FetchDescriptor<Volume>()), in: context)
        try deleteModelsNotIn(validTimelineIDs, from: context.fetch(FetchDescriptor<Timeline>()), in: context)
        try deleteModelsNotIn(validCharacterIDs, from: context.fetch(FetchDescriptor<Character>()), in: context)

        // Item and Organization may intentionally be unassigned, so retain nil
        // relationships while removing only non-nil links to missing books.
        var validItemIDs = Set(try context.fetch(
            FetchDescriptor<Item>(predicate: #Predicate { $0.book == nil })
        ).map(\.id))
        validItemIDs.formUnion(try linkedIDs(books) { bookID in
            try context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.book?.id == bookID })).map(\.id)
        })
        var validOrganizationIDs = Set(try context.fetch(
            FetchDescriptor<Organization>(predicate: #Predicate { $0.book == nil })
        ).map(\.id))
        validOrganizationIDs.formUnion(try linkedIDs(books) { bookID in
            try context.fetch(FetchDescriptor<Organization>(predicate: #Predicate { $0.book?.id == bookID })).map(\.id)
        })
        try deleteModelsNotIn(validItemIDs, from: context.fetch(FetchDescriptor<Item>()), in: context)
        try deleteModelsNotIn(validOrganizationIDs, from: context.fetch(FetchDescriptor<Organization>()), in: context)
        try context.save()

        let volumes = try context.fetch(FetchDescriptor<Volume>())
        let validSectionIDs = try linkedIDs(volumes) { volumeID in
            try context.fetch(FetchDescriptor<Section>(predicate: #Predicate { $0.volume?.id == volumeID })).map(\.id)
        }
        try deleteModelsNotIn(validSectionIDs, from: context.fetch(FetchDescriptor<Section>()), in: context)

        let timelines = try context.fetch(FetchDescriptor<Timeline>())
        let validNodeIDs = try linkedIDs(timelines) { timelineID in
            try context.fetch(FetchDescriptor<Node>(predicate: #Predicate { $0.timeline?.id == timelineID })).map(\.id)
        }
        try deleteModelsNotIn(validNodeIDs, from: context.fetch(FetchDescriptor<Node>()), in: context)
        try context.save()
    }

    private static func repairCharacterHierarchy(in context: ModelContext) throws {
        let characters = try context.fetch(FetchDescriptor<Character>())

        let validProfileIDs = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterProfile>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let validAliasIDs = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterAlias>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let validAbilityIDs = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterAbility>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let validAppearanceIDs = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterAppearance>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let validPsychologyIDs = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterPsychology>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let validSummaryIDs = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterSummary>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }

        try deleteModelsNotIn(validProfileIDs, from: context.fetch(FetchDescriptor<CharacterProfile>()), in: context)
        try deleteModelsNotIn(validAliasIDs, from: context.fetch(FetchDescriptor<CharacterAlias>()), in: context)
        try deleteModelsNotIn(validAbilityIDs, from: context.fetch(FetchDescriptor<CharacterAbility>()), in: context)
        try deleteModelsNotIn(validAppearanceIDs, from: context.fetch(FetchDescriptor<CharacterAppearance>()), in: context)
        try deleteModelsNotIn(validPsychologyIDs, from: context.fetch(FetchDescriptor<CharacterPsychology>()), in: context)
        try deleteModelsNotIn(validSummaryIDs, from: context.fetch(FetchDescriptor<CharacterSummary>()), in: context)

        let organizations = try context.fetch(FetchDescriptor<Organization>())
        let membershipsByCharacter = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterOrganization>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let membershipsByOrganization = try linkedIDs(organizations) { organizationID in
            try context.fetch(FetchDescriptor<CharacterOrganization>(predicate: #Predicate { $0.organization?.id == organizationID })).map(\.id)
        }
        try deleteModelsNotIn(
            membershipsByCharacter.intersection(membershipsByOrganization),
            from: context.fetch(FetchDescriptor<CharacterOrganization>()),
            in: context
        )

        let items = try context.fetch(FetchDescriptor<Item>())
        let characterItemsByCharacter = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterItem>(predicate: #Predicate { $0.character?.id == characterID })).map(\.id)
        }
        let characterItemsByItem = try linkedIDs(items) { itemID in
            try context.fetch(FetchDescriptor<CharacterItem>(predicate: #Predicate { $0.item?.id == itemID })).map(\.id)
        }
        try deleteModelsNotIn(
            characterItemsByCharacter.intersection(characterItemsByItem),
            from: context.fetch(FetchDescriptor<CharacterItem>()),
            in: context
        )

        let relationshipsBySource = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterRelationship>(predicate: #Predicate { $0.sourceCharacter?.id == characterID })).map(\.id)
        }
        let relationshipsByTarget = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<CharacterRelationship>(predicate: #Predicate { $0.targetCharacter?.id == characterID })).map(\.id)
        }
        try deleteModelsNotIn(
            relationshipsBySource.intersection(relationshipsByTarget),
            from: context.fetch(FetchDescriptor<CharacterRelationship>()),
            in: context
        )

        let kinshipsBySource = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<KinshipRelation>(predicate: #Predicate { $0.sourceCharacter?.id == characterID })).map(\.id)
        }
        let kinshipsByTarget = try linkedIDs(characters) { characterID in
            try context.fetch(FetchDescriptor<KinshipRelation>(predicate: #Predicate { $0.targetCharacter?.id == characterID })).map(\.id)
        }
        try deleteModelsNotIn(
            kinshipsBySource.intersection(kinshipsByTarget),
            from: context.fetch(FetchDescriptor<KinshipRelation>()),
            in: context
        )
        try context.save()
    }

    private static func repairOwnedHistories(in context: ModelContext) throws {
        let memberships = try context.fetch(FetchDescriptor<CharacterOrganization>())
        let validIdentityIDs = try linkedIDs(memberships) { membershipID in
            try context.fetch(FetchDescriptor<OrganizationIdentityHistory>(predicate: #Predicate { $0.membership?.id == membershipID })).map(\.id)
        }
        try deleteModelsNotIn(validIdentityIDs, from: context.fetch(FetchDescriptor<OrganizationIdentityHistory>()), in: context)

        let abilities = try context.fetch(FetchDescriptor<CharacterAbility>())
        let validAbilityHistoryIDs = try linkedIDs(abilities) { abilityID in
            try context.fetch(FetchDescriptor<AbilityStageHistory>(predicate: #Predicate { $0.ability?.id == abilityID })).map(\.id)
        }
        try deleteModelsNotIn(validAbilityHistoryIDs, from: context.fetch(FetchDescriptor<AbilityStageHistory>()), in: context)

        let characterItems = try context.fetch(FetchDescriptor<CharacterItem>())
        let validItemHistoryIDs = try linkedIDs(characterItems) { characterItemID in
            try context.fetch(FetchDescriptor<CharacterItemHistory>(predicate: #Predicate { $0.characterItem?.id == characterItemID })).map(\.id)
        }
        try deleteModelsNotIn(validItemHistoryIDs, from: context.fetch(FetchDescriptor<CharacterItemHistory>()), in: context)

        let relationships = try context.fetch(FetchDescriptor<CharacterRelationship>())
        let validRelationshipHistoryIDs = try linkedIDs(relationships) { relationshipID in
            try context.fetch(FetchDescriptor<RelationshipHistory>(predicate: #Predicate { $0.relationship?.id == relationshipID })).map(\.id)
        }
        try deleteModelsNotIn(validRelationshipHistoryIDs, from: context.fetch(FetchDescriptor<RelationshipHistory>()), in: context)
        try context.save()
    }

    private static func repairOptionalReferences(in context: ModelContext) throws {
        let nodes = try context.fetch(FetchDescriptor<Node>())
        let nodeIDs = Set(nodes.map(\.id))

        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<AbilityStageHistory>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<AbilityStageHistory>(predicate: #Predicate { $0.node?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<AbilityStageHistory>(predicate: #Predicate { $0.node == nil })).map(\.id)),
            clear: { $0.node = nil }
        )
        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<CharacterAppearance>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<CharacterAppearance>(predicate: #Predicate { $0.node?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<CharacterAppearance>(predicate: #Predicate { $0.node == nil })).map(\.id)),
            clear: { $0.node = nil }
        )
        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<CharacterPsychology>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<CharacterPsychology>(predicate: #Predicate { $0.node?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<CharacterPsychology>(predicate: #Predicate { $0.node == nil })).map(\.id)),
            clear: { $0.node = nil }
        )
        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<CharacterOrganization>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<CharacterOrganization>(predicate: #Predicate { $0.joinNode?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<CharacterOrganization>(predicate: #Predicate { $0.joinNode == nil })).map(\.id)),
            clear: { $0.joinNode = nil }
        )
        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<OrganizationIdentityHistory>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<OrganizationIdentityHistory>(predicate: #Predicate { $0.node?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<OrganizationIdentityHistory>(predicate: #Predicate { $0.node == nil })).map(\.id)),
            clear: { $0.node = nil }
        )
        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<CharacterItemHistory>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<CharacterItemHistory>(predicate: #Predicate { $0.node?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<CharacterItemHistory>(predicate: #Predicate { $0.node == nil })).map(\.id)),
            clear: { $0.node = nil }
        )
        try nullifyInvalidNodeLinks(
            in: context.fetch(FetchDescriptor<RelationshipHistory>()),
            validNodeIDs: nodeIDs,
            linkedIDs: { nodeID in
                try context.fetch(FetchDescriptor<RelationshipHistory>(predicate: #Predicate { $0.node?.id == nodeID })).map(\.id)
            },
            nilIDs: Set(try context.fetch(FetchDescriptor<RelationshipHistory>(predicate: #Predicate { $0.node == nil })).map(\.id)),
            clear: { $0.node = nil }
        )
        try context.save()
    }

    private static func linkedIDs<Parent>(
        _ parents: [Parent],
        fetch: (UUID) throws -> [UUID]
    ) throws -> Set<UUID> where Parent: PersistentModel & StoreUUIDModel {
        var result = Set<UUID>()
        for parent in parents {
            result.formUnion(try fetch(parent.id))
        }
        return result
    }

    private static func deleteModelsNotIn<Model>(
        _ validIDs: Set<UUID>,
        from models: [Model],
        in context: ModelContext
    ) throws where Model: PersistentModel & StoreUUIDModel {
        for model in models {
            if !validIDs.contains(model.id) { context.delete(model) }
        }
    }

    private static func nullifyInvalidNodeLinks<Model>(
        in models: [Model],
        validNodeIDs: Set<UUID>,
        linkedIDs: (UUID) throws -> [UUID],
        nilIDs: Set<UUID>,
        clear: (Model) -> Void
    ) throws where Model: PersistentModel & StoreUUIDModel {
        var validModelIDs = nilIDs
        for nodeID in validNodeIDs { validModelIDs.formUnion(try linkedIDs(nodeID)) }
        for model in models {
            if !validModelIDs.contains(model.id) { clear(model) }
        }
    }
}

/// Centralized destructive operations for root models whose generated inverse
/// relationships do not cover every dependent model.
@MainActor
enum PersistentModelDeletion {
    static func deleteBook(_ book: Book, in context: ModelContext) throws {
        let bookID = book.id

        let characters = try context.fetch(
            FetchDescriptor<Character>(predicate: #Predicate { $0.book?.id == bookID })
        )
        for character in characters { try deleteCharacter(character, in: context, save: false) }

        let timelines = try context.fetch(
            FetchDescriptor<Timeline>(predicate: #Predicate { $0.book?.id == bookID })
        )
        for timeline in timelines { try deleteTimeline(timeline, in: context, save: false) }

        let volumes = try context.fetch(
            FetchDescriptor<Volume>(predicate: #Predicate { $0.book?.id == bookID })
        )
        for volume in volumes { try deleteVolume(volume, in: context, save: false) }

        try context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.book?.id == bookID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<Organization>(predicate: #Predicate { $0.book?.id == bookID }))
            .forEach(context.delete)

        context.delete(book)
        try context.save()
    }

    static func deleteCharacter(_ character: Character, in context: ModelContext, save: Bool = true) throws {
        let characterID = character.id
        NotificationCenter.default.post(name: .dreaMoonWillChangeCharacterReferences, object: nil)
        var changedSectionIDs = Set<UUID>()

        // 刪除設定集資料時保留作者的正文，只移除已失效的角色連結樣式。
        for section in try context.fetch(FetchDescriptor<Section>()) {
            let attributed = NSMutableAttributedString(attributedString: NSAttributedString(section.content))
            var ranges: [NSRange] = []
            attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                guard let value, CharacterReferenceLink.characterID(from: value) == characterID else { return }
                ranges.append(range)
            }
            guard !ranges.isEmpty else { continue }
            for range in ranges.reversed() {
                attributed.removeAttribute(.link, range: range)
            }
            section.content = AttributedString(attributed)
            section.updatedAt = Date()
            section.volume?.book?.updatedAt = Date()
            changedSectionIDs.insert(section.id)
        }

        try context.fetch(FetchDescriptor<CharacterProfile>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterAlias>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterAbility>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterAppearance>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterPsychology>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterSummary>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterOrganization>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<CharacterItem>(predicate: #Predicate { $0.character?.id == characterID }))
            .forEach(context.delete)

        let sourcedRelationships = try context.fetch(
            FetchDescriptor<CharacterRelationship>(predicate: #Predicate { $0.sourceCharacter?.id == characterID })
        )
        let targetedRelationships = try context.fetch(
            FetchDescriptor<CharacterRelationship>(predicate: #Predicate { $0.targetCharacter?.id == characterID })
        )
        for relationship in uniqueModels(sourcedRelationships + targetedRelationships) { context.delete(relationship) }

        let sourcedKinships = try context.fetch(
            FetchDescriptor<KinshipRelation>(predicate: #Predicate { $0.sourceCharacter?.id == characterID })
        )
        let targetedKinships = try context.fetch(
            FetchDescriptor<KinshipRelation>(predicate: #Predicate { $0.targetCharacter?.id == characterID })
        )
        for kinship in uniqueModels(sourcedKinships + targetedKinships) { context.delete(kinship) }

        // Event.characters is a to-many reference without a declared inverse.
        for event in try context.fetch(FetchDescriptor<Event>()) {
            event.characters.removeAll { $0.id == characterID }
        }

        context.delete(character)
        if save {
            try context.save()
            if !changedSectionIDs.isEmpty {
                NotificationCenter.default.post(name: .dreaMoonCharacterReferencesChanged, object: changedSectionIDs)
            }
        }
    }

    static func deleteNodes(_ nodes: [Node], in context: ModelContext, save: Bool = true) throws {
        for node in nodes {
            let nodeID = node.id
            try context.fetch(FetchDescriptor<AbilityStageHistory>(predicate: #Predicate { $0.node?.id == nodeID }))
                .forEach { $0.node = nil }
            try context.fetch(FetchDescriptor<CharacterAppearance>(predicate: #Predicate { $0.node?.id == nodeID }))
                .forEach { $0.node = nil }
            try context.fetch(FetchDescriptor<CharacterPsychology>(predicate: #Predicate { $0.node?.id == nodeID }))
                .forEach { $0.node = nil }
            try context.fetch(FetchDescriptor<CharacterOrganization>(predicate: #Predicate { $0.joinNode?.id == nodeID }))
                .forEach { $0.joinNode = nil }
            try context.fetch(FetchDescriptor<OrganizationIdentityHistory>(predicate: #Predicate { $0.node?.id == nodeID }))
                .forEach { $0.node = nil }
            try context.fetch(FetchDescriptor<CharacterItemHistory>(predicate: #Predicate { $0.node?.id == nodeID }))
                .forEach { $0.node = nil }
            try context.fetch(FetchDescriptor<RelationshipHistory>(predicate: #Predicate { $0.node?.id == nodeID }))
                .forEach { $0.node = nil }
            context.delete(node)
        }
        if save { try context.save() }
    }

    static func deleteTimeline(_ timeline: Timeline, in context: ModelContext, save: Bool = true) throws {
        let timelineID = timeline.id
        let nodes = try context.fetch(
            FetchDescriptor<Node>(predicate: #Predicate { $0.timeline?.id == timelineID })
        )
        try deleteNodes(nodes, in: context, save: false)
        context.delete(timeline)
        if save { try context.save() }
    }

    static func deleteSection(_ section: Section, in context: ModelContext, save: Bool = true) throws {
        let sectionID = section.id
        try context.fetch(FetchDescriptor<Node>(predicate: #Predicate { $0.section?.id == sectionID }))
            .forEach { $0.section = nil }
        try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.section?.id == sectionID }))
            .forEach { $0.section = nil }
        context.delete(section)
        if save { try context.save() }
    }

    static func deleteVolume(_ volume: Volume, in context: ModelContext, save: Bool = true) throws {
        let volumeID = volume.id
        let sections = try context.fetch(
            FetchDescriptor<Section>(predicate: #Predicate { $0.volume?.id == volumeID })
        )
        for section in sections { try deleteSection(section, in: context, save: false) }
        context.delete(volume)
        if save { try context.save() }
    }

    private static func uniqueModels<Model>(_ models: [Model]) -> [Model]
    where Model: PersistentModel & StoreUUIDModel {
        var seen = Set<UUID>()
        return models.filter { seen.insert($0.id).inserted }
    }
}
