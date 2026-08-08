//
//  Item.swift
//  DreaMoon
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
    var createdAt: Date
    var updatedAt: Date

    var book: Book?

    @Relationship(deleteRule: .cascade, inverse: \CharacterItem.item)
    var characterItems: [CharacterItem]

    init(
        id: UUID = UUID(),
        name: String,
        itemDescription: String = "",
        book: Book? = nil
    ) {
        self.id = id
        self.name = name
        self.itemDescription = itemDescription
        self.createdAt = Date()
        self.updatedAt = Date()
        self.book = book
        self.characterItems = []
    }
}
