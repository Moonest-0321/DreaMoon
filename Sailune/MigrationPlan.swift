import Foundation
import SwiftData

// Keep old schemas as snapshots. Do not point historical schemas at the live
// app models, or future model edits will accidentally rewrite the past.

enum NovelWriterSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            Volume.self,
            Section.self
        ]
    }

    @Model
    final class Book {
        var id: UUID = UUID()
        var title: String = ""
        var author: String = ""
        var synopsis: String = ""
        var coverColorData: Data?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Volume.book)
        var volumes: [Volume] = []

        init() { }
    }

    @Model
    final class Volume {
        var id: UUID = UUID()
        var title: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var book: Book?

        @Relationship(deleteRule: .cascade, inverse: \Section.volume)
        var sections: [Section] = []

        init() { }
    }

    @Model
    final class Section {
        var id: UUID = UUID()
        var title: String = ""
        var content: AttributedString = AttributedString("")
        var sortOrder: Int = 0
        var wordCount: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var volume: Volume?

        init() { }
    }
}

enum NovelWriterSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            Volume.self,
            Section.self,
            AuthorProfile.self,
            Character.self,
            KinshipRelation.self
        ]
    }

    @Model
    final class Book {
        var id: UUID = UUID()
        var title: String = ""
        var author: String = ""
        var synopsis: String = ""
        var coverColorData: Data?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Volume.book)
        var volumes: [Volume] = []

        @Relationship(deleteRule: .cascade, inverse: \Character.book)
        var characters: [Character] = []

        init() { }
    }

    @Model
    final class Volume {
        var id: UUID = UUID()
        var title: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var book: Book?

        @Relationship(deleteRule: .cascade, inverse: \Section.volume)
        var sections: [Section] = []

        init() { }
    }

    @Model
    final class Section {
        var id: UUID = UUID()
        var title: String = ""
        var content: AttributedString = AttributedString("")
        var sortOrder: Int = 0
        var wordCount: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var volume: Volume?

        init() { }
    }

    @Model
    final class AuthorProfile {
        var id: UUID = UUID()
        var penName: String = ""
        var bio: String?
        var avatarData: Data?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() { }
    }

    @Model
    final class Character {
        var id: UUID = UUID()
        var isPinned: Bool = false
        var sortOrder: Int = 0
        var realName: String = ""
        var birthYear: String?
        var birthMonth: String?
        var birthDay: String?
        var birthSeason: String?
        var originBackground: String?
        var originStory: String?
        var gender: String?
        var notes: String?

        @Relationship(deleteRule: .cascade, inverse: \KinshipRelation.sourceCharacter)
        var kinships: [KinshipRelation] = []

        var personality: String?
        var principles: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var book: Book?

        init() { }
    }

    @Model
    final class KinshipRelation {
        var id: UUID = UUID()
        var roleRawValue: String = ""
        var targetCharacter: Character?
        var sourceCharacter: Character?

        init() { }
    }
}

enum NovelWriterSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            // V3 was released using these top-level models. They must stay
            // schema-compatible so SwiftData can identify existing stores.
            Sailune.Book.self,
            Sailune.Volume.self,
            Sailune.Section.self,
            Sailune.AuthorProfile.self,
            Sailune.Character.self,
            Sailune.KinshipRelation.self,
            Sailune.Era.self,
            Sailune.Timeline.self,
            Sailune.Node.self,
            Sailune.Event.self
        ]
    }
}

enum NovelWriterSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Sailune.Book.self, Sailune.Volume.self, Sailune.Section.self,
            Sailune.AuthorProfile.self, Sailune.Character.self,
            Sailune.KinshipRelation.self, Sailune.Era.self,
            Sailune.Timeline.self, Sailune.Node.self, Sailune.Event.self,
            Item.self, Sailune.CharacterProfile.self,
            Sailune.CharacterAlias.self,
            Sailune.Organization.self, Sailune.CharacterOrganization.self,
            Sailune.OrganizationIdentityHistory.self,
            Sailune.CharacterAbility.self, Sailune.AbilityStageHistory.self,
            Sailune.CharacterAppearance.self, Sailune.CharacterPsychology.self,
            CharacterItem.self, CharacterItemHistory.self,
            Sailune.CharacterRelationship.self, Sailune.RelationshipHistory.self,
            Sailune.CharacterSummary.self
        ]
    }

    // Exact snapshots of the three released V4 entities whose live models
    // were later expanded during development. All other V4 entities above are
    // unchanged and therefore safely reuse their live definitions.
    @Model
    final class Item {
        @Attribute(.unique) var id: UUID
        var name: String
        var itemDescription: String
        var createdAt: Date
        var updatedAt: Date
        var book: Sailune.Book?

        @Relationship(deleteRule: .cascade, inverse: \CharacterItem.item)
        var characterItems: [CharacterItem]

        init(id: UUID = UUID(), name: String, itemDescription: String = "", book: Sailune.Book? = nil) {
            self.id = id
            self.name = name
            self.itemDescription = itemDescription
            self.createdAt = Date()
            self.updatedAt = Date()
            self.book = book
            self.characterItems = []
        }
    }

    @Model
    final class CharacterItem {
        @Attribute(.unique) var id: UUID
        var quantity: Int
        var character: Sailune.Character?
        var item: Item?

        @Relationship(deleteRule: .cascade, inverse: \CharacterItemHistory.characterItem)
        var history: [CharacterItemHistory]

        init(id: UUID = UUID(), quantity: Int = 1, character: Sailune.Character? = nil, item: Item? = nil) {
            self.id = id
            self.quantity = quantity
            self.character = character
            self.item = item
            self.history = []
        }
    }

    @Model
    final class CharacterItemHistory {
        @Attribute(.unique) var id: UUID
        var content: String
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        var node: Sailune.Node?
        var characterItem: CharacterItem?

        init(id: UUID = UUID(), content: String, sortOrder: Int = 0, node: Sailune.Node? = nil, characterItem: CharacterItem? = nil) {
            self.id = id
            self.content = content
            self.sortOrder = sortOrder
            self.createdAt = Date()
            self.updatedAt = Date()
            self.node = node
            self.characterItem = characterItem
        }
    }
}

/// V5 is additive. ItemLevel uses Item's stable UUID rather than changing the
/// V4 Item entity, which keeps the on-device migration lightweight and safe.
enum NovelWriterSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Sailune.Book.self, Sailune.Volume.self, Sailune.Section.self,
            Sailune.AuthorProfile.self, Sailune.Character.self,
            Sailune.KinshipRelation.self, Sailune.Era.self,
            Sailune.Timeline.self, Sailune.Node.self, Sailune.Event.self,
            Sailune.Item.self, Sailune.ItemHistory.self, Sailune.ItemLevel.self,
            Sailune.CharacterProfile.self, Sailune.CharacterAlias.self,
            Sailune.Organization.self, Sailune.CharacterOrganization.self,
            Sailune.OrganizationIdentityHistory.self,
            Sailune.CharacterAbility.self, Sailune.AbilityStageHistory.self,
            Sailune.CharacterAppearance.self, Sailune.CharacterPsychology.self,
            Sailune.CharacterItem.self, Sailune.CharacterItemHistory.self,
            Sailune.CharacterRelationship.self, Sailune.RelationshipHistory.self,
            Sailune.CharacterSummary.self
        ]
    }
}

enum NovelWriterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NovelWriterSchemaV4.self, NovelWriterSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: NovelWriterSchemaV4.self, toVersion: NovelWriterSchemaV5.self)]
    }
}

// The released V3 schema referenced live app model types, so it is not a safe
// immutable source for a SwiftData MigrationStage. V3 -> V4 is intentionally
// handled by the validated store bridge below. The next schema version must
// add a real V4 -> V5 MigrationStage and leave NovelWriterSchemaV4 unchanged.

private struct LegacyImportValidationError: LocalizedError {
    let entityName: String
    let missingIDs: Set<UUID>

    var errorDescription: String? {
        "V4 \(entityName) 匯入不完整，缺少 \(missingIDs.count) 筆資料"
    }
}

private enum LegacyImportValidator {
    static func validate(
        sourceIDs: some Sequence<UUID>,
        destinationIDs: some Sequence<UUID>,
        entityName: String
    ) throws {
        let missingIDs = Set(sourceIDs).subtracting(Set(destinationIDs))
        guard missingIDs.isEmpty else {
            throw LegacyImportValidationError(entityName: entityName, missingIDs: missingIDs)
        }
    }
}

@MainActor
enum LegacyV3StoreImporter {
    static func importIfNeeded(from source: ModelContext, to destination: ModelContext) throws {
        let sourceBooks = try source.fetch(FetchDescriptor<Sailune.Book>())
        guard !sourceBooks.isEmpty else { return }

        let sourceVolumes = try source.fetch(FetchDescriptor<Sailune.Volume>())
        let sourceSections = try source.fetch(FetchDescriptor<Sailune.Section>())
        let sourceProfiles = try source.fetch(FetchDescriptor<Sailune.AuthorProfile>())
        let sourceCharacters = try source.fetch(FetchDescriptor<Sailune.Character>())
        let sourceKinships = try source.fetch(FetchDescriptor<Sailune.KinshipRelation>())
        let sourceEras = try source.fetch(FetchDescriptor<Sailune.Era>())
        let sourceTimelines = try source.fetch(FetchDescriptor<Sailune.Timeline>())
        let sourceNodes = try source.fetch(FetchDescriptor<Sailune.Node>())
        let sourceEvents = try source.fetch(FetchDescriptor<Sailune.Event>())

        if try !destination.fetch(FetchDescriptor<Sailune.Book>()).isEmpty {
            try validateImport(
                sourceBooks: sourceBooks,
                sourceVolumes: sourceVolumes,
                sourceSections: sourceSections,
                sourceProfiles: sourceProfiles,
                sourceCharacters: sourceCharacters,
                sourceKinships: sourceKinships,
                sourceEras: sourceEras,
                sourceTimelines: sourceTimelines,
                sourceNodes: sourceNodes,
                sourceEvents: sourceEvents,
                destination: destination
            )
            return
        }

        var books: [UUID: Sailune.Book] = [:]
        for old in sourceBooks {
            let new = Sailune.Book(id: old.id, title: old.title, author: old.author, synopsis: old.synopsis, coverColorData: old.coverColorData, createdAt: old.createdAt, updatedAt: old.updatedAt)
            destination.insert(new); books[old.id] = new
        }

        var volumes: [UUID: Sailune.Volume] = [:]
        for old in sourceVolumes {
            let new = Sailune.Volume(id: old.id, title: old.title, sortOrder: old.sortOrder, createdAt: old.createdAt, book: old.book.flatMap { books[$0.id] })
            destination.insert(new); volumes[old.id] = new
        }
        var sections: [UUID: Sailune.Section] = [:]
        for old in sourceSections {
            let new = Sailune.Section(id: old.id, title: old.title, content: old.content, sortOrder: old.sortOrder, wordCount: old.wordCount, createdAt: old.createdAt, updatedAt: old.updatedAt, volume: old.volume.flatMap { volumes[$0.id] })
            destination.insert(new)
            sections[old.id] = new
        }
        for old in sourceProfiles {
            let new = Sailune.AuthorProfile(penName: old.penName, bio: old.bio ?? "", avatarData: old.avatarData)
            new.id = old.id; new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }

        var characters: [UUID: Sailune.Character] = [:]
        for old in sourceCharacters {
            let new = Sailune.Character(realName: old.realName, book: old.book.flatMap { books[$0.id] })
            new.id = old.id; new.isPinned = old.isPinned; new.sortOrder = old.sortOrder
            new.birthYear = old.birthYear; new.birthMonth = old.birthMonth; new.birthDay = old.birthDay; new.birthSeason = old.birthSeason
            new.originBackground = old.originBackground; new.originStory = old.originStory; new.gender = old.gender; new.notes = old.notes
            new.personality = old.personality; new.principles = old.principles; new.createdAt = old.createdAt; new.updatedAt = old.updatedAt
            destination.insert(new); characters[old.id] = new
        }
        for old in sourceKinships {
            let new = Sailune.KinshipRelation(role: KinshipRole(rawValue: old.roleRawValue) ?? .siblingMixed, targetCharacter: old.targetCharacter.flatMap { characters[$0.id] })
            new.id = old.id; new.sourceCharacter = old.sourceCharacter.flatMap { characters[$0.id] }; destination.insert(new)
        }

        var eras: [UUID: Sailune.Era] = [:]
        for old in sourceEras {
            let new = Sailune.Era(id: old.id, name: old.name, color: old.color, startOrdinal: old.startOrdinal)
            destination.insert(new); eras[old.id] = new
        }
        var timelines: [UUID: Sailune.Timeline] = [:]
        for old in sourceTimelines {
            let new = Sailune.Timeline(id: old.id, name: old.name, isPrimary: old.isPrimary, sortOrder: old.sortOrder)
            new.book = old.book.flatMap { books[$0.id] }; destination.insert(new); timelines[old.id] = new
        }
        var nodes: [UUID: Sailune.Node] = [:]
        for old in sourceNodes {
            let new = Sailune.Node(id: old.id, year: old.year, month: old.month, day: old.day)
            new.isVisible = old.isVisible; new.sortOrder = old.sortOrder; new.era = old.era.flatMap { eras[$0.id] }; new.timeline = old.timeline.flatMap { timelines[$0.id] }
            new.section = old.section.flatMap { sections[$0.id] }
            destination.insert(new); nodes[old.id] = new
        }
        for old in sourceEvents {
            let new = Sailune.Event(id: old.id, title: old.title, detail: old.detail)
            new.isVisible = old.isVisible; new.sortOrder = old.sortOrder; new.node = old.node.flatMap { nodes[$0.id] }
            new.characters = old.characters.compactMap { characters[$0.id] }; destination.insert(new)
        }
        for (id, book) in books { book.currentEra = sourceBooks.first(where: { $0.id == id })?.currentEra.flatMap { eras[$0.id] } }
        try destination.save()

        try validateImport(
            sourceBooks: sourceBooks,
            sourceVolumes: sourceVolumes,
            sourceSections: sourceSections,
            sourceProfiles: sourceProfiles,
            sourceCharacters: sourceCharacters,
            sourceKinships: sourceKinships,
            sourceEras: sourceEras,
            sourceTimelines: sourceTimelines,
            sourceNodes: sourceNodes,
            sourceEvents: sourceEvents,
            destination: destination
        )
    }

    private static func validateImport(
        sourceBooks: [Sailune.Book],
        sourceVolumes: [Sailune.Volume],
        sourceSections: [Sailune.Section],
        sourceProfiles: [Sailune.AuthorProfile],
        sourceCharacters: [Sailune.Character],
        sourceKinships: [Sailune.KinshipRelation],
        sourceEras: [Sailune.Era],
        sourceTimelines: [Sailune.Timeline],
        sourceNodes: [Sailune.Node],
        sourceEvents: [Sailune.Event],
        destination: ModelContext
    ) throws {
        try LegacyImportValidator.validate(sourceIDs: sourceBooks.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Book>()).map(\.id), entityName: "書籍")
        try LegacyImportValidator.validate(sourceIDs: sourceVolumes.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Volume>()).map(\.id), entityName: "卷冊")
        try LegacyImportValidator.validate(sourceIDs: sourceSections.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Section>()).map(\.id), entityName: "章節")
        try LegacyImportValidator.validate(sourceIDs: sourceProfiles.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.AuthorProfile>()).map(\.id), entityName: "作者資料")
        try LegacyImportValidator.validate(sourceIDs: sourceCharacters.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Character>()).map(\.id), entityName: "角色")
        try LegacyImportValidator.validate(sourceIDs: sourceKinships.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.KinshipRelation>()).map(\.id), entityName: "血緣關係")
        try LegacyImportValidator.validate(sourceIDs: sourceEras.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Era>()).map(\.id), entityName: "紀元")
        try LegacyImportValidator.validate(sourceIDs: sourceTimelines.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Timeline>()).map(\.id), entityName: "時間軸")
        try LegacyImportValidator.validate(sourceIDs: sourceNodes.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Node>()).map(\.id), entityName: "時間節點")
        try LegacyImportValidator.validate(sourceIDs: sourceEvents.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Event>()).map(\.id), entityName: "事件")
    }
}

@MainActor
enum LegacyV2StoreImporter {
    static func importIfNeeded(
        from source: ModelContext,
        to destination: ModelContext
    ) throws {
        let legacyBooks = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Book>())
        guard !legacyBooks.isEmpty else { return }

        let legacyProfiles = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.AuthorProfile>())
        let legacyVolumes = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Volume>())
        let legacySections = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Section>())
        let legacyCharacters = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Character>())
        let legacyKinships = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.KinshipRelation>())

        let existingBooks = try destination.fetch(FetchDescriptor<Sailune.Book>())
        if !existingBooks.isEmpty {
            try validateImport(
                legacyBooks: legacyBooks,
                legacyProfiles: legacyProfiles,
                legacyVolumes: legacyVolumes,
                legacySections: legacySections,
                legacyCharacters: legacyCharacters,
                legacyKinships: legacyKinships,
                destination: destination
            )
            for book in existingBooks {
                try TimelineEngine.Bootstrap.ensure(for: book, in: destination)
            }
            return
        }

        for legacy in legacyProfiles {
            let profile = Sailune.AuthorProfile(
                penName: legacy.penName,
                bio: legacy.bio ?? "",
                avatarData: legacy.avatarData
            )
            profile.id = legacy.id
            profile.createdAt = legacy.createdAt
            profile.updatedAt = legacy.updatedAt
            destination.insert(profile)
        }

        var booksByID: [UUID: Sailune.Book] = [:]
        for legacy in legacyBooks {
            let book = Sailune.Book(
                id: legacy.id,
                title: legacy.title,
                author: legacy.author,
                synopsis: legacy.synopsis,
                coverColorData: legacy.coverColorData,
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt
            )
            destination.insert(book)
            booksByID[legacy.id] = book
        }

        var volumesByID: [UUID: Sailune.Volume] = [:]
        for legacy in legacyVolumes {
            let volume = Sailune.Volume(
                id: legacy.id,
                title: legacy.title,
                sortOrder: legacy.sortOrder,
                createdAt: legacy.createdAt,
                book: legacy.book.flatMap { booksByID[$0.id] }
            )
            destination.insert(volume)
            volumesByID[legacy.id] = volume
        }

        for legacy in legacySections {
            let section = Sailune.Section(
                id: legacy.id,
                title: legacy.title,
                content: legacy.content,
                sortOrder: legacy.sortOrder,
                wordCount: legacy.wordCount,
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt,
                volume: legacy.volume.flatMap { volumesByID[$0.id] }
            )
            destination.insert(section)
        }

        var charactersByID: [UUID: Sailune.Character] = [:]
        for legacy in legacyCharacters {
            let character = Sailune.Character(
                realName: legacy.realName,
                book: legacy.book.flatMap { booksByID[$0.id] }
            )
            character.id = legacy.id
            character.isPinned = legacy.isPinned
            character.sortOrder = legacy.sortOrder
            character.birthYear = legacy.birthYear
            character.birthMonth = legacy.birthMonth
            character.birthDay = legacy.birthDay
            character.birthSeason = legacy.birthSeason
            character.originBackground = legacy.originBackground
            character.originStory = legacy.originStory
            character.gender = legacy.gender
            character.notes = legacy.notes
            character.personality = legacy.personality
            character.principles = legacy.principles
            character.createdAt = legacy.createdAt
            character.updatedAt = legacy.updatedAt
            destination.insert(character)
            charactersByID[legacy.id] = character
        }

        for legacy in legacyKinships {
            let relation = Sailune.KinshipRelation(
                role: KinshipRole(rawValue: legacy.roleRawValue) ?? .siblingMixed,
                targetCharacter: legacy.targetCharacter.flatMap { charactersByID[$0.id] }
            )
            relation.id = legacy.id
            relation.sourceCharacter = legacy.sourceCharacter.flatMap { charactersByID[$0.id] }
            destination.insert(relation)
        }

        try destination.save()

        for book in booksByID.values {
            try TimelineEngine.Bootstrap.ensure(for: book, in: destination)
        }

        try validateImport(
            legacyBooks: legacyBooks,
            legacyProfiles: legacyProfiles,
            legacyVolumes: legacyVolumes,
            legacySections: legacySections,
            legacyCharacters: legacyCharacters,
            legacyKinships: legacyKinships,
            destination: destination
        )
    }

    private static func validateImport(
        legacyBooks: [NovelWriterSchemaV2.Book],
        legacyProfiles: [NovelWriterSchemaV2.AuthorProfile],
        legacyVolumes: [NovelWriterSchemaV2.Volume],
        legacySections: [NovelWriterSchemaV2.Section],
        legacyCharacters: [NovelWriterSchemaV2.Character],
        legacyKinships: [NovelWriterSchemaV2.KinshipRelation],
        destination: ModelContext
    ) throws {
        try LegacyImportValidator.validate(sourceIDs: legacyBooks.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Book>()).map(\.id), entityName: "書籍")
        try LegacyImportValidator.validate(sourceIDs: legacyProfiles.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.AuthorProfile>()).map(\.id), entityName: "作者資料")
        try LegacyImportValidator.validate(sourceIDs: legacyVolumes.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Volume>()).map(\.id), entityName: "卷冊")
        try LegacyImportValidator.validate(sourceIDs: legacySections.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Section>()).map(\.id), entityName: "章節")
        try LegacyImportValidator.validate(sourceIDs: legacyCharacters.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.Character>()).map(\.id), entityName: "角色")
        try LegacyImportValidator.validate(sourceIDs: legacyKinships.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<Sailune.KinshipRelation>()).map(\.id), entityName: "血緣關係")
    }
}
