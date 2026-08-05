import Foundation
import SwiftData

@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var title: String
    var detail: String
    var isVisible: Bool = true
    var sortOrder: Double = 0.0

    // Node is a shared time locator. It does not own Event or other records.
    var node: Node?

    @Relationship(deleteRule: .nullify)
    var section: Section?

    @Relationship(deleteRule: .nullify)
    var characters: [Character]

    init(id: UUID = UUID(), title: String, detail: String = "") {
        self.id = id
        self.title = title
        self.detail = detail
        self.characters = []
    }
}
