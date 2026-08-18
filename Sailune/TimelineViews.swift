import SwiftUI
import SwiftData

// MARK: - 角色顯示名（直接取 realName）

private func sailuneDisplayName(_ character: Character) -> String {
    let name = character.realName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "角色·\(character.id.uuidString.prefix(4))" : name
}

// MARK: - 右欄頂端分段

private enum SailuneInspectorTab: String, CaseIterable, Identifiable {
    case settings = "設定集"
    case timeline = "時間軸"
    var id: String { rawValue }
}

private enum SailuneTimelineGranularity: String, CaseIterable, Identifiable {
    case year = "年", month = "月", day = "日"
    var id: String { rawValue }
}

@MainActor
struct InspectorWithTimeline: View {
    let book: Book
    let currentSection: Section?
    var focusedCharacter: Character? = nil
    var focusRequestID = UUID()
    var onSelectSection: ((Section) -> Void)? = nil
    @State private var tab: SailuneInspectorTab = .settings

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SailuneInspectorTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            switch tab {
            case .settings:
                InspectorRootView(
                    book: book,
                    currentSection: currentSection,
                    focusedCharacter: focusedCharacter,
                    focusRequestID: focusRequestID,
                    onSelectSection: onSelectSection
                )
            case .timeline:
                TimelinePanelView(book: book)
            }
        }
        .onAppear { showFocusedCharacter() }
        .onChange(of: focusedCharacter?.id) { _, _ in showFocusedCharacter() }
        .onChange(of: focusRequestID) { _, _ in showFocusedCharacter() }
    }

    private func showFocusedCharacter() {
        guard focusedCharacter != nil else { return }
        tab = .settings
    }
}

// MARK: - 格子模型

private enum CellKind { case year, month, day }

private struct TimelineCell: Identifiable {
    let id: String
    let kind: CellKind
    let ordinal: Int
    let eraID: UUID?
    let eraHex: String
    let eraName: String
    let era: Era?
    let nodes: [Node]
    let repYear: Int
    let repMonth: Int?
    let repDay: Int?
    let events: [Event]
    var label: String = ""
}

private final class CellAccum {
    let kind: CellKind
    var ordinal: Int
    let eraID: UUID?
    let eraHex: String
    let eraName: String
    var era: Era?
    var nodes: [Node]
    var nodeIDs: Set<UUID>
    let repYear: Int
    let repMonth: Int?
    let repDay: Int?
    var events: [Event]
    init(kind: CellKind, ordinal: Int, eraID: UUID?, eraHex: String, eraName: String,
         era: Era?, nodes: [Node], ry: Int, rm: Int?, rd: Int?, events: [Event]) {
        self.kind = kind; self.ordinal = ordinal; self.eraID = eraID
        self.eraHex = eraHex; self.eraName = eraName
        self.era = era; self.nodes = nodes; self.nodeIDs = Set(nodes.map(\.id))
        self.repYear = ry; self.repMonth = rm; self.repDay = rd; self.events = events
    }
}

// MARK: - 以人分類的鑽取分組

private struct EventGroup: Identifiable {
    let id: String
    let character: Character?
    let events: [Event]
    var displayName: String {
        character.map { sailuneDisplayName($0) } ?? "未指定角色"
    }
}

// MARK: - 事件操作鈕常駐淡顯（可見性與 hover 脫鉤，根治點不到）

private let eventActionIdleOpacity: Double = 0.3

// MARK: - 時間軸面板

@MainActor
struct TimelinePanelView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext

    @Query private var allTimelines: [Timeline]
    @Query private var allNodes: [Node]
    @Query private var allEras: [Era]
    @Query private var allEvents: [Event]
    @Query private var allCharacters: [Character]

    @State private var selectedTimelineID: UUID? = nil
    @State private var granularity: SailuneTimelineGranularity = .month
    @State private var expandedCells: Set<String> = []
    @State private var showingEraChange = false
    @State private var editingEra: Era? = nil
    @State private var pendingDeleteNodes: [Node] = []
    @State private var showDeleteConfirm = false
    @State private var addingEventToCell: String? = nil
    @State private var newEventTitle = ""
    @State private var newEventDetail = ""
    @State private var selectedCharIDs: Set<String> = []
    @State private var collapsedCharGroups: Set<String> = []
    @State private var showingAddSecondary = false
    @State private var newSecondaryName = ""
    @State private var pendingRenameTimeline: Timeline? = nil
    @State private var renameBuffer = ""
    @State private var pendingDeleteTimeline: Timeline? = nil
    @State private var showingAddNode = false
    @State private var newNodeYearText = ""
    @State private var newNodeMonthText = ""
    @State private var newNodeDayText = ""
    @State private var newNodeEraID: UUID? = nil
    @State private var showingEraManager = false

    init(book: Book) {
        self.book = book
        let bookID = book.id
        _allTimelines = Query(filter: #Predicate<Timeline> { $0.book?.id == bookID })
        // SwiftData cannot translate nested optional relationship paths such as
        // `timeline?.book?.id` into a persistent-store predicate. Nodes and
        // events are scoped in memory below by their selected timeline/node.
        _allNodes = Query()
        _allEvents = Query()
        _allCharacters = Query(filter: #Predicate<Character> { $0.book?.id == bookID })
    }

    private var sortedCharacters: [Character] {
        allCharacters.sorted { sailuneDisplayName($0) < sailuneDisplayName($1) }
    }

    private var bookTimelines: [Timeline] {
        allTimelines
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var selectedTimeline: Timeline? {
        bookTimelines.first { $0.id == selectedTimelineID } ?? bookTimelines.first
    }

    private var isPrimarySelected: Bool { selectedTimeline?.isPrimary ?? false }

    private var visibleNodes: [Node] {
        guard let t = selectedTimeline else { return [] }
        let ofTimeline = allNodes.filter { $0.timeline?.id == t.id }
        let filtered = isPrimarySelected ? ofTimeline.filter { $0.isVisible } : ofTimeline
        return TimelineEngine.Query.sorted(filtered)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            axisContent
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .popover(item: $editingEra) { era in
            EraEditPopover(era: era)
        }
        .alert("刪除時間釘子", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDeleteNodes = [] }
            Button("刪除", role: .destructive) { performDeleteNodes() }
        } message: {
            let n = pendingDeleteNodes.count
            if n <= 1 {
                Text("確定刪除此時間釘子？其下事件將一併刪除，且無法復原。")
            } else {
                Text("確定刪除這 \(n) 個時間釘子？其下事件將一併刪除，且無法復原。")
            }
        }
        .alert("新增副軸", isPresented: $showingAddSecondary) {
            TextField("副軸名稱", text: $newSecondaryName)
            Button("取消", role: .cancel) { newSecondaryName = "" }
            Button("新增") { commitAddSecondary() }
                .disabled(newSecondaryName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("副軸用來裝前史、伏筆或規劃中劇情，與主軸並存。")
        }
        .alert("重新命名副軸",
               isPresented: Binding(get: { pendingRenameTimeline != nil },
                                    set: { if !$0 { pendingRenameTimeline = nil } }),
               presenting: pendingRenameTimeline) { t in
            TextField("副軸名稱", text: $renameBuffer)
            Button("取消", role: .cancel) { pendingRenameTimeline = nil }
            Button("儲存") {
                t.name = renameBuffer
                try? modelContext.save()
                pendingRenameTimeline = nil
            }
        }
        .alert("刪除副軸",
               isPresented: Binding(get: { pendingDeleteTimeline != nil },
                                    set: { if !$0 { pendingDeleteTimeline = nil } }),
               presenting: pendingDeleteTimeline) { t in
            Button("取消", role: .cancel) { pendingDeleteTimeline = nil }
            Button("刪除", role: .destructive) { performDeleteTimeline(t) }
        } message: { t in
            Text("確定刪除副軸「\(t.name.isEmpty ? "副軸" : t.name)」？其下所有時間釘子與事件將一併刪除，且無法復原。")
        }
        .popover(isPresented: $showingAddNode) {
            AddNodePopover(
                book: book,
                target: selectedTimeline,
                eras: allEras,
                yearText: $newNodeYearText,
                monthText: $newNodeMonthText,
                dayText: $newNodeDayText,
                eraID: $newNodeEraID
            )
        }
        .popover(isPresented: $showingEraManager) {
            EraManagerPopover(book: book)
        }
    }

    private var header: some View {
        let eraName = book.currentEra?.name ?? ""
        return HStack {
            Text("時間軸").font(.system(.headline, design: .serif))
            Spacer()
            Text("當前：\(eraName.isEmpty ? "（未命名）" : eraName)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(bookTimelines, id: \.id) { t in
                        Button { selectedTimelineID = t.id } label: {
                            Text(t.isPrimary ? "主軸" : (t.name.isEmpty ? "副軸" : t.name))
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(
                                    Capsule().fill(selectedTimeline?.id == t.id
                                                   ? Color.accentColor.opacity(0.2)
                                                   : Color.clear)
                                )
                                .overlay(
                                    Capsule().stroke(t.isPrimary ? Color.clear : Color.secondary.opacity(0.25),
                                                     lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !t.isPrimary {
                                Button { startRenameTimeline(t) } label: {
                                    Label("重新命名", systemImage: "pencil")
                                }
                                Button(role: .destructive) { pendingDeleteTimeline = t } label: {
                                    Label("刪除副軸", systemImage: "trash")
                                }
                            }
                        }
                    }
                    Button { openAddNode() } label: {
                        Image(systemName: "mappin.circle.fill").font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedTimeline == nil)
                    .help("新增時間釘子到當前軸（含副軸）")
                    Button { showingEraManager = true } label: {
                        Image(systemName: "list.bullet.rectangle").font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("年號管理：新增／編輯紀元，填負序數可建前史紀元")
                    Button {
                        newSecondaryName = ""
                        showingAddSecondary = true
                    } label: {
                        Image(systemName: "plus").font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("新增副軸")
                    Button { showingEraChange = true } label: {
                        Image(systemName: "calendar.badge.plus").font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .foregroundStyle(isPrimarySelected ? .primary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPrimarySelected)
                    .help(isPrimarySelected
                          ? "改元（踰年推進敘事，落主軸並切換當前年號）"
                          : "改元為全書敘事推進，請於主軸操作；副軸請用年號管理＋📌")
                    .popover(isPresented: $showingEraChange) {
                        EraChangePopover(book: book)
                    }
                }
                .padding(.horizontal, 12)
            }
            Picker("", selection: $granularity) {
                ForEach(SailuneTimelineGranularity.allCases) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    private var axisContent: some View {
        let cells = buildCells()
        let cellIDs = cells.map(\.id)
        return ScrollView {
            if cells.isEmpty {
                ContentUnavailableView(
                    "尚無時間記錄",
                    systemImage: "clock",
                    description: Text("右鍵捕獲會落到主軸；副軸請先以「年號管理」建紀元，再點 📌 落釘。")
                )
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { offset, cell in
                        eraHeaderIfNeeded(cell: cell, previous: offset > 0 ? cells[offset - 1] : nil)
                            .transition(.opacity)
                        cellRow(cell)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.vertical, 8)
                .animation(.snappy, value: cellIDs)
            }
        }
    }

    @ViewBuilder
    private func eraHeaderIfNeeded(cell: TimelineCell, previous: TimelineCell?) -> some View {
        let eraColor = Color(hex: cell.eraHex) ?? .gray
        if previous == nil || previous?.eraID != cell.eraID {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [eraColor, eraColor.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: 10)
                Text(cell.eraName.isEmpty ? "未命名紀元" : cell.eraName)
                    .font(.system(.caption, design: .serif)).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if let era = cell.era {
                    Button { editingEra = era } label: {
                        Image(systemName: "pencil")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("編輯年號名稱與顏色")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(eraColor.opacity(0.08))
        }
    }

    @ViewBuilder
    private func cellRow(_ cell: TimelineCell) -> some View {
        let expanded = expandedCells.contains(cell.id)
        let dot = Color(hex: cell.eraHex) ?? .gray
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Rectangle().fill(dot.opacity(0.3)).frame(width: 2)
                Circle().fill(dot).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: dot.opacity(0.4), radius: 2)
            }
            .frame(width: 14).frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(cell.label)
                        .font(.system(.body, design: .serif))
                        .fontWeight(cell.kind == .year ? .semibold : .regular)
                    Spacer(minLength: 4)
                    if !cell.events.isEmpty {
                        Text("\(cell.events.count)")
                            .font(.caption2).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Button { requestDeleteNodes(cell.nodes) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("刪除時間釘子")
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(cell.id) }

                if expanded { drillDown(cell) }
            }
            .padding(.vertical, 6).padding(.trailing, 12)
        }
    }

    @ViewBuilder
    private func drillDown(_ cell: TimelineCell) -> some View {
        let groups = groupedEvents(cell.events)
        VStack(alignment: .leading, spacing: 6) {
            if groups.isEmpty && addingEventToCell != cell.id {
                Text("尚無事件").font(.caption).foregroundStyle(.tertiary).padding(.leading, 4)
            } else {
                ForEach(groups) { g in
                    let collapsed = collapsedCharGroups.contains(g.id)
                    VStack(alignment: .leading, spacing: 3) {
                        Button { toggleGroup(g.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .frame(width: 10)
                                Text(g.displayName)
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(g.character == nil ? .secondary : .primary)
                                Spacer(minLength: 4)
                                Text("\(g.events.count)")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if !collapsed {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(g.events, id: \.id) { e in
                                    EventRow(event: e, allCharacters: sortedCharacters)
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
                }
            }

            if addingEventToCell == cell.id {
                addEventForm(cell: cell)
            } else {
                Button {
                    selectedCharIDs = []
                    withAnimation(.snappy) { addingEventToCell = cell.id }
                } label: {
                    Label("新增事件", systemImage: "plus.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4).padding(.top, 2)
            }
        }
        .padding(.leading, 6).padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func groupedEvents(_ events: [Event]) -> [EventGroup] {
        var dict: [String: (Character?, [Event])] = [:]
        var order: [String] = []
        for e in events {
            if e.characters.isEmpty {
                let k = "__unassigned__"
                if dict[k] == nil { dict[k] = (nil, []); order.append(k) }
                dict[k]?.1.append(e)
            } else {
                for c in e.characters {
                    let k = c.id.uuidString
                    if dict[k] == nil { dict[k] = (c, []); order.append(k) }
                    dict[k]?.1.append(e)
                }
            }
        }
        let built: [EventGroup] = order.map { k in
            let p = dict[k]!
            return EventGroup(id: k, character: p.0,
                              events: p.1.sorted { $0.sortOrder < $1.sortOrder })
        }
        return built.sorted { lhs, rhs in
            switch (lhs.character, rhs.character) {
            case (_, nil): return true
            case (nil, _): return false
            default: return lhs.displayName < rhs.displayName
            }
        }
    }

    private func toggleGroup(_ id: String) {
        withAnimation(.snappy) {
            if collapsedCharGroups.contains(id) { collapsedCharGroups.remove(id) }
            else { collapsedCharGroups.insert(id) }
        }
    }

    @ViewBuilder
    private func addEventForm(cell: TimelineCell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("事件標題", text: $newEventTitle)
                .textFieldStyle(.roundedBorder).font(.caption)
            TextField("詳情（選填）", text: $newEventDetail, axis: .vertical)
                .textFieldStyle(.roundedBorder).font(.caption).lineLimit(2...3)

            VStack(alignment: .leading, spacing: 4) {
                Text("參與角色（選填，可多選）").font(.caption2).foregroundStyle(.secondary)
                if sortedCharacters.isEmpty {
                    Text("尚無角色，請先到設定集建立。").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(sortedCharacters, id: \.id) { c in
                                let sel = selectedCharIDs.contains(c.id.uuidString)
                                Button { toggleChar(c.id.uuidString) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: sel ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(sel ? Color.accentColor : .secondary)
                                        Text(sailuneDisplayName(c)).font(.caption)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }
            }

            HStack {
                Button("取消") {
                    withAnimation(.snappy) { cancelAddEvent() }
                }
                .buttonStyle(.borderless).font(.caption)
                Spacer()
                Button("儲存") {
                    withAnimation(.snappy) { commitAddEvent(to: cell) }
                }
                .buttonStyle(.borderedProminent).font(.caption)
                .disabled(newEventTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 4).padding(.top, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    private func toggleChar(_ id: String) {
        if selectedCharIDs.contains(id) { selectedCharIDs.remove(id) }
        else { selectedCharIDs.insert(id) }
    }

    private func commitAddEvent(to cell: TimelineCell) {
        guard let node = cell.nodes.first else { return }
        let ev = Event(title: newEventTitle, detail: newEventDetail)
        modelContext.insert(ev)
        ev.node = node
        ev.sortOrder = (events(at: node).map(\.sortOrder).max() ?? -1) + 1
        ev.characters = allCharacters.filter { selectedCharIDs.contains($0.id.uuidString) }
        try? modelContext.save()
        newEventTitle = ""
        newEventDetail = ""
        selectedCharIDs = []
        addingEventToCell = nil
    }

    private func cancelAddEvent() {
        newEventTitle = ""
        newEventDetail = ""
        selectedCharIDs = []
        addingEventToCell = nil
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            if expandedCells.contains(id) { expandedCells.remove(id) } else { expandedCells.insert(id) }
        }
    }

    private func requestDeleteNodes(_ nodes: [Node]) {
        guard !nodes.isEmpty else { return }
        pendingDeleteNodes = nodes
        showDeleteConfirm = true
    }

    private func performDeleteNodes() {
        do {
            try PersistentModelDeletion.deleteNodes(pendingDeleteNodes, in: modelContext)
        } catch {
            print("❌ 時間釘子刪除失敗：\(error.localizedDescription)")
        }
        pendingDeleteNodes = []
    }

    private func commitAddSecondary() {
        let name = newSecondaryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let t = try? TimelineEngine.addSecondaryTimeline(for: book, name: name, in: modelContext) {
            selectedTimelineID = t.id
        }
        newSecondaryName = ""
    }

    private func startRenameTimeline(_ t: Timeline) {
        renameBuffer = t.name
        pendingRenameTimeline = t
    }

    private func performDeleteTimeline(_ t: Timeline) {
        if selectedTimelineID == t.id {
            selectedTimelineID = bookTimelines.first(where: \.isPrimary)?.id
        }
        do {
            try PersistentModelDeletion.deleteTimeline(t, in: modelContext)
        } catch {
            print("❌ 時間軸刪除失敗：\(error.localizedDescription)")
        }
        pendingDeleteTimeline = nil
    }

    private func openAddNode() {
        newNodeYearText = ""
        newNodeMonthText = ""
        newNodeDayText = ""
        newNodeEraID = book.currentEra?.id
        showingAddNode = true
    }

    private func buildCells() -> [TimelineCell] {
        var groups: [String: CellAccum] = [:]
        var order: [String] = []

        for n in visibleNodes {
            let ord = n.absoluteOrdinal
            let absYear = ord / 10000
            let absMonth = ord / 100
            let eraHex = n.era?.color ?? "#888888"
            let eraName = n.era?.name ?? ""
            let eraID = n.era?.id
            let hasMonth = n.month != nil
            let hasDay = n.day != nil

            let nodeEvents = events(at: n)
            let evs = isPrimarySelected
                ? nodeEvents.filter { TimelineEngine.Visibility.isVisibleOnPrimaryAxis($0) }
                : nodeEvents

            let key: String
            let kind: CellKind
            if !hasMonth {
                key = "Y:\(absYear)"; kind = .year
            } else if !hasDay {
                switch granularity {
                case .year:        key = "Y:\(absYear)"; kind = .year
                case .month, .day: key = "M:\(absMonth)"; kind = .month
                }
            } else {
                switch granularity {
                case .year:  key = "Y:\(absYear)"; kind = .year
                case .month: key = "M:\(absMonth)"; kind = .month
                case .day:   key = "D:\(ord)";     kind = .day
                }
            }

            if let acc = groups[key] {
                acc.ordinal = min(acc.ordinal, ord)
                acc.events.append(contentsOf: evs)
                if !acc.nodeIDs.contains(n.id) { acc.nodeIDs.insert(n.id); acc.nodes.append(n) }
                if acc.era == nil { acc.era = n.era }
            } else {
                groups[key] = CellAccum(kind: kind, ordinal: ord, eraID: eraID, eraHex: eraHex,
                                        eraName: eraName, era: n.era, nodes: [n],
                                        ry: n.year, rm: n.month, rd: n.day, events: evs)
                order.append(key)
            }
        }

        var cells: [TimelineCell] = order.compactMap { k in
            guard let g = groups[k] else { return nil }
            return TimelineCell(id: k, kind: g.kind, ordinal: g.ordinal, eraID: g.eraID,
                                eraHex: g.eraHex, eraName: g.eraName, era: g.era, nodes: g.nodes,
                                repYear: g.repYear, repMonth: g.repMonth, repDay: g.repDay, events: g.events)
        }
        cells.sort { $0.ordinal < $1.ordinal }
        assignLabels(&cells)
        return cells
    }

    private func events(at node: Node) -> [Event] {
        allEvents
            .filter { $0.node?.id == node.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func assignLabels(_ cells: inout [TimelineCell]) {
        var lastYear: Int? = nil
        var lastMonth: Int? = nil
        for i in cells.indices {
            let c = cells[i]
            let y = c.repYear
            switch granularity {
            case .year:
                cells[i].label = "\(y)年"
                lastYear = y; lastMonth = nil
            case .month:
                switch c.kind {
                case .year:
                    cells[i].label = "\(y)年"; lastYear = y; lastMonth = nil
                case .month, .day:
                    let m = c.repMonth ?? 0
                    cells[i].label = (lastYear == y) ? "\(m)月" : "\(y)年\(m)月"
                    lastYear = y; lastMonth = m
                }
            case .day:
                switch c.kind {
                case .year:
                    cells[i].label = "\(y)年"; lastYear = y; lastMonth = nil
                case .month:
                    let m = c.repMonth ?? 0
                    cells[i].label = (lastYear == y) ? "\(m)月" : "\(y)年\(m)月"
                    lastYear = y; lastMonth = m
                case .day:
                    let m = c.repMonth ?? 0
                    let d = c.repDay ?? 0
                    if lastYear == y && lastMonth == m { cells[i].label = "\(d)" }
                    else if lastYear == y { cells[i].label = "\(m)/\(d)" }
                    else { cells[i].label = "\(y)/\(m)/\(d)" }
                    lastYear = y; lastMonth = m
                }
            }
        }
    }
}

// MARK: - 事件列（操作鈕常駐淡顯）

@MainActor
private struct EventRow: View {
    @Bindable var event: Event
    let allCharacters: [Character]
    @Environment(\.modelContext) private var modelContext
    @State private var hovering = false
    @State private var editing = false
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editing {
                TextField("事件標題", text: $event.title)
                    .textFieldStyle(.roundedBorder).font(.caption)
                TextField("詳情（選填）", text: $event.detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder).font(.caption2).lineLimit(2...4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("參與角色").font(.caption2).foregroundStyle(.secondary)
                    if allCharacters.isEmpty {
                        Text("尚無角色").font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(allCharacters, id: \.id) { c in
                                    let sel = selectedIDs.contains(c.id.uuidString)
                                    Button {
                                        if selectedIDs.contains(c.id.uuidString) {
                                            selectedIDs.remove(c.id.uuidString)
                                        } else {
                                            selectedIDs.insert(c.id.uuidString)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: sel ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(sel ? Color.accentColor : .secondary)
                                            Text(sailuneDisplayName(c)).font(.caption2)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 90)
                    }
                }

                HStack {
                    Spacer()
                    Button("完成") {
                        event.characters = allCharacters.filter { selectedIDs.contains($0.id.uuidString) }
                        editing = false
                        hovering = false
                        try? modelContext.save()
                    }
                    .buttonStyle(.borderedProminent).font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(event.isVisible ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title.isEmpty ? "（無標題事件）" : event.title)
                            .font(.caption).foregroundStyle(.primary)
                        if !event.detail.isEmpty {
                            Text(event.detail)
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Button {
                            event.isVisible.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: event.isVisible ? "eye.fill" : "eye.slash")
                                .font(.caption2)
                                .foregroundStyle(event.isVisible ? .secondary : .tertiary)
                                .padding(4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("顯示於主時間軸")
                        Button {
                            selectedIDs = Set(event.characters.map { $0.id.uuidString })
                            editing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("編輯事件")
                        Button {
                            modelContext.delete(event)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .padding(4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("刪除事件")
                    }
                    .opacity(hovering ? 1.0 : eventActionIdleOpacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { flag in
                    withAnimation(.easeInOut(duration: 0.12)) { hovering = flag }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 手動新增釘子 popover

@MainActor
private struct AddNodePopover: View {
    let book: Book
    let target: Timeline?
    let eras: [Era]
    @Binding var yearText: String
    @Binding var monthText: String
    @Binding var dayText: String
    @Binding var eraID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
    private var parsedYear: Int? {
        let t = trimmed(yearText)
        guard !t.isEmpty, let v = Int(t), v > 0 else { return nil }
        return v
    }
    private var parsedMonth: Int? {
        let t = trimmed(monthText)
        guard !t.isEmpty, let v = Int(t), (1...12).contains(v) else { return nil }
        return v
    }
    private var parsedDay: Int? {
        let t = trimmed(dayText)
        guard !t.isEmpty, let v = Int(t), (1...31).contains(v) else { return nil }
        return v
    }

    private var validationHint: String? {
        if !trimmed(yearText).isEmpty && parsedYear == nil { return "年份需為正整數" }
        if !trimmed(monthText).isEmpty && parsedMonth == nil { return "月份需為 1–12" }
        if !trimmed(dayText).isEmpty && parsedDay == nil { return "日期需為 1–31" }
        if !trimmed(dayText).isEmpty && trimmed(monthText).isEmpty { return "有日必先有月" }
        return nil
    }

    private var canSave: Bool { parsedYear != nil && validationHint == nil }

    private var targetName: String {
        guard let t = target else { return "（無軸）" }
        return t.isPrimary ? "主軸" : (t.name.isEmpty ? "副軸" : t.name)
    }

    private func eraDisplayName(_ era: Era) -> String {
        era.name.isEmpty ? "未命名紀元" : era.name
    }

    private var previewHex: String {
        if let id = eraID, let e = eras.first(where: { $0.id == id }) { return e.color }
        return book.currentEra?.color ?? "#888888"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("新增時間釘子").font(.system(.headline, design: .serif))
                Spacer()
                Text(targetName)
                    .font(.caption2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("年號").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: previewHex) ?? .gray).frame(width: 12, height: 12)
                    Picker("", selection: $eraID) {
                        if eras.isEmpty {
                            Text("（無年號）").tag(Optional<UUID>.none)
                        } else {
                            ForEach(eras) { e in
                                Text(eraDisplayName(e)).tag(e.id as UUID?)
                            }
                        }
                    }
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("日期（月、日選填）").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("年", text: $yearText)
                        .textFieldStyle(.roundedBorder).font(.caption)
                        .frame(maxWidth: .infinity)
                    TextField("月", text: $monthText)
                        .textFieldStyle(.roundedBorder).font(.caption)
                        .frame(width: 44)
                    TextField("日", text: $dayText)
                        .textFieldStyle(.roundedBorder).font(.caption)
                        .frame(width: 44)
                        .disabled(trimmed(monthText).isEmpty)
                }
            }

            if let hint = validationHint {
                Text(hint)
                    .font(.caption2).foregroundStyle(.red.opacity(0.85))
                    .transition(.opacity)
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("新增") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || target == nil)
            }
        }
        .padding(16)
        .frame(width: 260)
        .animation(.easeInOut(duration: 0.15), value: validationHint)
    }

    private func commit() {
        guard let y = parsedYear, let target else { return }
        _ = try? TimelineEngine.Bootstrap.ensure(for: book, in: modelContext)
        let era = eras.first { $0.id == eraID } ?? book.currentEra
        let node = Node(year: y, month: parsedMonth, day: parsedDay)
        modelContext.insert(node)
        node.era = era
        node.timeline = target
        node.section = nil
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 年號管理 popover

@MainActor
private struct EraManagerPopover: View {
    let book: Book
    @Query private var eras: [Era]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var sortedEras: [Era] { eras.sorted { $0.startOrdinal < $1.startOrdinal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("年號管理").font(.system(.headline, design: .serif))
            Text("紀元為全書共享的時間皮膚。序數較小者排在時間河上游；填負數可建立前史紀元，供副軸落釘。改元（踰年推進敘事）請於主軸操作。")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sortedEras) { era in
                        EraRow(era: era)
                    }
                }
            }
            .frame(maxHeight: 260)
            Button { addEra() } label: {
                Label("新增紀元", systemImage: "plus.circle").font(.caption)
            }
            .buttonStyle(.plain)
            HStack {
                Spacer()
                Button("完成") {
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func addEra() {
        let next = (eras.map(\.startOrdinal).max() ?? 0) + 1
        let e = Era(name: "", color: "#888888", startOrdinal: next)
        modelContext.insert(e)
    }
}

@MainActor
private struct EraRow: View {
    @Bindable var era: Era
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: era.color) ?? .gray).frame(width: 12, height: 12)
                TextField("紀元名", text: $era.name)
                    .textFieldStyle(.roundedBorder).font(.caption)
            }
            HStack(spacing: 8) {
                Text("序").font(.caption2).foregroundStyle(.secondary)
                TextField("", value: $era.startOrdinal, format: .number)
                    .textFieldStyle(.roundedBorder).font(.caption).frame(width: 72)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(eraPalette, id: \.self) { hex in
                            Button { era.color = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(era.color == hex ? Color.primary : .clear, lineWidth: 1.5))
                                    .scaleEffect(hovering && era.color == hex ? 1.12 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(hovering ? 0.05 : 0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}

// MARK: - 改元 popover

private let eraPalette: [String] = [
    "#C0392B", "#E67E22", "#F1C40F", "#27AE60",
    "#2980B9", "#8E44AD", "#16A085", "#7F8C8D"
]

@MainActor
private struct EraChangePopover: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedHex = eraPalette[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("改元（踰年）").font(.system(.headline, design: .serif))
            TextField("新年號名", text: $name)
            Text("年號色").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(eraPalette, id: \.self) { hex in
                    Button { selectedHex = hex } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(selectedHex == hex ? Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("確認改元") {
                    _ = try? TimelineEngine.EraChange.perform(
                        for: book,
                        input: .init(newName: name, newColor: selectedHex),
                        in: modelContext
                    )
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - 編輯既有年號 popover

@MainActor
private struct EraEditPopover: View {
    @Bindable var era: Era
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("編輯年號").font(.system(.headline, design: .serif))
            TextField("年號名", text: $era.name)
            Text("年號色").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(eraPalette, id: \.self) { hex in
                    Button { era.color = hex } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(era.color == hex ? Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("完成") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - hex → Color

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - 個人卡片時間投影（PRD 第 10 節主入口）

@MainActor
struct CharacterTimelineProjectionView: View {
    let character: Character
    @Query private var allEvents: [Event]
    @Environment(\.modelContext) private var modelContext

    private var myEvents: [Event] {
        allEvents
            .filter { $0.characters.contains(where: { $0.id == character.id }) }
            .sorted { ordinal(of: $0) < ordinal(of: $1) }
    }

    private var visibleCount: Int {
        myEvents.filter { TimelineEngine.Visibility.isVisibleOnPrimaryAxis($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            if myEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(myEvents, id: \.id) { e in
                            EventProjectionRow(event: e)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.05), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(sailuneDisplayName(character))
                .font(.system(.headline, design: .serif))
                .lineLimit(1)
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                statBlock(value: myEvents.count, label: "筆事件")
                statBlock(value: visibleCount, label: "上主軸", accent: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.accentColor.opacity(0.5), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1.5)
        }
    }

    private func statBlock(value: Int, label: String, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(value)")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(accent ? Color.accentColor : .primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("尚未踏入時間")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
            Text("在右欄時間軸為這角色記錄事件後，其一生足跡將在此呈現。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func ordinal(of e: Event) -> Int {
        guard let n = e.node else { return Int.max }
        return TimelineEngine.Core.ordinal(
            eraStart: n.era?.startOrdinal ?? 1,
            year: n.year, month: n.month, day: n.day
        )
    }
}

// MARK: - 投影事件列（含 isVisible 主開關）

@MainActor
private struct EventProjectionRow: View {
    @Bindable var event: Event
    @Environment(\.modelContext) private var modelContext
    @State private var hovering = false

    private var bandColor: Color {
        if !event.isVisible { return .secondary.opacity(0.25) }
        if let hex = event.node?.era?.color, let c = Color(hex: hex) { return c }
        return .accentColor
    }

    private var timeLabel: String {
        guard let n = event.node else { return "未定時間" }
        var s = n.year > 0 ? "\(n.year)年" : ""
        if let m = n.month {
            s += "\(m)月"
            if let d = n.day { s += "\(d)日" }
        }
        return s.isEmpty ? "未設定世界時間" : s
    }

    private var nodeHidesIt: Bool {
        event.isVisible && (event.node?.isVisible == false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(bandColor)
                .frame(width: hovering ? 4 : 3)
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.15), value: hovering)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? "（無標題事件）" : event.title)
                    .font(.caption)
                    .foregroundStyle(event.isVisible ? .primary : .secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(timeLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if nodeHidesIt {
                        Text("· 所在節點已隱藏")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    event.isVisible.toggle()
                }
                try? modelContext.save()
            } label: {
                ZStack {
                    Circle()
                        .fill(event.isVisible ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(
                                event.isVisible ? Color.clear : Color.secondary.opacity(0.4),
                                lineWidth: 1
                            )
                        )
                        .scaleEffect(hovering ? 1.08 : 1.0)
                    Image(systemName: event.isVisible ? "eye.fill" : "eye.slash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(event.isVisible ? .white : .secondary)
                }
            }
            .buttonStyle(.plain)
            .help("顯示於主時間軸")
            .padding(.trailing, 10)
            .padding(.top, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovering ? 0.05 : 0.0))
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}
