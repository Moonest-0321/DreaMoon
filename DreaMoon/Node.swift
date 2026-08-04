import Foundation
import SwiftData

@Model
final class Node {
    @Attribute(.unique) var id: UUID
    var year: Int
    var month: Int?
    var day: Int?
    var isVisible: Bool = true
    var sortOrder: Double = 0.0

    var era: Era?
    var timeline: Timeline?

    @Relationship(deleteRule: .nullify)
    var section: Section?

    @Relationship(deleteRule: .cascade, inverse: \Event.node)
    var events: [Event]

    init(id: UUID = UUID(), year: Int, month: Int? = nil, day: Int? = nil) {
        self.id = id
        self.year = year
        self.month = month
        self.day = day
        self.events = []
    }

    var absoluteOrdinal: Int {
        TimelineEngine.Core.ordinal(
            eraStart: era?.startOrdinal ?? 1,
            year: year, month: month, day: day
        )
    }
}
