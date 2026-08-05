import SwiftUI
import SwiftData

struct CharacterNodePicker: View {
    let book: Book
    @Binding var node: Node?
    @Query(sort: \Node.sortOrder) private var allNodes: [Node]
    @State private var showingTimestampEditor = false

    private var nodes: [Node] {
        allNodes
            .filter { $0.timeline?.book?.id == book.id }
            .sorted { $0.absoluteOrdinal < $1.absoluteOrdinal }
    }

    var body: some View {
        HStack(spacing: 5) {
            Picker("時間定位", selection: Binding(
                get: { node?.id },
                set: { selectedID in node = selectedID.flatMap { id in nodes.first { $0.id == id } } }
            )) {
                Text("無時間定位").tag(Optional<UUID>.none)
                ForEach(nodes) { item in
                    Text(nodeLabel(item)).tag(Optional(item.id))
                }
            }
            .labelsHidden()
            .help(nodes.isEmpty ? "尚無時間點，可按右側加號建立" : "選擇此筆資料的時間定位")

            Button { showingTimestampEditor = true } label: {
                Image(systemName: node == nil ? "plus.circle" : "pencil.circle")
            }
            .buttonStyle(.plain)
            .help(node == nil ? "建立時間戳記" : "修改此筆資料的時間戳記")
        }
        .sheet(isPresented: $showingTimestampEditor) {
            CharacterTimestampEditorSheet(book: book, existingNode: node) { savedNode in
                node = savedNode
            }
        }
    }

    private func nodeLabel(_ node: Node) -> String {
        var dateParts: [String] = []
        if node.year > 0 { dateParts.append("\(node.year)年") }
        if let month = node.month { dateParts.append("\(month)月") }
        if let day = node.day { dateParts.append("\(day)日") }
        let date = dateParts.isEmpty ? "未設定" : dateParts.joined()
        let era = node.era?.name.isEmpty == false ? "\(node.era!.name)・" : ""
        let timeline = node.timeline?.name ?? "時間軸"
        let section = node.section.map { "・\($0.title)" } ?? ""
        let hidden = node.isVisible ? "" : "・隱藏"
        return "\(timeline)・\(era)\(date)\(section)\(hidden)"
    }
}

private struct CharacterTimestampEditorSheet: View {
    let book: Book
    let existingNode: Node?
    let onSave: (Node) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Timeline.sortOrder) private var allTimelines: [Timeline]
    @Query(sort: \Era.startOrdinal) private var allEras: [Era]
    @Query(sort: \Section.sortOrder) private var allSections: [Section]

    @State private var selectedTimelineID: UUID?
    @State private var selectedEraID: UUID?
    @State private var yearText = ""
    @State private var monthText = ""
    @State private var dayText = ""
    @State private var selectedSectionID: UUID?
    @State private var isVisible = true

    init(book: Book, existingNode: Node?, onSave: @escaping (Node) -> Void) {
        self.book = book
        self.existingNode = existingNode
        self.onSave = onSave
        let existingYear = existingNode?.year ?? 0
        _selectedTimelineID = State(initialValue: existingNode?.timeline?.id)
        _selectedEraID = State(initialValue: existingNode?.era?.id)
        _yearText = State(initialValue: existingYear > 0 ? String(existingYear) : "")
        _monthText = State(initialValue: existingNode?.month.map(String.init) ?? "")
        _dayText = State(initialValue: existingNode?.day.map(String.init) ?? "")
        _selectedSectionID = State(initialValue: existingNode?.section?.id)
        _isVisible = State(initialValue: existingNode?.isVisible ?? true)
    }

    private var timelines: [Timeline] { allTimelines.filter { $0.book?.id == book.id } }
    private var sections: [Section] {
        allSections.filter { $0.volume?.book?.id == book.id }
            .sorted { lhs, rhs in
                if lhs.volume?.sortOrder != rhs.volume?.sortOrder {
                    return (lhs.volume?.sortOrder ?? 0) < (rhs.volume?.sortOrder ?? 0)
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }
    private var parsedYear: Int? { Int(yearText) }
    private var parsedMonth: Int? { monthText.isEmpty ? nil : Int(monthText) }
    private var parsedDay: Int? { dayText.isEmpty ? nil : Int(dayText) }
    private var canCreate: Bool {
        (parsedYear == nil || parsedYear! > 0) &&
        (parsedMonth == nil || (1...12).contains(parsedMonth!)) &&
        (parsedDay == nil || (1...31).contains(parsedDay!))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingNode == nil ? "新增時間戳記" : "修改時間戳記").font(.headline)
            Form {
                Picker("時間軸", selection: $selectedTimelineID) {
                    ForEach(timelines) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("紀元", selection: $selectedEraID) {
                    Text("無紀元").tag(Optional<UUID>.none)
                    ForEach(allEras) { Text($0.name.isEmpty ? "未命名紀元" : $0.name).tag(Optional($0.id)) }
                }
                SwiftUI.Section("世界時間") {
                    HStack(alignment: .top, spacing: 12) {
                        dateField(title: "年", text: $yearText, width: 100)
                        dateField(title: "月", text: $monthText, width: 64)
                        dateField(title: "日", text: $dayText, width: 64)
                    }
                    .padding(.vertical, 2)
                }
                Picker("節", selection: $selectedSectionID) {
                    Text("無節定位").tag(Optional<UUID>.none)
                    ForEach(sections) { Text($0.title.isEmpty ? "未命名節" : $0.title).tag(Optional($0.id)) }
                }
                Toggle("顯示於時間軸", isOn: $isVisible)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(existingNode == nil ? "建立" : "儲存", action: saveTimestamp)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 450, height: 420)
        .onAppear {
            if selectedTimelineID == nil {
                selectedTimelineID = timelines.first(where: \.isPrimary)?.id ?? timelines.first?.id
            }
            if selectedEraID == nil {
                selectedEraID = book.currentEra?.id
            }
        }
    }

    private func numericBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = $0.filter(\.isNumber) }
        )
    }

    private func dateField(title: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: numericBinding(text))
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(width: width, height: 28)
        }
    }

    private func saveTimestamp() {
        guard canCreate else { return }
        // Node.year remains non-optional for SwiftData store compatibility.
        // A zero value represents an intentionally unspecified world year.
        let timestamp = existingNode ?? Node(year: parsedYear ?? 0, month: parsedMonth, day: parsedDay)
        timestamp.year = parsedYear ?? 0
        timestamp.month = parsedMonth
        timestamp.day = parsedDay
        timestamp.timeline = selectedTimelineID.flatMap { id in timelines.first { $0.id == id } }
        timestamp.era = selectedEraID.flatMap { id in allEras.first { $0.id == id } }
        timestamp.section = selectedSectionID.flatMap { id in sections.first { $0.id == id } }
        // A node without a year is a reference-only timestamp by default, so it
        // does not create a misleading "0 年" entry on the world timeline.
        timestamp.isVisible = isVisible && parsedYear != nil
        if existingNode == nil {
            timestamp.sortOrder = (timestamp.timeline?.nodes.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(timestamp)
        }
        onSave(timestamp)
        try? modelContext.save()
        dismiss()
    }
}

struct OrganizationIdentityHistoryEditor: View {
    @Bindable var membership: CharacterOrganization
    let book: Book
    @Environment(\.modelContext) private var modelContext

    private var histories: [OrganizationIdentityHistory] { membership.identityHistory.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        historyContainer(title: "身分歷史", addTitle: "新增身分", add: addHistory) {
            ForEach(histories) { history in
                OrganizationIdentityHistoryRow(history: history, book: book, onDelete: { modelContext.delete(history) })
            }
        }
    }

    private func addHistory() {
        let history = OrganizationIdentityHistory(identity: "新身分", sortOrder: (histories.map(\.sortOrder).max() ?? -1) + 1)
        membership.identityHistory.append(history)
        modelContext.insert(history)
    }
}

private struct OrganizationIdentityHistoryRow: View {
    @Bindable var history: OrganizationIdentityHistory
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TextField("身分", text: $history.identity).textFieldStyle(.roundedBorder)
                CharacterNodePicker(book: book, node: $history.node)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            TextField("備註", text: $history.note).textFieldStyle(.roundedBorder)
        }
        .onChange(of: history.identity) { history.updatedAt = Date() }
        .onChange(of: history.note) { history.updatedAt = Date() }
    }
}

struct AbilityHistoryEditor: View {
    @Bindable var ability: CharacterAbility
    let book: Book
    @Environment(\.modelContext) private var modelContext
    private var histories: [AbilityStageHistory] { ability.history.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        historyContainer(title: "階段歷史", addTitle: "新增階段", add: addHistory) {
            ForEach(histories) { history in
                AbilityHistoryRow(history: history, book: book, onDelete: { modelContext.delete(history) })
            }
        }
    }

    private func addHistory() {
        let history = AbilityStageHistory(stage: "新階段", sortOrder: (histories.map(\.sortOrder).max() ?? -1) + 1)
        ability.history.append(history)
        modelContext.insert(history)
    }
}

private struct AbilityHistoryRow: View {
    @Bindable var history: AbilityStageHistory
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TextField("階段", text: $history.stage).textFieldStyle(.roundedBorder)
                CharacterNodePicker(book: book, node: $history.node)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            TextField("描述", text: $history.descriptionText).textFieldStyle(.roundedBorder)
        }
        .onChange(of: history.stage) { history.updatedAt = Date() }
        .onChange(of: history.descriptionText) { history.updatedAt = Date() }
    }
}

struct ItemHistoryEditor: View {
    @Bindable var characterItem: CharacterItem
    let book: Book
    @Environment(\.modelContext) private var modelContext
    private var histories: [CharacterItemHistory] { characterItem.history.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        historyContainer(title: "物品歷史", addTitle: "新增紀錄", add: addHistory) {
            ForEach(histories) { history in
                ItemHistoryRow(history: history, book: book, onDelete: { modelContext.delete(history) })
            }
        }
    }

    private func addHistory() {
        let history = CharacterItemHistory(content: "", sortOrder: (histories.map(\.sortOrder).max() ?? -1) + 1)
        characterItem.history.append(history)
        modelContext.insert(history)
    }
}

private struct ItemHistoryRow: View {
    @Bindable var history: CharacterItemHistory
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        HStack {
            TextField("自由文字紀錄", text: $history.content).textFieldStyle(.roundedBorder)
            CharacterNodePicker(book: book, node: $history.node)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
        }
        .onChange(of: history.content) { history.updatedAt = Date() }
    }
}

struct RelationshipHistoryEditor: View {
    @Bindable var relationship: CharacterRelationship
    let book: Book
    @Environment(\.modelContext) private var modelContext
    private var histories: [RelationshipHistory] { relationship.history.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        historyContainer(title: "關係歷史", addTitle: "新增變化", add: addHistory) {
            ForEach(histories) { history in
                RelationshipHistoryRow(history: history, book: book, onDelete: { modelContext.delete(history) })
            }
        }
    }

    private func addHistory() {
        let history = RelationshipHistory(type: relationship.type, sortOrder: (histories.map(\.sortOrder).max() ?? -1) + 1)
        relationship.history.append(history)
        modelContext.insert(history)
    }
}

private struct RelationshipHistoryRow: View {
    @Bindable var history: RelationshipHistory
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TextField("關係", text: $history.type).textFieldStyle(.roundedBorder)
                CharacterNodePicker(book: book, node: $history.node)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            TextField("備註", text: $history.note).textFieldStyle(.roundedBorder)
        }
        .onChange(of: history.type) { history.updatedAt = Date() }
        .onChange(of: history.note) { history.updatedAt = Date() }
    }
}

@ViewBuilder
private func historyContainer<Content: View>(title: String, addTitle: String, add: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) -> some View {
    DisclosureGroup {
        VStack(alignment: .leading, spacing: 7) {
            content()
            Button(action: add) { Label(addTitle, systemImage: "plus") }.buttonStyle(.borderless)
        }
        .padding(.top, 7)
    } label: {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }
}
