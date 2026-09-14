import SwiftUI
import SwiftData

struct SidebarSettingsManagerView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(V5SettingsStore.self) private var settingsStore

    private var rows: [BookSidebarSetting] {
        settingsStore.sidebarRows(for: book.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("管理設定集").font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }
            Text("預設項目也可以隱藏；隱藏只影響側邊欄，不會刪除資料。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                SwiftUI.Section("側邊欄順序") {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Toggle(isOn: binding(for: row)) {
                                Label(row.key?.title ?? "未知設定", systemImage: row.key?.systemImage ?? "questionmark")
                            }
                            Spacer()
                            Button { move(row, offset: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless)
                                .disabled(row.sortOrder == rows.first?.sortOrder)
                            Button { move(row, offset: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless)
                                .disabled(row.sortOrder == rows.last?.sortOrder)
                        }
                    }
                }
            }
            HStack {
                Button("重設預設顯示", action: reset)
                Spacer()
                Text("可選項目：地點、世界條目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 360)
        .task { settingsStore.ensureDefaults(for: book.id) }
    }

    private func binding(for row: BookSidebarSetting) -> Binding<Bool> {
        Binding(get: { row.isVisible }, set: { row.isVisible = $0; settingsStore.save() })
    }

    private func move(_ row: BookSidebarSetting, offset: Int) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let target = index + offset
        guard rows.indices.contains(target) else { return }
        let other = rows[target]
        let order = row.sortOrder
        row.sortOrder = other.sortOrder
        other.sortOrder = order
        settingsStore.save()
    }

    private func reset() {
        for (index, row) in rows.enumerated() {
            row.sortOrder = index
            row.isVisible = row.key?.isDefaultVisible ?? false
        }
        settingsStore.save()
    }
}

struct PowerListView: View {
    let book: Book
    let onOpen: (PowerUnit) -> Void
    @Environment(V5SettingsStore.self) private var settingsStore
    @State private var searchText = ""
    @State private var showingLevels = false

    private var levels: [PowerLevel] { settingsStore.levels(for: book.id) }
    private var powers: [PowerUnit] {
        settingsStore.powers(for: book.id).filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜尋勢力", text: $searchText).textFieldStyle(.roundedBorder)
                Button { showingLevels = true } label: { Label("管理層級", systemImage: "list.number") }
                    .buttonStyle(.borderless)
                Button { addPower() } label: { Label("新增", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            .padding(10)
            List {
                ForEach(powers) { power in
                    Button { onOpen(power) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(power.name.isEmpty ? "未命名勢力" : power.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(PowerHierarchyStore.level(for: power, levels: levels)?.name ?? "尚未指定層級")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !power.powerDescription.isEmpty {
                                Text(power.powerDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for power in offsets.map({ powers[$0] }) {
                        settingsStore.deletePower(power, bookID: book.id)
                    }
                }
            }
        }
        .sheet(isPresented: $showingLevels) {
            PowerLevelManagementView(book: book)
        }
    }

    private func addPower() {
        let power = PowerUnit(bookID: book.id, name: "新勢力")
        settingsStore.context.insert(power)
        settingsStore.save()
        onOpen(power)
    }
}

struct PowerLevelManagementView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(V5SettingsStore.self) private var settingsStore
    @State private var draftNames: [UUID: String] = [:]
    @State private var errorMessage: String?

    private var levels: [PowerLevel] { settingsStore.levels(for: book.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("管理勢力層級").font(.headline)
                    Text("由高至低排列；勢力可跨級直屬。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("新增層級", systemImage: "plus", action: addLevel)
                Button("完成") { dismiss() }
            }

            if levels.isEmpty {
                ContentUnavailableView(
                    "尚未建立層級",
                    systemImage: "list.number",
                    description: Text("先新增一個具名層級，再為勢力指定層級。")
                )
            } else {
                List {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            TextField("層級名稱", text: nameBinding(for: level))
                                .onSubmit { rename(level) }
                            Button("儲存") { rename(level) }
                                .disabled((draftNames[level.id] ?? level.name) == level.name)
                            Button { move(level, offset: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                            Button { move(level, offset: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless)
                                .disabled(index == levels.count - 1)
                            Button(role: .destructive) { delete(level) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                    .onMove(perform: reorder)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 380)
        .onAppear { synchronizeDraftNames() }
        .onChange(of: settingsStore.revision) { synchronizeDraftNames() }
        .alert("無法變更層級", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func nameBinding(for level: PowerLevel) -> Binding<String> {
        Binding(
            get: { draftNames[level.id] ?? level.name },
            set: { draftNames[level.id] = $0 }
        )
    }

    private func synchronizeDraftNames() {
        for level in levels where draftNames[level.id] == nil {
            draftNames[level.id] = level.name
        }
        draftNames = draftNames.filter { id, _ in levels.contains(where: { $0.id == id }) }
    }

    private func addLevel() {
        do {
            let level = try settingsStore.createLevel(bookID: book.id)
            draftNames[level.id] = level.name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(_ level: PowerLevel) {
        do {
            try settingsStore.renameLevel(level, to: draftNames[level.id] ?? level.name, bookID: book.id)
            draftNames[level.id] = level.name
        } catch {
            draftNames[level.id] = level.name
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ level: PowerLevel, offset: Int) {
        guard let index = levels.firstIndex(where: { $0.id == level.id }) else { return }
        let destination = index + offset
        guard levels.indices.contains(destination) else { return }
        var orderedIDs = levels.map(\.id)
        orderedIDs.swapAt(index, destination)
        applyOrder(orderedIDs)
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        var reordered = levels
        reordered.move(fromOffsets: source, toOffset: destination)
        applyOrder(reordered.map(\.id))
    }

    private func applyOrder(_ orderedIDs: [UUID]) {
        do {
            try settingsStore.reorderLevels(bookID: book.id, orderedIDs: orderedIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ level: PowerLevel) {
        do {
            try settingsStore.deleteLevel(level, bookID: book.id)
            draftNames[level.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PowerDetailView: View {
    @Bindable var power: PowerUnit
    let book: Book
    let onBack: () -> Void
    @Environment(V5SettingsStore.self) private var settingsStore
    @State private var showingLevels = false
    @State private var errorMessage: String?

    private var levels: [PowerLevel] { settingsStore.levels(for: book.id) }
    private var powers: [PowerUnit] { settingsStore.powers(for: book.id) }
    private var edges: [PowerSubordination] { settingsStore.edges(for: book.id) }
    private var currentLevel: PowerLevel? { PowerHierarchyStore.level(for: power, levels: levels) }
    private var upper: [PowerUnit] { PowerGraphStore.directUpperPowers(of: power, edges: edges, powers: powers) }
    private var lower: [PowerUnit] { PowerGraphStore.directLowerPowers(of: power, edges: edges, powers: powers) }
    private var upperCandidates: [PowerUnit] {
        PowerHierarchyStore.upperCandidates(for: power, powers: powers, levels: levels)
            .filter { candidate in !upper.contains(where: { $0.id == candidate.id }) }
    }
    private var lowerCandidates: [PowerUnit] {
        PowerHierarchyStore.lowerCandidates(for: power, powers: powers, levels: levels)
            .filter { candidate in !lower.contains(where: { $0.id == candidate.id }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button(action: onBack) { Label("返回勢力", systemImage: "chevron.left") }.buttonStyle(.plain)
                    Spacer()
                    Button("管理層級", systemImage: "list.number") { showingLevels = true }
                        .buttonStyle(.borderless)
                    Button(role: .destructive, action: deletePower) { Label("刪除", systemImage: "trash") }.buttonStyle(.borderless)
                }
                TextField("勢力名稱", text: $power.name).textFieldStyle(.roundedBorder)
                Text("簡介").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $power.powerDescription)
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

                powerNotebookField(
                    title: "高層管理員",
                    detail: "記錄職稱與人名；第一版不連結角色資料。",
                    text: $power.seniorManagers
                )
                powerNotebookField(
                    title: "其他名單",
                    detail: "可自由記錄其他職稱、人名或群組。",
                    text: $power.otherRoster
                )
                powerNotebookField(
                    title: "勢力關係",
                    detail: "補充隸屬以外的合作、敵對或其他關係。",
                    text: $power.relationshipNotes
                )
                powerNotebookField(title: "政治", detail: "記錄政治立場、制度或運作方式。", text: $power.politics)
                powerNotebookField(title: "宗教", detail: "記錄信仰、宗教制度或相關影響。", text: $power.religion)

                VStack(alignment: .leading, spacing: 7) {
                    Text("層級").font(.subheadline.weight(.semibold))
                    if levels.isEmpty {
                        Text("尚未建立層級。請先使用「管理層級」新增。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(levels) { level in
                                Button(level.name) { changeLevel(to: level) }
                            }
                        } label: {
                            Label(currentLevel?.name ?? "選擇層級", systemImage: "list.number")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                if currentLevel == nil {
                    ContentUnavailableView(
                        "請先指定層級",
                        systemImage: "arrow.up.arrow.down",
                        description: Text("指定具體層級後，才能選擇此勢力的直屬上級或下級。")
                    )
                } else {
                    powerRelationSection(
                        title: "直屬上層",
                        detail: "此勢力直接隸屬的較高層級勢力，可跨級選擇。",
                        values: upper,
                        candidates: upperCandidates,
                        addTitle: "新增上層"
                    ) { candidate in
                        add(lower: power, upper: candidate)
                    }
                    powerRelationSection(
                        title: "直屬下層",
                        detail: "直接隸屬於此勢力的較低層級勢力，可跨級選擇。",
                        values: lower,
                        candidates: lowerCandidates,
                        addTitle: "新增下層"
                    ) { candidate in
                        add(lower: candidate, upper: power)
                    }
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $showingLevels) {
            PowerLevelManagementView(book: book)
        }
        .alert("無法完成勢力變更", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
        .onChange(of: power.name) { power.updatedAt = Date() }
        .onChange(of: power.powerDescription) { power.updatedAt = Date() }
        .onChange(of: power.seniorManagers) { power.updatedAt = Date() }
        .onChange(of: power.otherRoster) { power.updatedAt = Date() }
        .onChange(of: power.relationshipNotes) { power.updatedAt = Date() }
        .onChange(of: power.politics) { power.updatedAt = Date() }
        .onChange(of: power.religion) { power.updatedAt = Date() }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @ViewBuilder
    private func powerNotebookField(title: String, detail: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: 72)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func powerRelationSection(
        title: String,
        detail: String,
        values: [PowerUnit],
        candidates: [PowerUnit],
        addTitle: String,
        add: @escaping (PowerUnit) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if values.isEmpty { Text("尚未設定").font(.caption).foregroundStyle(.tertiary) }
            ForEach(values) { value in
                HStack {
                    Text(value.name.isEmpty ? "未命名勢力" : value.name)
                    Spacer()
                    Button(role: .destructive) { remove(value) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                }
            }
            Menu {
                if candidates.isEmpty {
                    Text("沒有符合層級的候選勢力")
                } else {
                    ForEach(candidates) { candidate in
                        Button(candidate.name.isEmpty ? "未命名勢力" : candidate.name) { add(candidate) }
                    }
                }
            } label: {
                Label(addTitle, systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(candidates.isEmpty)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func changeLevel(to level: PowerLevel) {
        do {
            try settingsStore.changeLevel(of: power, to: level, bookID: book.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(lower: PowerUnit, upper: PowerUnit) {
        do {
            try settingsStore.addSubordination(lower: lower, upper: upper, bookID: book.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ other: PowerUnit) {
        settingsStore.removeRelations(between: power, and: other, bookID: book.id)
    }

    private func deletePower() {
        settingsStore.deletePower(power, bookID: book.id)
        onBack()
    }
}

struct PlaceListView: View {
    let book: Book
    @Environment(V5SettingsStore.self) private var settingsStore
    private var places: [Place] { settingsStore.places(for: book.id).sorted { $0.sortOrder < $1.sortOrder } }
    var body: some View {
        List {
            ForEach(places) { place in
                @Bindable var place = place
                VStack(alignment: .leading) {
                    TextField("地點名稱", text: $place.name).textFieldStyle(.roundedBorder)
                    TextField("簡介", text: $place.placeDescription).textFieldStyle(.roundedBorder)
                }
            }
            .onDelete { offsets in offsets.map { places[$0] }.forEach(settingsStore.context.delete); settingsStore.save() }
        }
        .toolbar { Button("新增地點", systemImage: "plus") { settingsStore.context.insert(Place(bookID: book.id, name: "新地點")); settingsStore.save() } }
    }
}

struct WorldTermListView: View {
    let book: Book
    @Environment(V5SettingsStore.self) private var settingsStore
    private var terms: [WorldTerm] { settingsStore.worldTerms(for: book.id).sorted { $0.sortOrder < $1.sortOrder } }
    var body: some View {
        List {
            ForEach(terms) { term in
                @Bindable var term = term
                VStack(alignment: .leading) {
                    TextField("條目名稱", text: $term.name).textFieldStyle(.roundedBorder)
                    TextField("簡介", text: $term.termDescription).textFieldStyle(.roundedBorder)
                }
            }
            .onDelete { offsets in offsets.map { terms[$0] }.forEach(settingsStore.context.delete); settingsStore.save() }
        }
        .toolbar { Button("新增世界條目", systemImage: "plus") { settingsStore.context.insert(WorldTerm(bookID: book.id, name: "新條目")); settingsStore.save() } }
    }
}
