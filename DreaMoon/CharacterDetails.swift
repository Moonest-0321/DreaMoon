import Foundation
import SwiftData

@Model
final class CharacterProfile {
    @Attribute(.unique) var id: UUID
    var role: String
    var character: Character?

    init(id: UUID = UUID(), role: String = "", character: Character? = nil) {
        self.id = id
        self.role = role
        self.character = character
    }
}

@Model
final class CharacterAlias {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var character: Character?

    init(id: UUID = UUID(), name: String, note: String = "", character: Character? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
        self.character = character
    }
}

@Model
final class Organization {
    @Attribute(.unique) var id: UUID
    var name: String
    var organizationDescription: String
    var book: Book?

    @Relationship(deleteRule: .cascade, inverse: \CharacterOrganization.organization)
    var memberships: [CharacterOrganization]

    init(id: UUID = UUID(), name: String, organizationDescription: String = "", book: Book? = nil) {
        self.id = id
        self.name = name
        self.organizationDescription = organizationDescription
        self.book = book
        self.memberships = []
    }
}

@Model
final class CharacterOrganization {
    @Attribute(.unique) var id: UUID
    var reason: String
    var note: String
    var joinNode: Node?
    var character: Character?
    var organization: Organization?

    @Relationship(deleteRule: .cascade, inverse: \OrganizationIdentityHistory.membership)
    var identityHistory: [OrganizationIdentityHistory]

    init(id: UUID = UUID(), reason: String = "", note: String = "", character: Character? = nil, organization: Organization? = nil, joinNode: Node? = nil) {
        self.id = id
        self.reason = reason
        self.note = note
        self.character = character
        self.organization = organization
        self.joinNode = joinNode
        self.identityHistory = []
    }
}

@Model
final class OrganizationIdentityHistory {
    @Attribute(.unique) var id: UUID
    var identity: String
    var note: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var node: Node?
    var membership: CharacterOrganization?

    init(id: UUID = UUID(), identity: String, note: String = "", sortOrder: Int = 0, node: Node? = nil, membership: CharacterOrganization? = nil) {
        self.id = id
        self.identity = identity
        self.note = note
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.membership = membership
    }
}

@Model
final class CharacterAbility {
    @Attribute(.unique) var id: UUID
    var name: String
    var currentStage: String
    var stageDescription: String
    var summary: String
    var createdAt: Date
    var updatedAt: Date
    var character: Character?

    @Relationship(deleteRule: .cascade, inverse: \AbilityStageHistory.ability)
    var history: [AbilityStageHistory]

    init(id: UUID = UUID(), name: String, currentStage: String = "", stageDescription: String = "", summary: String = "", character: Character? = nil) {
        self.id = id
        self.name = name
        self.currentStage = currentStage
        self.stageDescription = stageDescription
        self.summary = summary
        self.createdAt = Date()
        self.updatedAt = Date()
        self.character = character
        self.history = []
    }
}

@Model
final class AbilityStageHistory {
    @Attribute(.unique) var id: UUID
    var stage: String
    var descriptionText: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var node: Node?
    var ability: CharacterAbility?

    init(id: UUID = UUID(), stage: String, descriptionText: String = "", sortOrder: Int = 0, node: Node? = nil, ability: CharacterAbility? = nil) {
        self.id = id
        self.stage = stage
        self.descriptionText = descriptionText
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.ability = ability
    }
}

enum CharacterAppearanceKind: String, CaseIterable, Identifiable {
    case outfit
    case bodyFeature
    var id: String { rawValue }
}

@Model
final class CharacterAppearance {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var descriptionText: String
    var usage: String
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var node: Node?
    var character: Character?

    var kind: CharacterAppearanceKind {
        get { CharacterAppearanceKind(rawValue: kindRawValue) ?? .outfit }
        set { kindRawValue = newValue.rawValue }
    }

    init(id: UUID = UUID(), kind: CharacterAppearanceKind, descriptionText: String, usage: String = "", note: String = "", node: Node? = nil, character: Character? = nil) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.descriptionText = descriptionText
        self.usage = usage
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.character = character
    }
}

enum CharacterPsychologyKind: String, CaseIterable, Identifiable {
    case personality
    case value
    case motivation
    var id: String { rawValue }
}

@Model
final class CharacterPsychology {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var node: Node?
    var character: Character?

    var kind: CharacterPsychologyKind {
        get { CharacterPsychologyKind(rawValue: kindRawValue) ?? .personality }
        set { kindRawValue = newValue.rawValue }
    }

    init(id: UUID = UUID(), kind: CharacterPsychologyKind, content: String, node: Node? = nil, character: Character? = nil) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.character = character
    }
}

@Model
final class CharacterItem {
    @Attribute(.unique) var id: UUID
    var quantity: Int
    var character: Character?
    var item: Item?

    @Relationship(deleteRule: .cascade, inverse: \CharacterItemHistory.characterItem)
    var history: [CharacterItemHistory]

    init(id: UUID = UUID(), quantity: Int = 1, character: Character? = nil, item: Item? = nil) {
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
    var node: Node?
    var characterItem: CharacterItem?

    init(id: UUID = UUID(), content: String, sortOrder: Int = 0, node: Node? = nil, characterItem: CharacterItem? = nil) {
        self.id = id
        self.content = content
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.characterItem = characterItem
    }
}

@Model
final class CharacterRelationship {
    @Attribute(.unique) var id: UUID
    var type: String
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var sourceCharacter: Character?
    var targetCharacter: Character?

    @Relationship(deleteRule: .cascade, inverse: \RelationshipHistory.relationship)
    var history: [RelationshipHistory]

    init(id: UUID = UUID(), type: String, note: String = "", sourceCharacter: Character? = nil, targetCharacter: Character? = nil) {
        self.id = id
        self.type = type
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceCharacter = sourceCharacter
        self.targetCharacter = targetCharacter
        self.history = []
    }
}

@Model
final class RelationshipHistory {
    @Attribute(.unique) var id: UUID
    var type: String
    var note: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var node: Node?
    var relationship: CharacterRelationship?

    init(id: UUID = UUID(), type: String, note: String = "", sortOrder: Int = 0, node: Node? = nil, relationship: CharacterRelationship? = nil) {
        self.id = id
        self.type = type
        self.note = note
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.relationship = relationship
    }
}

@Model
final class CharacterSummary {
    @Attribute(.unique) var id: UUID
    var character: Character?
    var alias: CharacterAlias?
    var organizationIdentity: OrganizationIdentityHistory?
    var ability: CharacterAbility?
    var psychology: CharacterPsychology?
    var relationship: CharacterRelationship?

    init(id: UUID = UUID(), character: Character? = nil) {
        self.id = id
        self.character = character
    }
}
