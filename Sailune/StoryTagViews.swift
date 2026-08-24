import SwiftUI

struct StoryTagListView: View {
    let book: Book
    let onOpen: ((StoryTag) -> Void)?
    @Environment(StoryPlanningStore.self) private var planningStore

    private var tags: [StoryTag] {
        planningStore.tags(bookID: book.id)
    }

    var body: some View {
        let sectionOrder = Dictionary(uniqueKeysWithValues: BookStructure.orderedSections(in: book).enumerated().map { ($0.element.id, $0.offset) })
        List {
            SwiftUI.ForEach(0..<StoryTagKind.allCases.count, id: \.self) { index in
                let kind = StoryTagKind.allCases[index]
                let grouped = tags.filter { $0.kindRawValue == kind.rawValue }.sorted { lhs, rhs in
                    let left = sectionOrder[lhs.sectionID] ?? Int.max
                    let right = sectionOrder[rhs.sectionID] ?? Int.max
                    return left == right ? lhs.anchorOffset < rhs.anchorOffset : left < right
                }
                SwiftUI.Section(kind.rawValue) {
                    if grouped.isEmpty {
                        Text("尚無標籤").font(.caption).foregroundStyle(.tertiary)
                    }
                    SwiftUI.ForEach(grouped) { tag in
                        Button { onOpen?(tag) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tag.title.isEmpty ? "未命名標籤" : tag.title).lineLimit(1)
                                Text(section(for: tag)?.title.isEmpty == false ? section(for: tag)!.title : "未命名節")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func section(for tag: StoryTag) -> Section? {
        BookStructure.orderedSections(in: book).first { $0.id == tag.sectionID }
    }
}
