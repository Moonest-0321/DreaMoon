import Foundation
import SwiftData

@Model
final class Timeline {
    @Attribute(.unique) var id: UUID
    var name: String
    var isPrimary: Bool
    var sortOrder: Double

    var book: Book?

    @Relationship(deleteRule: .cascade, inverse: \Node.timeline)
    var nodes: [Node]

    init(id: UUID = UUID(), name: String = "主時間軸", isPrimary: Bool = false, sortOrder: Double = 0.0) {
        self.id = id
        self.name = name
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.nodes = []
    }
}
