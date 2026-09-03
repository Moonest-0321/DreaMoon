import SwiftUI

struct StoryTagListView: View {
    let book: Book
    let onOpen: ((StoryTag) -> Void)?
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var deleteTarget: StoryTag?
    @State private var errorMessage: String?

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
                        HStack(spacing: 8) {
                            Button { onOpen?(tag) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tag.title.isEmpty ? "未命名標籤" : tag.title).lineLimit(1)
                                    Text(section(for: tag)?.title.isEmpty == false ? section(for: tag)!.title : "未命名節")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { deleteTarget = tag } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("刪除標籤")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog("刪除標籤？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { tag in
            Button("刪除", role: .destructive) { delete(tag) }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { tag in
            Text("「\(tag.title.isEmpty ? "未命名標籤" : tag.title)」的標籤提示會消失，但正文不會被刪除。")
        }
        .alert("標籤無法刪除", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知錯誤") }
    }

    private func section(for tag: StoryTag) -> Section? {
        BookStructure.orderedSections(in: book).first { $0.id == tag.sectionID }
    }

    private func delete(_ tag: StoryTag) {
        do {
            try planningStore.deleteStoryTag(tag)
            deleteTarget = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
