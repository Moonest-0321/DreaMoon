//
//  Item.swift
//  Sailune
//
//  Created by 徐承佑 on Minguo 115/7/20.
//

import Foundation
import SwiftData

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemDescription: String
    var category: String
    var appearanceAndMaterial: String
    var usage: String
    var positiveAbility: String
    var negativeAbility: String
    var createdAt: Date
    var updatedAt: Date

    var book: Book?

    @Relationship(deleteRule: .cascade, inverse: \CharacterItem.item)
    var characterItems: [CharacterItem]

    @Relationship(deleteRule: .cascade, inverse: \ItemHistory.item)
    var histories: [ItemHistory]

    init(
        id: UUID = UUID(),
        name: String,
        itemDescription: String = "",
        category: String = "",
        appearanceAndMaterial: String = "",
        usage: String = "",
        positiveAbility: String = "",
        negativeAbility: String = "",
        book: Book? = nil
    ) {
        self.id = id
        self.name = name
        self.itemDescription = itemDescription
        self.category = category
        self.appearanceAndMaterial = appearanceAndMaterial
        self.usage = usage
        self.positiveAbility = positiveAbility
        self.negativeAbility = negativeAbility
        self.createdAt = Date()
        self.updatedAt = Date()
        self.book = book
        self.characterItems = []
        self.histories = []
    }
}

@Model
final class ItemHistory {
    @Attribute(.unique) var id: UUID
    var content: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var node: Node?
    var item: Item?
    var relatedCharacters: [Character]

    init(
        id: UUID = UUID(),
        content: String = "",
        sortOrder: Int = 0,
        node: Node? = nil,
        item: Item? = nil,
        relatedCharacters: [Character] = []
    ) {
        self.id = id
        self.content = content
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.node = node
        self.item = item
        self.relatedCharacters = relatedCharacters
    }
}

@MainActor
enum ItemOperations {
    /// Creates an independent item containing only the fields explicitly
    /// allowed by the V3 copy contract. Holders, histories, and writing
    /// references are intentionally absent.
    static func duplicate(
        _ source: Item,
        levels: [ItemLevel],
        in book: Book,
        context: ModelContext
    ) -> Item {
        let sourceName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let copy = Item(
            name: sourceName.isEmpty ? "新物品（副本）" : "\(sourceName)（副本）",
            itemDescription: source.itemDescription,
            category: source.category,
            appearanceAndMaterial: source.appearanceAndMaterial,
            usage: source.usage,
            book: book
        )
        context.insert(copy)

        for level in levels.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            context.insert(ItemLevel(
                itemID: copy.id,
                sortOrder: level.sortOrder,
                name: level.name,
                itemName: level.itemName,
                ability: level.ability,
                cost: level.cost,
                note: level.note
            ))
        }
        return copy
    }
}
