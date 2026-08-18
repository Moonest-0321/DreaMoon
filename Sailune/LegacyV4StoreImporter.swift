import Foundation
import SwiftData

/// Copies the released V4 store into a new V5 store. The source file is never
/// mutated, so a failed import remains fully recoverable.
@MainActor
enum LegacyV4StoreImporter {
    static func importIfNeeded(from source: ModelContext, to destination: ModelContext) throws {
        let oldBooks = try source.fetch(FetchDescriptor<Book>())
        guard !oldBooks.isEmpty else { return }
        if try !destination.fetch(FetchDescriptor<Book>()).isEmpty {
            try validate(source: oldBooks.map(\.id), destination: destination.fetch(FetchDescriptor<Book>()).map(\.id), name: "書籍")
            return
        }

        let oldVolumes = try source.fetch(FetchDescriptor<Volume>())
        let oldSections = try source.fetch(FetchDescriptor<Section>())
        let oldProfiles = try source.fetch(FetchDescriptor<AuthorProfile>())
        let oldCharacters = try source.fetch(FetchDescriptor<Character>())
        let oldKinships = try source.fetch(FetchDescriptor<KinshipRelation>())
        let oldEras = try source.fetch(FetchDescriptor<Era>())
        let oldTimelines = try source.fetch(FetchDescriptor<Timeline>())
        let oldNodes = try source.fetch(FetchDescriptor<Node>())
        let oldEvents = try source.fetch(FetchDescriptor<Event>())

        var books: [UUID: Book] = [:]
        for old in oldBooks {
            let new = Book(id: old.id, title: old.title, author: old.author, synopsis: old.synopsis, coverColorData: old.coverColorData, createdAt: old.createdAt, updatedAt: old.updatedAt)
            destination.insert(new); books[old.id] = new
        }
        var volumes: [UUID: Volume] = [:]
        for old in oldVolumes {
            let new = Volume(id: old.id, title: old.title, sortOrder: old.sortOrder, createdAt: old.createdAt, book: old.book.flatMap { books[$0.id] })
            destination.insert(new); volumes[old.id] = new
        }
        var sections: [UUID: Section] = [:]
        for old in oldSections {
            let new = Section(id: old.id, title: old.title, content: old.content, sortOrder: old.sortOrder, wordCount: old.wordCount, createdAt: old.createdAt, updatedAt: old.updatedAt, volume: old.volume.flatMap { volumes[$0.id] })
            destination.insert(new); sections[old.id] = new
        }
        for old in oldProfiles {
            let new = AuthorProfile(penName: old.penName, bio: old.bio ?? "", avatarData: old.avatarData)
            new.id = old.id; new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }
        var characters: [UUID: Character] = [:]
        for old in oldCharacters {
            let new = Character(realName: old.realName, book: old.book.flatMap { books[$0.id] })
            new.id = old.id; new.isPinned = old.isPinned; new.sortOrder = old.sortOrder
            new.birthYear = old.birthYear; new.birthMonth = old.birthMonth; new.birthDay = old.birthDay; new.birthSeason = old.birthSeason
            new.originBackground = old.originBackground; new.originStory = old.originStory; new.gender = old.gender; new.notes = old.notes
            new.personality = old.personality; new.principles = old.principles; new.createdAt = old.createdAt; new.updatedAt = old.updatedAt
            destination.insert(new); characters[old.id] = new
        }
        for old in oldKinships {
            let new = KinshipRelation(role: KinshipRole(rawValue: old.roleRawValue) ?? .siblingMixed, targetCharacter: old.targetCharacter.flatMap { characters[$0.id] })
            new.id = old.id; new.sourceCharacter = old.sourceCharacter.flatMap { characters[$0.id] }; destination.insert(new)
        }
        var eras: [UUID: Era] = [:]
        for old in oldEras {
            let new = Era(id: old.id, name: old.name, color: old.color, startOrdinal: old.startOrdinal)
            destination.insert(new); eras[old.id] = new
        }
        var timelines: [UUID: Timeline] = [:]
        for old in oldTimelines {
            let new = Timeline(id: old.id, name: old.name, isPrimary: old.isPrimary, sortOrder: old.sortOrder)
            new.book = old.book.flatMap { books[$0.id] }; destination.insert(new); timelines[old.id] = new
        }
        var nodes: [UUID: Node] = [:]
        for old in oldNodes {
            let new = Node(id: old.id, year: old.year, month: old.month, day: old.day)
            new.isVisible = old.isVisible; new.sortOrder = old.sortOrder; new.era = old.era.flatMap { eras[$0.id] }
            new.timeline = old.timeline.flatMap { timelines[$0.id] }; new.section = old.section.flatMap { sections[$0.id] }
            destination.insert(new); nodes[old.id] = new
        }
        for old in oldEvents {
            let new = Event(id: old.id, title: old.title, detail: old.detail)
            new.isVisible = old.isVisible; new.sortOrder = old.sortOrder; new.node = old.node.flatMap { nodes[$0.id] }
            new.section = old.section.flatMap { sections[$0.id] }; new.characters = old.characters.compactMap { characters[$0.id] }
            destination.insert(new)
        }
        for old in oldBooks { books[old.id]?.currentEra = old.currentEra.flatMap { eras[$0.id] } }

        for old in try source.fetch(FetchDescriptor<CharacterProfile>()) {
            destination.insert(CharacterProfile(id: old.id, role: old.role, character: old.character.flatMap { characters[$0.id] }))
        }
        var aliases: [UUID: CharacterAlias] = [:]
        for old in try source.fetch(FetchDescriptor<CharacterAlias>()) {
            let new = CharacterAlias(id: old.id, name: old.name, note: old.note, character: old.character.flatMap { characters[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new); aliases[old.id] = new
        }
        var organizations: [UUID: Organization] = [:]
        for old in try source.fetch(FetchDescriptor<Organization>()) {
            let new = Organization(id: old.id, name: old.name, organizationDescription: old.organizationDescription, book: old.book.flatMap { books[$0.id] })
            destination.insert(new); organizations[old.id] = new
        }
        var memberships: [UUID: CharacterOrganization] = [:]
        for old in try source.fetch(FetchDescriptor<CharacterOrganization>()) {
            let new = CharacterOrganization(id: old.id, reason: old.reason, note: old.note, character: old.character.flatMap { characters[$0.id] }, organization: old.organization.flatMap { organizations[$0.id] }, joinNode: old.joinNode.flatMap { nodes[$0.id] })
            destination.insert(new); memberships[old.id] = new
        }
        var identities: [UUID: OrganizationIdentityHistory] = [:]
        for old in try source.fetch(FetchDescriptor<OrganizationIdentityHistory>()) {
            let new = OrganizationIdentityHistory(id: old.id, identity: old.identity, note: old.note, sortOrder: old.sortOrder, node: old.node.flatMap { nodes[$0.id] }, membership: old.membership.flatMap { memberships[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new); identities[old.id] = new
        }
        var abilities: [UUID: CharacterAbility] = [:]
        for old in try source.fetch(FetchDescriptor<CharacterAbility>()) {
            let new = CharacterAbility(id: old.id, name: old.name, currentStage: old.currentStage, stageDescription: old.stageDescription, summary: old.summary, character: old.character.flatMap { characters[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new); abilities[old.id] = new
        }
        for old in try source.fetch(FetchDescriptor<AbilityStageHistory>()) {
            let new = AbilityStageHistory(id: old.id, stage: old.stage, descriptionText: old.descriptionText, sortOrder: old.sortOrder, node: old.node.flatMap { nodes[$0.id] }, ability: old.ability.flatMap { abilities[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }
        for old in try source.fetch(FetchDescriptor<CharacterAppearance>()) {
            let new = CharacterAppearance(id: old.id, kind: old.kind, descriptionText: old.descriptionText, usage: old.usage, note: old.note, node: old.node.flatMap { nodes[$0.id] }, character: old.character.flatMap { characters[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }
        var psychologies: [UUID: CharacterPsychology] = [:]
        for old in try source.fetch(FetchDescriptor<CharacterPsychology>()) {
            let new = CharacterPsychology(id: old.id, kind: old.kind, content: old.content, node: old.node.flatMap { nodes[$0.id] }, character: old.character.flatMap { characters[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new); psychologies[old.id] = new
        }

        var items: [UUID: Item] = [:]
        for old in try source.fetch(FetchDescriptor<NovelWriterSchemaV4.Item>()) {
            let new = Item(id: old.id, name: old.name, itemDescription: old.itemDescription, book: old.book.flatMap { books[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new); items[old.id] = new
        }
        var characterItems: [UUID: CharacterItem] = [:]
        for old in try source.fetch(FetchDescriptor<NovelWriterSchemaV4.CharacterItem>()) {
            let new = CharacterItem(id: old.id, quantity: old.quantity, character: old.character.flatMap { characters[$0.id] }, item: old.item.flatMap { items[$0.id] })
            destination.insert(new); characterItems[old.id] = new
        }
        for old in try source.fetch(FetchDescriptor<NovelWriterSchemaV4.CharacterItemHistory>()) {
            let new = CharacterItemHistory(id: old.id, content: old.content, sortOrder: old.sortOrder, node: old.node.flatMap { nodes[$0.id] }, characterItem: old.characterItem.flatMap { characterItems[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }
        var relationships: [UUID: CharacterRelationship] = [:]
        for old in try source.fetch(FetchDescriptor<CharacterRelationship>()) {
            let new = CharacterRelationship(id: old.id, type: old.type, note: old.note, sourceCharacter: old.sourceCharacter.flatMap { characters[$0.id] }, targetCharacter: old.targetCharacter.flatMap { characters[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new); relationships[old.id] = new
        }
        for old in try source.fetch(FetchDescriptor<RelationshipHistory>()) {
            let new = RelationshipHistory(id: old.id, type: old.type, note: old.note, sortOrder: old.sortOrder, node: old.node.flatMap { nodes[$0.id] }, relationship: old.relationship.flatMap { relationships[$0.id] })
            new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }
        for old in try source.fetch(FetchDescriptor<CharacterSummary>()) {
            let new = CharacterSummary(id: old.id, character: old.character.flatMap { characters[$0.id] })
            new.alias = old.alias.flatMap { aliases[$0.id] }; new.organizationIdentity = old.organizationIdentity.flatMap { identities[$0.id] }
            new.ability = old.ability.flatMap { abilities[$0.id] }; new.psychology = old.psychology.flatMap { psychologies[$0.id] }
            new.relationship = old.relationship.flatMap { relationships[$0.id] }; destination.insert(new)
        }

        try destination.save()
        try validate(source: oldBooks.map(\.id), destination: destination.fetch(FetchDescriptor<Book>()).map(\.id), name: "書籍")
        try validate(source: oldCharacters.map(\.id), destination: destination.fetch(FetchDescriptor<Character>()).map(\.id), name: "角色")
        try validate(source: oldSections.map(\.id), destination: destination.fetch(FetchDescriptor<Section>()).map(\.id), name: "正文")
        try validate(source: items.keys, destination: destination.fetch(FetchDescriptor<Item>()).map(\.id), name: "物品")
    }

    private static func validate(source: some Sequence<UUID>, destination: some Sequence<UUID>, name: String) throws {
        let missing = Set(source).subtracting(Set(destination))
        guard missing.isEmpty else {
            throw NSError(domain: "Sailune.V4Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name)匯入不完整，缺少 \(missing.count) 筆"])
        }
    }
}
