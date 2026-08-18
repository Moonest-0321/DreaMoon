import Foundation
import SwiftData

/// A predefined description of a possible item phase.  It deliberately has no
/// "current" flag and is linked by ID instead of a SwiftData relationship so
/// adding it does not alter the released V4 Item table.
@Model
final class ItemLevel {
    @Attribute(.unique) var id: UUID
    var itemID: UUID
    var sortOrder: Int
    var name: String
    var itemName: String
    var ability: String
    var cost: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        itemID: UUID,
        sortOrder: Int = 0,
        name: String = "",
        itemName: String = "",
        ability: String = "",
        cost: String = "",
        note: String = ""
    ) {
        self.id = id
        self.itemID = itemID
        self.sortOrder = sortOrder
        self.name = name
        self.itemName = itemName
        self.ability = ability
        self.cost = cost
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
