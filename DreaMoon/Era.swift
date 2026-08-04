import Foundation
import SwiftData

@Model
final class Era {
    @Attribute(.unique) var id: UUID
    var name: String
    var color: String
    var startOrdinal: Int

    @Relationship(deleteRule: .nullify, inverse: \Book.currentEra)
    var books: [Book]

    @Relationship(deleteRule: .nullify, inverse: \Node.era)
    var nodes: [Node]

    init(id: UUID = UUID(), name: String = "", color: String = "#888888", startOrdinal: Int = 1) {
        self.id = id
        self.name = name
        self.color = color
        self.startOrdinal = startOrdinal
        self.books = []
        self.nodes = []
    }
}
