import Foundation
import SwiftData

/// A predefined description of a possible item phase.  It deliberately has no
/// "current" flag and is linked by ID instead of a SwiftData relationship so
/// the legacy Item table remains stable.
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

extension ItemLevel {
    /// A compact, read-only description used by the collapsed level list.
    /// It is derived from existing fields, so V3.1 does not add a new stored
    /// property or change the item-level data contract.
    var compactOverview: String {
        let parts = [
            labeled("名稱", itemName),
            labeled("能力", ability),
            labeled("代價", cost),
            labeled("其他", note)
        ].compactMap { $0 }
        return parts.isEmpty ? "尚未填寫概述" : parts.joined(separator: " · ")
    }

    private func labeled(_ label: String, _ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "\(label)：\(trimmed)"
    }
}
