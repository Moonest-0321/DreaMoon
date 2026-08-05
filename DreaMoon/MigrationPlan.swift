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
            DreaMoon.Book.self,
            DreaMoon.Volume.self,
            DreaMoon.Section.self,
            DreaMoon.AuthorProfile.self,
            DreaMoon.Character.self,
            DreaMoon.KinshipRelation.self,
            DreaMoon.Era.self,
            DreaMoon.Timeline.self,
            DreaMoon.Node.self,
            DreaMoon.Event.self
        ]
    }
}

enum NovelWriterSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            DreaMoon.Book.self, DreaMoon.Volume.self, DreaMoon.Section.self,
            DreaMoon.AuthorProfile.self, DreaMoon.Character.self,
            DreaMoon.KinshipRelation.self, DreaMoon.Era.self,
            DreaMoon.Timeline.self, DreaMoon.Node.self, DreaMoon.Event.self,
            DreaMoon.Item.self, DreaMoon.CharacterProfile.self,
            DreaMoon.CharacterAlias.self,
            DreaMoon.Organization.self, DreaMoon.CharacterOrganization.self,
            DreaMoon.OrganizationIdentityHistory.self,
            DreaMoon.CharacterAbility.self, DreaMoon.AbilityStageHistory.self,
            DreaMoon.CharacterAppearance.self, DreaMoon.CharacterPsychology.self,
            DreaMoon.CharacterItem.self, DreaMoon.CharacterItemHistory.self,
            DreaMoon.CharacterRelationship.self, DreaMoon.RelationshipHistory.self,
            DreaMoon.CharacterSummary.self
        ]
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
        let sourceBooks = try source.fetch(FetchDescriptor<DreaMoon.Book>())
        guard !sourceBooks.isEmpty else { return }

        let sourceVolumes = try source.fetch(FetchDescriptor<DreaMoon.Volume>())
        let sourceSections = try source.fetch(FetchDescriptor<DreaMoon.Section>())
        let sourceProfiles = try source.fetch(FetchDescriptor<DreaMoon.AuthorProfile>())
        let sourceCharacters = try source.fetch(FetchDescriptor<DreaMoon.Character>())
        let sourceKinships = try source.fetch(FetchDescriptor<DreaMoon.KinshipRelation>())
        let sourceEras = try source.fetch(FetchDescriptor<DreaMoon.Era>())
        let sourceTimelines = try source.fetch(FetchDescriptor<DreaMoon.Timeline>())
        let sourceNodes = try source.fetch(FetchDescriptor<DreaMoon.Node>())
        let sourceEvents = try source.fetch(FetchDescriptor<DreaMoon.Event>())

        if try !destination.fetch(FetchDescriptor<DreaMoon.Book>()).isEmpty {
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

        var books: [UUID: DreaMoon.Book] = [:]
        for old in sourceBooks {
            let new = DreaMoon.Book(id: old.id, title: old.title, author: old.author, synopsis: old.synopsis, coverColorData: old.coverColorData, createdAt: old.createdAt, updatedAt: old.updatedAt)
            destination.insert(new); books[old.id] = new
        }

        var volumes: [UUID: DreaMoon.Volume] = [:]
        for old in sourceVolumes {
            let new = DreaMoon.Volume(id: old.id, title: old.title, sortOrder: old.sortOrder, createdAt: old.createdAt, book: old.book.flatMap { books[$0.id] })
            destination.insert(new); volumes[old.id] = new
        }
        var sections: [UUID: DreaMoon.Section] = [:]
        for old in sourceSections {
            let new = DreaMoon.Section(id: old.id, title: old.title, content: old.content, sortOrder: old.sortOrder, wordCount: old.wordCount, createdAt: old.createdAt, updatedAt: old.updatedAt, volume: old.volume.flatMap { volumes[$0.id] })
            destination.insert(new)
            sections[old.id] = new
        }
        for old in sourceProfiles {
            let new = DreaMoon.AuthorProfile(penName: old.penName, bio: old.bio ?? "", avatarData: old.avatarData)
            new.id = old.id; new.createdAt = old.createdAt; new.updatedAt = old.updatedAt; destination.insert(new)
        }

        var characters: [UUID: DreaMoon.Character] = [:]
        for old in sourceCharacters {
            let new = DreaMoon.Character(realName: old.realName, book: old.book.flatMap { books[$0.id] })
            new.id = old.id; new.isPinned = old.isPinned; new.sortOrder = old.sortOrder
            new.birthYear = old.birthYear; new.birthMonth = old.birthMonth; new.birthDay = old.birthDay; new.birthSeason = old.birthSeason
            new.originBackground = old.originBackground; new.originStory = old.originStory; new.gender = old.gender; new.notes = old.notes
            new.personality = old.personality; new.principles = old.principles; new.createdAt = old.createdAt; new.updatedAt = old.updatedAt
            destination.insert(new); characters[old.id] = new
        }
        for old in sourceKinships {
            let new = DreaMoon.KinshipRelation(role: KinshipRole(rawValue: old.roleRawValue) ?? .siblingMixed, targetCharacter: old.targetCharacter.flatMap { characters[$0.id] })
            new.id = old.id; new.sourceCharacter = old.sourceCharacter.flatMap { characters[$0.id] }; destination.insert(new)
        }

        var eras: [UUID: DreaMoon.Era] = [:]
        for old in sourceEras {
            let new = DreaMoon.Era(id: old.id, name: old.name, color: old.color, startOrdinal: old.startOrdinal)
            destination.insert(new); eras[old.id] = new
        }
        var timelines: [UUID: DreaMoon.Timeline] = [:]
        for old in sourceTimelines {
            let new = DreaMoon.Timeline(id: old.id, name: old.name, isPrimary: old.isPrimary, sortOrder: old.sortOrder)
            new.book = old.book.flatMap { books[$0.id] }; destination.insert(new); timelines[old.id] = new
        }
        var nodes: [UUID: DreaMoon.Node] = [:]
        for old in sourceNodes {
            let new = DreaMoon.Node(id: old.id, year: old.year, month: old.month, day: old.day)
            new.isVisible = old.isVisible; new.sortOrder = old.sortOrder; new.era = old.era.flatMap { eras[$0.id] }; new.timeline = old.timeline.flatMap { timelines[$0.id] }
            new.section = old.section.flatMap { sections[$0.id] }
            destination.insert(new); nodes[old.id] = new
        }
        for old in sourceEvents {
            let new = DreaMoon.Event(id: old.id, title: old.title, detail: old.detail)
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
        sourceBooks: [DreaMoon.Book],
        sourceVolumes: [DreaMoon.Volume],
        sourceSections: [DreaMoon.Section],
        sourceProfiles: [DreaMoon.AuthorProfile],
        sourceCharacters: [DreaMoon.Character],
        sourceKinships: [DreaMoon.KinshipRelation],
        sourceEras: [DreaMoon.Era],
        sourceTimelines: [DreaMoon.Timeline],
        sourceNodes: [DreaMoon.Node],
        sourceEvents: [DreaMoon.Event],
        destination: ModelContext
    ) throws {
        try LegacyImportValidator.validate(sourceIDs: sourceBooks.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Book>()).map(\.id), entityName: "書籍")
        try LegacyImportValidator.validate(sourceIDs: sourceVolumes.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Volume>()).map(\.id), entityName: "卷冊")
        try LegacyImportValidator.validate(sourceIDs: sourceSections.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Section>()).map(\.id), entityName: "章節")
        try LegacyImportValidator.validate(sourceIDs: sourceProfiles.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.AuthorProfile>()).map(\.id), entityName: "作者資料")
        try LegacyImportValidator.validate(sourceIDs: sourceCharacters.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Character>()).map(\.id), entityName: "角色")
        try LegacyImportValidator.validate(sourceIDs: sourceKinships.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.KinshipRelation>()).map(\.id), entityName: "血緣關係")
        try LegacyImportValidator.validate(sourceIDs: sourceEras.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Era>()).map(\.id), entityName: "紀元")
        try LegacyImportValidator.validate(sourceIDs: sourceTimelines.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Timeline>()).map(\.id), entityName: "時間軸")
        try LegacyImportValidator.validate(sourceIDs: sourceNodes.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Node>()).map(\.id), entityName: "時間節點")
        try LegacyImportValidator.validate(sourceIDs: sourceEvents.map(\.id), destinationIDs: try destination.fetch(FetchDescriptor<DreaMoon.Event>()).map(\.id), entityName: "事件")
    }
}

@MainActor
enum LegacyV2StoreImporter {
    static func importIfNeeded(
        from source: ModelContext,
        to destination: ModelContext
    ) throws {
        let existingBooks = try destination.fetch(FetchDescriptor<DreaMoon.Book>())
        guard existingBooks.isEmpty else { return }

        let legacyBooks = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Book>())
        guard !legacyBooks.isEmpty else { return }

        let legacyProfiles = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.AuthorProfile>())
        for legacy in legacyProfiles {
            let profile = DreaMoon.AuthorProfile(
                penName: legacy.penName,
                bio: legacy.bio ?? "",
                avatarData: legacy.avatarData
            )
            profile.id = legacy.id
            profile.createdAt = legacy.createdAt
            profile.updatedAt = legacy.updatedAt
            destination.insert(profile)
        }

        var booksByID: [UUID: DreaMoon.Book] = [:]
        for legacy in legacyBooks {
            let book = DreaMoon.Book(
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

        let legacyVolumes = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Volume>())
        var volumesByID: [UUID: DreaMoon.Volume] = [:]
        for legacy in legacyVolumes {
            let volume = DreaMoon.Volume(
                id: legacy.id,
                title: legacy.title,
                sortOrder: legacy.sortOrder,
                createdAt: legacy.createdAt,
                book: legacy.book.flatMap { booksByID[$0.id] }
            )
            destination.insert(volume)
            volumesByID[legacy.id] = volume
        }

        let legacySections = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Section>())
        for legacy in legacySections {
            let section = DreaMoon.Section(
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

        let legacyCharacters = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.Character>())
        var charactersByID: [UUID: DreaMoon.Character] = [:]
        for legacy in legacyCharacters {
            let character = DreaMoon.Character(
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

        let legacyKinships = try source.fetch(FetchDescriptor<NovelWriterSchemaV2.KinshipRelation>())
        for legacy in legacyKinships {
            let relation = DreaMoon.KinshipRelation(
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
    }
}
