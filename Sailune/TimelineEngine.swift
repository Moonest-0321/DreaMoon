import Foundation
import SwiftData

@MainActor
enum TimelineEngine {

    enum Core {
        nonisolated static func ordinal(eraStart: Int, year: Int, month: Int?, day: Int?) -> Int {
            let m = month ?? 0
            let d = day ?? 0
            return ((eraStart + year - 1) * 10000) + (m * 100) + d
        }
        nonisolated static func nodeLessThan(
            ordinalL: Int, orderL: Double, idL: String,
            ordinalR: Int, orderR: Double, idR: String
        ) -> Bool {
            if ordinalL != ordinalR { return ordinalL < ordinalR }
            if orderL != orderR { return orderL < orderR }
            return idL < idR
        }
        nonisolated static func visibleOnPrimary(nodeVisible: Bool?, eventVisible: Bool) -> Bool {
            (nodeVisible ?? false) && eventVisible
        }
    }

    enum Bootstrap {
        static func ensure(for book: Book, in context: ModelContext) throws {
            if book.currentEra == nil {
                let era = Era(name: "", color: "#888888", startOrdinal: 1)
                context.insert(era)
                book.currentEra = era
            }
            if !book.timelines.contains(where: \.isPrimary) {
                let primary = Timeline(name: "主時間軸", isPrimary: true, sortOrder: 0.0)
                context.insert(primary)
                primary.book = book
            }
            try context.save()
        }
    }

    enum EraChange {
        struct Input { var newName: String; var newColor: String }
        @discardableResult
        static func perform(for book: Book, input: Input, in context: ModelContext) throws -> (era: Era, node: Node) {
            try Bootstrap.ensure(for: book, in: context)
            guard let prevEra = book.currentEra else { throw EngineError.noCurrentEra }
            guard let primary = Query.primaryTimeline(for: book) else { throw EngineError.noPrimaryTimeline }
            let lastYear = (try Query.maxYear(of: prevEra, in: context)) ?? 1
            let newStart = prevEra.startOrdinal + lastYear
            let newEra = Era(name: input.newName, color: input.newColor, startOrdinal: newStart)
            context.insert(newEra)
            let node = Node(year: 1, month: 1, day: 1)
            context.insert(node)
            node.era = newEra
            node.timeline = primary
            node.section = nil
            book.currentEra = newEra
            try context.save()
            return (newEra, node)
        }
    }

    @discardableResult
    static func addSecondaryTimeline(for book: Book, name: String, in context: ModelContext) throws -> Timeline {
        let nextOrder = (book.timelines.map(\.sortOrder).max() ?? 0.0) + 1.0
        let timeline = Timeline(name: name, isPrimary: false, sortOrder: nextOrder)
        context.insert(timeline)
        timeline.book = book
        try context.save()
        return timeline
    }

    enum Visibility {
        static func isVisibleOnPrimaryAxis(_ event: Event) -> Bool {
            Core.visibleOnPrimary(nodeVisible: event.node?.isVisible, eventVisible: event.isVisible)
        }
    }

    enum Query {
        static func primaryTimeline(for book: Book) -> Timeline? {
            book.timelines.first(where: \.isPrimary)
        }
        static func maxYear(of era: Era, in context: ModelContext) throws -> Int? {
            let all = try context.fetch(FetchDescriptor<Node>())
            return all.filter { $0.era?.id == era.id }.map(\.year).max()
        }
        static func sorted(_ nodes: [Node]) -> [Node] { nodes.sorted(by: compareNodes) }
        static func nodesSorted(for timeline: Timeline) -> [Node] { sorted(timeline.nodes) }
        static func allNodesSorted(in context: ModelContext) throws -> [Node] {
            try context.fetch(FetchDescriptor<Node>()).sorted(by: compareNodes)
        }
        private static func compareNodes(_ lhs: Node, _ rhs: Node) -> Bool {
            Core.nodeLessThan(
                ordinalL: lhs.absoluteOrdinal, orderL: lhs.sortOrder, idL: lhs.id.uuidString,
                ordinalR: rhs.absoluteOrdinal, orderR: rhs.sortOrder, idR: rhs.id.uuidString
            )
        }
    }

    enum EngineError: Error, LocalizedError {
        case noCurrentEra, noPrimaryTimeline
        var errorDescription: String? {
            switch self {
            case .noCurrentEra: return "改元失敗：該書無 currentEra（bootstrap 未執行）。"
            case .noPrimaryTimeline: return "改元失敗：該書無主軸 Timeline（bootstrap 未執行）。"
            }
        }
    }

    #if DEBUG
    enum SelfTest {
        nonisolated static func run() {
            print("🧪 [Engine SelfTest] 開始（純計算核心，不碰 store）")
            let o1 = Core.ordinal(eraStart: 10, year: 1, month: nil, day: nil)
            let o2 = Core.ordinal(eraStart: 10, year: 1, month: 3,   day: nil)
            let o3 = Core.ordinal(eraStart: 10, year: 1, month: 3,   day: 5)
            let ok1 = (o1 == 100000 && o2 == 100300 && o3 == 100305)
            print("🧪 ordinal 年/月/日 = \(o1)/\(o2)/\(o3) → \(ok1 ? "✅" : "❌")")
            let idA = "AAAA", idB = "BBBB"
            let rByOrd   = Core.nodeLessThan(ordinalL: 3, orderL: 9, idL: idA, ordinalR: 5, orderR: 0, idR: idB)
            let rByOrder = Core.nodeLessThan(ordinalL: 5, orderL: 1, idL: idA, ordinalR: 5, orderR: 2, idR: idB)
            let rById    = Core.nodeLessThan(ordinalL: 5, orderL: 0, idL: idB, ordinalR: 5, orderR: 0, idR: idA)
            let ok2 = (rByOrd == true && rByOrder == true && rById == false)
            print("🧪 tie-break (ordinal/order/id→應false) = \(rByOrd)/\(rByOrder)/\(rById) → \(ok2 ? "✅" : "❌")")
            let v1 = Core.visibleOnPrimary(nodeVisible: true,  eventVisible: true)
            let v2 = Core.visibleOnPrimary(nodeVisible: false, eventVisible: true)
            let v3 = Core.visibleOnPrimary(nodeVisible: true,  eventVisible: false)
            let v4 = Core.visibleOnPrimary(nodeVisible: nil,   eventVisible: true)
            let ok3 = (v1 && !v2 && !v3 && !v4)
            print("🧪 AND (T/T, F/T, T/F, nil/T) = \(v1)/\(v2)/\(v3)/\(v4) → \(ok3 ? "✅" : "❌")")
            print((ok1 && ok2 && ok3)
                  ? "🧪 [Engine SelfTest] 全部通過 ✅ 引擎計算核心就緒"
                  : "🧪 [Engine SelfTest] 有項目失敗 ❌ 請貼 Console 給我")
        }
    }
    #endif
}
