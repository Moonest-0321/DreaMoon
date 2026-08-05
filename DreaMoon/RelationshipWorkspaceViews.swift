import SwiftUI
import SwiftData

struct RelationshipGroup: Identifiable {
    let source: Character
    let target: Character
    var relationships: [CharacterRelationship]
    var kinships: [KinshipRelation]

    var id: String { "\(source.id.uuidString)-\(target.id.uuidString)" }

    var currentNames: [String] {
        let blood = kinships.map { $0.role.displayName }
        let general = relationships.map { relationship in
            relationship.history.sorted { $0.sortOrder < $1.sortOrder }.last?.type ?? relationship.type
        }
        var seen = Set<String>()
        return (blood + general).filter { seen.insert($0).inserted }
    }

    var latestNode: Node? {
        relationships
            .flatMap(\.history)
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .node
    }

    var latestUpdate: Date {
        relationships.map(\.updatedAt).max() ?? .distantPast
    }
}

enum RelationshipGroupBuilder {
    static func directGroups(for center: Character, relationships: [CharacterRelationship]) -> [RelationshipGroup] {
        var groups: [String: RelationshipGroup] = [:]

        func add(source: Character, target: Character, relationship: CharacterRelationship? = nil, kinship: KinshipRelation? = nil) {
            let key = "\(source.id.uuidString)-\(target.id.uuidString)"
            var group = groups[key] ?? RelationshipGroup(source: source, target: target, relationships: [], kinships: [])
            if let relationship { group.relationships.append(relationship) }
            if let kinship { group.kinships.append(kinship) }
            groups[key] = group
        }

        for kinship in center.kinships {
            if let target = kinship.targetCharacter { add(source: center, target: target, kinship: kinship) }
        }
        for relationship in relationships {
            if relationship.sourceCharacter?.id == center.id, let target = relationship.targetCharacter {
                add(source: center, target: target, relationship: relationship)
            } else if relationship.targetCharacter?.id == center.id, let source = relationship.sourceCharacter {
                add(source: source, target: center, relationship: relationship)
            }
        }
        return groups.values.sorted {
            if $0.target.sortOrder != $1.target.sortOrder { return $0.target.sortOrder < $1.target.sortOrder }
            return $0.source.sortOrder < $1.source.sortOrder
        }
    }
}

struct RelationshipListView: View {
    let center: Character
    let book: Book
    let searchText: String
    let selectedFilter: String
    @Query(sort: \CharacterRelationship.updatedAt, order: .reverse) private var allRelationships: [CharacterRelationship]
    @State private var selectedGroup: RelationshipGroup?

    private var groups: [RelationshipGroup] {
        RelationshipGroupBuilder.directGroups(
            for: center,
            relationships: allRelationships.filter {
                $0.sourceCharacter?.book?.id == book.id || $0.targetCharacter?.book?.id == book.id
            }
        )
    }
    private var visibleGroups: [RelationshipGroup] {
        groups.filter { group in
            let peer = group.source.id == center.id ? group.target : group.source
            let matchesSearch = searchText.isEmpty || peer.realName.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = selectedFilter == "全部" ||
                (selectedFilter == "血緣" ? !group.kinships.isEmpty : group.currentNames.contains(selectedFilter))
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        Group {
            if visibleGroups.isEmpty {
                ContentUnavailableView("尚未建立人物關係", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                List(visibleGroups) { group in
                    Button { selectedGroup = group } label: {
                        HStack(spacing: 12) {
                            Text(group.source.id == center.id
                                 ? (group.target.realName.isEmpty ? "未命名角色" : group.target.realName)
                                 : (group.source.realName.isEmpty ? "未命名角色" : group.source.realName))
                                .frame(width: 72, alignment: .leading)
                            Text("\(group.source.realName) → \(group.target.realName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 112, alignment: .leading)
                            Text(group.currentNames.joined(separator: "、"))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(timestampLabel(group.latestNode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .popover(item: $selectedGroup, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) { group in
            RelationshipDetailSheet(group: group, book: book)
        }
    }

    private func timestampLabel(_ node: Node?) -> String {
        guard let node else { return "" }
        if let section = node.section, !section.title.isEmpty { return section.title }
        var value = node.year > 0 ? "\(node.year)年" : ""
        if let month = node.month { value += "\(month)月" }
        if let day = node.day { value += "\(day)日" }
        return value
    }
}

struct RelationshipDetailSheet: View {
    let group: RelationshipGroup
    let book: Book
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(group.source.realName) → \(group.target.realName)")
                        .font(.headline)
                    Spacer()
                    Button("完成") { dismiss() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("目前關係").font(.subheadline)
                    ForEach(group.currentNames, id: \.self) { Text($0) }
                }

                if !group.relationships.isEmpty {
                    Divider()
                    ForEach(group.relationships) { relationship in
                        RelationshipDetailRelationRow(relationship: relationship, book: book, onDeleted: { dismiss() })
                    }
                }
                if !group.kinships.isEmpty {
                    Divider()
                    ForEach(group.kinships) { kinship in
                        KinshipDetailRelationRow(kinship: kinship, onDeleted: { dismiss() })
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(width: 420, height: 430)
    }

}

private struct RelationshipDetailRelationRow: View {
    @Bindable var relationship: CharacterRelationship
    let book: Book
    @Environment(\.modelContext) private var modelContext
    let onDeleted: () -> Void
    @State private var confirmDelete = false

    private var currentType: String {
        relationship.history.sorted { $0.sortOrder < $1.sortOrder }.last?.type ?? relationship.type
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(currentType).fontWeight(.medium)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            if !relationship.note.isEmpty {
                Text(relationship.note).font(.caption).foregroundStyle(.secondary)
            }
            RelationshipHistoryEditor(relationship: relationship, book: book)
        }
        .confirmationDialog("刪除關係？", isPresented: $confirmDelete) {
            Button("刪除", role: .destructive) {
                modelContext.delete(relationship)
                onDeleted()
            }
        } message: {
            Text("此關係的歷史會一併刪除。")
        }
    }
}

private struct KinshipDetailRelationRow: View {
    let kinship: KinshipRelation
    let onDeleted: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            Text(kinship.role.displayName).fontWeight(.medium)
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("刪除血緣關係？", isPresented: $confirmDelete) {
            Button("刪除", role: .destructive) { deleteKinship() }
        }
    }

    private func deleteKinship() {
        let source = kinship.sourceCharacter
        let target = kinship.targetCharacter
        if let source, let target,
           let inverse = target.kinships.first(where: {
               $0.targetCharacter?.id == source.id && $0.role == kinship.role.inverseRole
           }) {
            modelContext.delete(inverse)
        }
        modelContext.delete(kinship)
        onDeleted()
    }
}

struct AddGeneralRelationshipSheet: View {
    let center: Character
    let book: Book
    let characters: [Character]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var targetID: UUID?
    @State private var relationshipName = "朋友"
    @State private var reverseDirection = false
    @State private var note = ""
    @State private var node: Node?

    @Query private var allRelationships: [CharacterRelationship]

    private var availableCharacters: [Character] {
        characters.filter { candidate in
            let sourceID = reverseDirection ? candidate.id : center.id
            let targetID = reverseDirection ? center.id : candidate.id
            return !allRelationships.contains {
                $0.sourceCharacter?.id == sourceID && $0.targetCharacter?.id == targetID
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增關係").font(.headline)
            Form {
                Picker("關聯角色", selection: $targetID) {
                    Text("選擇角色").tag(Optional<UUID>.none)
                    ForEach(availableCharacters) { item in
                        Text(item.realName.isEmpty ? "未命名角色" : item.realName).tag(Optional(item.id))
                    }
                }
                TextField("關係", text: $relationshipName)
                Toggle("反向", isOn: $reverseDirection)
                Text(directionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("簡述", text: $note, axis: .vertical)
                HStack {
                    Text("時間")
                    CharacterNodePicker(book: book, node: $node)
                }
            }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("建立", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(targetID == nil || relationshipName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 410, height: 370)
        .onChange(of: reverseDirection) { targetID = nil }
    }

    private func create() {
        guard let targetID,
              let selected = availableCharacters.first(where: { $0.id == targetID }) else { return }
        let source = reverseDirection ? selected : center
        let target = reverseDirection ? center : selected
        let relationship = CharacterRelationship(type: relationshipName, note: note, sourceCharacter: source, targetCharacter: target)
        let history = RelationshipHistory(type: relationshipName, note: note, node: node, relationship: relationship)
        relationship.history.append(history)
        modelContext.insert(relationship)
        modelContext.insert(history)
        dismiss()
    }

    private var directionLabel: String {
        guard let targetID, let target = availableCharacters.first(where: { $0.id == targetID }) else { return "" }
        let source = reverseDirection ? target : center
        let destination = reverseDirection ? center : target
        return "\(source.realName) → \(destination.realName)"
    }
}
