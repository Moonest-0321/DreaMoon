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
    case outline = "大綱"
    var id: String { rawValue }
}

private enum SailuneOutlineTab: String, CaseIterable, Identifiable {
    case narrative = "敘事大綱"
    case timeline = "時間軸"
    var id: String { rawValue }
}

enum SailuneTimelineGranularity: String, CaseIterable, Identifiable {
    case year = "年", month = "月", day = "日"
    var id: String { rawValue }
}

@MainActor
struct WorkspaceInspectorView: View {
    let book: Book
    let currentSection: Section?
    var focusedCharacter: Character? = nil
    var focusRequestID = UUID()
    var onSelectSection: ((Section) -> Void)? = nil
    var onOpenStoryTag: ((StoryTag) -> Void)? = nil
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @State private var tab: SailuneInspectorTab = .settings
    @State private var outlineTab: SailuneOutlineTab = .narrative

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
            .background(Color.workspacePanelBackground)
            Divider()
            switch tab {
            case .settings:
                InspectorRootView(
                    book: book,
                    currentSection: currentSection,
                    focusedCharacter: focusedCharacter,
                    focusRequestID: focusRequestID,
                    onSelectSection: onSelectSection,
                    onOpenStoryTag: onOpenStoryTag
                )
            case .outline:
                outlineWorkspace
            }
        }
        .background(Color.workspacePanelBackground)
        .onAppear { showFocusedCharacter() }
        .onChange(of: focusedCharacter?.id) { _, _ in showFocusedCharacter() }
        .onChange(of: focusRequestID) { _, _ in showFocusedCharacter() }
    }

    private func showFocusedCharacter() {
        guard focusedCharacter != nil else { return }
        tab = .settings
    }

    private var outlineWorkspace: some View {
        VStack(spacing: 0) {
            Picker("大綱種類", selection: $outlineTab) {
                ForEach(SailuneOutlineTab.allCases) { outlineTab in
                    Text(outlineTab.rawValue).tag(outlineTab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch outlineTab {
            case .narrative:
                NarrativeOutlineNavigationView(
                    book: book,
                    onOpenOutlineItem: onOpenOutlineItem
                )
            case .timeline:
                TimelineOutlineNavigationView(
                    book: book,
                    onOpenSection: onSelectSection
                )
            }
        }
    }
}

@MainActor
private struct NarrativeOutlineNavigationView: View {
    let book: Book
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)?
    @Environment(StoryPlanningStore.self) private var planningStore

    private var orderedItems: [OutlineItem] {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: planningStore.items(bookID: book.id).map { ($0.id, $0) }
        )
        return planningStore.narrativeOutlineList(book: book).itemIDsInDisplayOrder.compactMap { itemsByID[$0] }
    }

    var body: some View {
        OutlineNavigationList(items: orderedItems) { item in
            guard let anchor = validAnchor(for: item) else { return nil }
            return { onOpenOutlineItem?(item, anchor) }
        }
    }

    private func validAnchor(for item: OutlineItem) -> OutlineItemAnchor? {
        guard let anchor = planningStore.anchor(outlineItemID: item.id) else { return nil }
        let sectionIDs = Set(BookStructure.orderedSections(in: book).map(\.id))
        return sectionIDs.contains(anchor.sectionID) ? anchor : nil
    }
}

@MainActor
private struct TimelineOutlineNavigationView: View {
    let book: Book
    var onOpenSection: ((Section) -> Void)?
    @Query private var allTimelines: [Timeline]
    @Query private var allNodes: [Node]
    @Query private var allEvents: [Event]

    init(book: Book, onOpenSection: ((Section) -> Void)? = nil) {
        self.book = book
        self.onOpenSection = onOpenSection
        let bookID = book.id
        _allTimelines = Query(filter: #Predicate<Timeline> { $0.book?.id == bookID })
        _allNodes = Query()
        _allEvents = Query()
    }

    private var primaryTimeline: Timeline? {
        allTimelines.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.sortOrder < rhs.sortOrder
        }.first
    }

    private var orderedEvents: [Event] {
        guard let primaryTimeline else { return [] }
        let nodes = TimelineEngine.Query.sorted(
            allNodes.filter { $0.timeline?.id == primaryTimeline.id && (!$0.isVisible ? !primaryTimeline.isPrimary : true) }
        )
        let cells = TimelineDateProjection.cells(
            nodes: nodes,
            events: allEvents,
            primary: primaryTimeline.isPrimary,
            granularity: .day
        )
        return TimelineDateProjection.eventsInDisplayOrder(cells: cells)
    }

    var body: some View {
        OutlineNavigationList(items: orderedEvents) { event in
            guard let section = validSection(for: event) else { return nil }
            return { onOpenSection?(section) }
        }
    }

    private func validSection(for event: Event) -> Section? {
        guard let section = event.section else { return nil }
        return BookStructure.orderedSections(in: book).contains(where: { $0.id == section.id }) ? section : nil
    }
}

private struct OutlineNavigationList<Item: Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    let action: (Item) -> (() -> Void)?

    init(items: [Item], title: @escaping (Item) -> String, action: @escaping (Item) -> (() -> Void)?) {
        self.items = items
        self.title = title
        self.action = action
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("尚無可顯示的標題", systemImage: "list.bullet")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        let displayTitle = normalizedTitle(item)
        if let action = action(item) {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleText(displayTitle)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(displayTitle)
            .accessibilityLabel(displayTitle)
        } else {
            titleText(displayTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .foregroundStyle(.secondary)
                .help(displayTitle)
                .accessibilityLabel(displayTitle)
        }
    }

    private func titleText(_ value: String) -> some View {
        Text(value)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private func normalizedTitle(_ item: Item) -> String {
        let value = title(item).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未命名項目" : value
    }
}

private extension OutlineNavigationList where Item == OutlineItem {
    init(items: [OutlineItem], action: @escaping (OutlineItem) -> (() -> Void)?) {
        self.init(items: items, title: \OutlineItem.title, action: action)
    }
}

private extension OutlineNavigationList where Item == Event {
    init(items: [Event], action: @escaping (Event) -> (() -> Void)?) {
        self.init(items: items, title: \Event.title, action: action)
    }
}

// MARK: - 格子模型

enum CellKind { case year, month, day }

struct TimelineCell: Identifiable {
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

struct TimelineEraGroup: Identifiable {
    let id: String
    let eraID: UUID?
    let name: String
    let colorHex: String
    let era: Era?
    let cells: [TimelineCell]
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

// MARK: - 時間軸面板

@MainActor
struct TimelinePanelView: View {
    let book: Book
    let allowsWideLayout: Bool
    var onOpenSection: ((Section) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(StoryPlanningStore.self) private var planningStore

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
    @State private var selectedCellID: String?
    @State private var collapsedEraGroups: Set<String> = []
    @State private var collapsedWideCells: Set<String> = []
    @State private var selectedEvent: Event?
    @State private var operationError: String?
    @State private var firstVisibleWideCellIndex = 0
    @State private var pendingDeleteEvent: Event?
    @State private var showingCreateEvent = false
    @State private var createEventFromOutline = false

    init(book: Book, allowsWideLayout: Bool = false, onOpenSection: ((Section) -> Void)? = nil) {
        self.book = book
        self.allowsWideLayout = allowsWideLayout
        self.onOpenSection = onOpenSection
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

    private var operationErrorBinding: Binding<Bool> {
        Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
    }

    private var deleteEventBinding: Binding<Bool> {
        Binding(get: { pendingDeleteEvent != nil }, set: { if !$0 { pendingDeleteEvent = nil } })
    }

    private var deleteTimelineBinding: Binding<Bool> {
        Binding(get: { pendingDeleteTimeline != nil }, set: { if !$0 { pendingDeleteTimeline = nil } })
    }

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
        .task {
            do {
                try TimelineEngine.Bootstrap.ensure(for: book, in: modelContext)
                try cleanTimelineMetadataOrphans()
            }
            catch { operationError = error.localizedDescription }
        }
        .onChange(of: selectedTimeline?.id) { _, _ in resetSelection() }
        .onChange(of: granularity) { _, _ in resetSelection() }
        .alert("時間軸操作失敗", isPresented: operationErrorBinding) { Button("好") { operationError = nil } } message: {
            Text(operationError ?? "未知錯誤")
        }
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
        .alert("刪除事件卡片",
               isPresented: deleteEventBinding,
               presenting: pendingDeleteEvent) { event in
            Button("取消", role: .cancel) { pendingDeleteEvent = nil }
            Button("刪除", role: .destructive) { performDeleteEvent(event) }
        } message: { _ in
            Text("只會刪除此事件卡片；日期節點、敘事大綱與正文都會保留。")
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
                do { try modelContext.save() }
                catch { operationError = error.localizedDescription; return }
                pendingRenameTimeline = nil
            }
        }
        .alert("刪除副軸",
               isPresented: deleteTimelineBinding,
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
        .popover(isPresented: $showingEraChange) {
            EraChangePopover(book: book)
        }
        .sheet(isPresented: $showingCreateEvent) {
            TimelineEventCreationView(
                book: book,
                timeline: selectedTimeline,
                eras: allEras,
                startsFromOutline: createEventFromOutline
            )
        }
        .sheet(item: $selectedEvent) { event in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("事件詳情").font(.headline)
                    Spacer()
                    Button("完成") { selectedEvent = nil }
                        .buttonStyle(PlanningActionStyle(prominent: true))
                }
                Divider()
                TimelineEventBindingControls(event: event, book: book)
                EventRow(event: event, allCharacters: sortedCharacters)
            }
            .padding(16)
            .frame(minWidth: 420, idealWidth: 520, minHeight: 260)
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
                                .font(.body)
                                .padding(.horizontal, 10).frame(minHeight: 30)
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
                }
                .padding(.horizontal, 12)
            }
            ViewThatFits(in: .horizontal) {
                if allowsWideLayout {
                    HStack {
                        addNodeButton
                        timelineActions
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    addNodeButton
                    Menu("時間軸操作", systemImage: "ellipsis.circle") { timelineActions }
                        .controlSize(.large)
                }
            }
            .buttonStyle(PlanningActionStyle())
            .padding(.horizontal, 12)
            Picker("日期顯示粒度", selection: $granularity) {
                ForEach(SailuneTimelineGranularity.allCases) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    private var addNodeButton: some View {
        Menu("新增", systemImage: "plus.circle.fill") {
            Button("新增預排事件", systemImage: "rectangle.dashed") {
                createEventFromOutline = false
                showingCreateEvent = true
            }
            Button("從敘事大綱加入", systemImage: "text.badge.plus") {
                createEventFromOutline = true
                showingCreateEvent = true
            }
            Divider()
            Button("只新增日期節點", systemImage: "mappin.circle", action: openAddNode)
        }
            .buttonStyle(PlanningActionStyle(prominent: true))
            .disabled(selectedTimeline == nil)
            .help(selectedTimeline == nil ? "請先選擇時間軸" : "新增事件或日期節點")
    }

    @ViewBuilder
    private var timelineActions: some View {
        Button("紀元管理", systemImage: "list.bullet.rectangle") {
            showingEraManager = true
        }
            .help("新增或編輯紀元")
        Button("新增副軸", systemImage: "plus") {
            newSecondaryName = ""
            showingAddSecondary = true
        }
        Button("改元", systemImage: "calendar.badge.plus") {
            showingEraChange = true
        }
            .disabled(!isPrimarySelected)
            .help(isPrimarySelected ? "建立新紀元並推進主軸" : "請切換至主軸後改元")
    }

    private var axisContent: some View {
        let cells = buildCells()
        let cellIDs = cells.map(\.id)
        return Group {
            if allowsWideLayout {
                wideOutlineContent(cells: cells)
            } else {
                compactAxisContent(cells: cells)
            }
        }
        .onChange(of: cellIDs) { _, ids in
            if let selectedCellID, !ids.contains(selectedCellID) { self.selectedCellID = nil }
            expandedCells.formIntersection(ids)
            collapsedWideCells.formIntersection(ids)
            let eraIDs = Set(TimelineDateProjection.eraGroups(cells: cells).map(\.id))
            collapsedEraGroups.formIntersection(eraIDs)
        }
    }

    private func wideOutlineContent(cells: [TimelineCell]) -> some View {
        let labels = TimelineDateProjection.relativeLabels(
            cells: cells,
            granularity: granularity,
            firstVisibleIndex: firstVisibleWideCellIndex
        )
        return Group {
            if cells.isEmpty {
                ContentUnavailableView(
                    "尚無時間記錄",
                    systemImage: "clock",
                    description: Text("使用上方「新增」建立預排事件、加入敘事大綱項目或建立日期節點。")
                )
                .padding(.top, 40)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                            wideTimelineSlot(cell, label: labels[index], isLast: index == cells.count - 1)
                                .frame(width: 190, alignment: .top)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
                .onScrollGeometryChange(for: Int.self) { geometry in
                    max(0, Int(geometry.contentOffset.x / 190))
                } action: { _, index in
                    firstVisibleWideCellIndex = min(index, max(0, cells.count - 1))
                }
            }
        }
    }

    private func wideTimelineSlot(_ cell: TimelineCell, label: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(cell.eraName.isEmpty ? " " : cell.eraName)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(height: 38)
            ZStack {
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
                Circle().fill(Color(hex: cell.eraHex) ?? .accentColor).frame(width: 9, height: 9)
                if isLast {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 18)
            VStack(spacing: 10) {
                ForEach(cell.events, id: \.id) { event in
                    timelineCard(event)
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 8)
        }
    }

    private func timelineCard(_ event: Event) -> some View {
        let presentation = TimelineCardProjection.presentation(
            event: event,
            book: book,
            metadata: planningStore.timelineMetadata(eventID: event.id),
            planningStore: planningStore
        )
        return TimelineEventCardView(
            event: event,
            presentation: presentation,
            onOpen: { open(event) },
            onDelete: { pendingDeleteEvent = event }
        )
    }

    private func performDeleteEvent(_ event: Event) {
        let eventID = event.id
        modelContext.delete(event)
        do {
            try modelContext.save()
            try planningStore.deleteTimelineMetadata(eventID: eventID)
            pendingDeleteEvent = nil
        } catch {
            modelContext.rollback()
            operationError = error.localizedDescription
        }
    }

    private func wideEraSection(_ group: TimelineEraGroup) -> some View {
        let collapsed = collapsedEraGroups.contains(group.id)
        let color = Color(hex: group.colorHex) ?? .gray
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { toggleWideEra(group.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .frame(width: 12)
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                        Text(group.name).font(.headline)
                        Spacer()
                        Text("\(group.cells.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let era = group.era {
                    Button("編輯紀元", systemImage: "pencil") { editingEra = era }
                        .buttonStyle(PlanningActionStyle())
                }
            }
            if !collapsed {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.cells) { cell in
                        wideDateSection(cell)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(14)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.2)))
    }

    private func wideDateSection(_ cell: TimelineCell) -> some View {
        let collapsed = collapsedWideCells.contains(cell.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { toggleWideCell(cell.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .frame(width: 12)
                        Text(cell.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(cell.events.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button("刪除時間釘子", systemImage: "trash", role: .destructive) {
                    requestDeleteNodes(cell.nodes)
                }
                .buttonStyle(PlanningActionStyle())
            }
            if !collapsed {
                VStack(alignment: .leading, spacing: 3) {
                    if cell.events.isEmpty && addingEventToCell != cell.id {
                        Text("尚無事件").font(.callout).foregroundStyle(.secondary).padding(.leading, 18)
                    } else {
                        ForEach(cell.events, id: \.id) { event in
                            Button { open(event) } label: {
                                HStack(spacing: 10) {
                                    Text(event.title.isEmpty ? "未命名事件" : event.title)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 12)
                                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            .help(event.title.isEmpty ? "未命名事件" : event.title)
                        }
                    }
                    if addingEventToCell == cell.id {
                        addEventForm(cell: cell)
                    } else {
                        Button("新增事件", systemImage: "plus.circle") {
                            selectedCharIDs = []
                            withAnimation(.snappy) { addingEventToCell = cell.id }
                        }
                        .buttonStyle(PlanningActionStyle(prominent: true))
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private func open(_ event: Event) {
        if let section = event.section, BookStructure.orderedSections(in: book).contains(where: { $0.id == section.id }) {
            onOpenSection?(section)
        } else {
            selectedEvent = event
        }
    }

    private func toggleWideEra(_ id: String) {
        withAnimation(.snappy) {
            if collapsedEraGroups.contains(id) { collapsedEraGroups.remove(id) }
            else { collapsedEraGroups.insert(id) }
        }
    }

    private func toggleWideCell(_ id: String) {
        withAnimation(.snappy) {
            if collapsedWideCells.contains(id) { collapsedWideCells.remove(id) }
            else { collapsedWideCells.insert(id) }
        }
    }

    private func resetSelection() {
        selectedCellID = nil
        expandedCells = []
        collapsedCharGroups = []
        collapsedEraGroups = []
        collapsedWideCells = []
        // 已輸入的事件草稿保留，重新選擇日期後可繼續使用。
        addingEventToCell = nil
    }

    private func compactAxisContent(cells: [TimelineCell]) -> some View {
        ScrollView {
            if cells.isEmpty {
                ContentUnavailableView(
                    "尚無時間記錄",
                    systemImage: "clock",
                    description: Text("使用上方「新增時間釘子」建立日期，再展開日期新增事件。")
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
                .animation(.snappy, value: cells.map(\.id))
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
                    Button("編輯紀元", systemImage: "pencil") { editingEra = era }
                    .buttonStyle(PlanningActionStyle())
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
                    Button("刪除釘子", systemImage: "trash", role: .destructive) {
                        requestDeleteNodes(cell.nodes)
                    }
                    .buttonStyle(PlanningActionStyle())
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
                }
                .buttonStyle(PlanningActionStyle(prominent: true))
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
                .buttonStyle(PlanningActionStyle())
                Spacer()
                Button("儲存") {
                    withAnimation(.snappy) { commitAddEvent(to: cell) }
                }
                .buttonStyle(PlanningActionStyle(prominent: true))
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
        do { try modelContext.save() }
        catch { modelContext.delete(ev); operationError = error.localizedDescription; return }
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
            try cleanTimelineMetadataOrphans()
        } catch {
            operationError = error.localizedDescription
        }
        pendingDeleteNodes = []
    }

    private func commitAddSecondary() {
        let name = newSecondaryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let t = try TimelineEngine.addSecondaryTimeline(for: book, name: name, in: modelContext)
            selectedTimelineID = t.id
        } catch { operationError = error.localizedDescription; return }
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
            try cleanTimelineMetadataOrphans()
        } catch {
            operationError = error.localizedDescription
        }
        pendingDeleteTimeline = nil
    }

    private func cleanTimelineMetadataOrphans() throws {
        let validEventIDs = Set(try modelContext.fetch(FetchDescriptor<Event>()).map(\.id))
        try planningStore.removeOrphanedTimelineMetadata(validEventIDs: validEventIDs)
    }

    private func openAddNode() {
        newNodeYearText = ""
        newNodeMonthText = ""
        newNodeDayText = ""
        newNodeEraID = book.currentEra?.id
        showingAddNode = true
    }

    private func buildCells() -> [TimelineCell] {
        TimelineDateProjection.cells(nodes: visibleNodes, events: allEvents, primary: isPrimarySelected, granularity: granularity)
    }

    private func events(at node: Node) -> [Event] {
        allEvents
            .filter { $0.node?.id == node.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

}

// 寬窄版共用的唯讀日期投影，與捲動、選取及編輯狀態分離。
@MainActor
enum TimelineDateProjection {
    static func cells(nodes: [Node], events: [Event], primary: Bool, granularity: SailuneTimelineGranularity) -> [TimelineCell] {
        var groups: [String: CellAccum] = [:]
        var order: [String] = []

        for n in TimelineEngine.Query.sorted(nodes) where n.year != 0 && (!primary || n.isVisible) {
            let ord = n.absoluteOrdinal
            let absYear = ord / 10000
            let absMonth = ord / 100
            let eraHex = n.era?.color ?? "#888888"
            let eraName = n.era?.name ?? ""
            let eraID = n.era?.id
            let hasMonth = n.month != nil
            let hasDay = n.day != nil

            let nodeEvents = events.filter { $0.node?.id == n.id }.sorted { $0.sortOrder < $1.sortOrder }
            let evs = primary
                ? nodeEvents.filter { TimelineEngine.Visibility.isVisibleOnPrimaryAxis($0) }
                : nodeEvents

            var key: String
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

            key = "\(eraID?.uuidString ?? "none"):\(key)"
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
        assignLabels(&cells, granularity: granularity)
        return cells
    }

    static func eraGroups(cells: [TimelineCell]) -> [TimelineEraGroup] {
        var groups: [TimelineEraGroup] = []
        var indexByID: [String: Int] = [:]
        for cell in cells {
            let id = cell.eraID?.uuidString ?? "none"
            if let index = indexByID[id] {
                let existing = groups[index]
                groups[index] = TimelineEraGroup(
                    id: existing.id,
                    eraID: existing.eraID,
                    name: existing.name,
                    colorHex: existing.colorHex,
                    era: existing.era,
                    cells: existing.cells + [cell]
                )
            } else {
                indexByID[id] = groups.count
                groups.append(TimelineEraGroup(
                    id: id,
                    eraID: cell.eraID,
                    name: cell.eraName.isEmpty ? (cell.eraID == nil ? "未指定紀元" : "未命名紀元") : cell.eraName,
                    colorHex: cell.eraHex,
                    era: cell.era,
                    cells: [cell]
                ))
            }
        }
        return groups
    }

    static func eventsInDisplayOrder(cells: [TimelineCell]) -> [Event] {
        cells.flatMap { cell in
            cell.events.sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    static func relativeLabels(
        cells: [TimelineCell],
        granularity: SailuneTimelineGranularity,
        firstVisibleIndex: Int
    ) -> [String] {
        guard !cells.isEmpty else { return [] }
        let start = min(max(0, firstVisibleIndex), cells.count - 1)
        var labels = cells.map(\.label)
        var lastYear: Int?
        var lastMonth: Int?
        var lastEraID: UUID?
        for index in cells.indices {
            let cell = cells[index]
            let beginsVisibleSequence = index == start
            let eraChanged = index > start && cell.eraID != lastEraID
            if index < start { continue }
            if beginsVisibleSequence || eraChanged {
                labels[index] = fullLabel(for: cell, granularity: granularity)
                lastYear = cell.repYear
                lastMonth = cell.repMonth
                lastEraID = cell.eraID
                continue
            }
            switch granularity {
            case .year:
                labels[index] = "\(cell.repYear)年"
            case .month:
                if cell.repYear == lastYear, let month = cell.repMonth {
                    labels[index] = "\(month)月"
                } else {
                    labels[index] = fullLabel(for: cell, granularity: granularity)
                }
            case .day:
                if cell.repYear == lastYear, cell.repMonth == lastMonth, let day = cell.repDay {
                    labels[index] = "\(day)日"
                } else if cell.repYear == lastYear, let month = cell.repMonth, let day = cell.repDay {
                    labels[index] = "\(month)月\(day)日"
                } else {
                    labels[index] = fullLabel(for: cell, granularity: granularity)
                }
            }
            lastYear = cell.repYear
            lastMonth = cell.repMonth
            lastEraID = cell.eraID
        }
        return labels
    }

    private static func fullLabel(for cell: TimelineCell, granularity: SailuneTimelineGranularity) -> String {
        switch granularity {
        case .year:
            return "\(cell.repYear)年"
        case .month:
            guard let month = cell.repMonth else { return "\(cell.repYear)年" }
            return "\(cell.repYear)年\(month)月"
        case .day:
            guard let month = cell.repMonth else { return "\(cell.repYear)年" }
            guard let day = cell.repDay else { return "\(cell.repYear)年\(month)月" }
            return "\(cell.repYear)年\(month)月\(day)日"
        }
    }

    private static func assignLabels(_ cells: inout [TimelineCell], granularity: SailuneTimelineGranularity) {
        var lastYear: Int? = nil
        var lastMonth: Int? = nil
        for i in cells.indices {
            let c = cells[i]
            if i > 0 && cells[i - 1].eraID != c.eraID {
                lastYear = nil
                lastMonth = nil
            }
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

struct TimelineCardPresentation {
    let isWritten: Bool
    let locationText: String
    let excerpt: String
    let accessibilityText: String
}

private struct TimelineEventCardView: View {
    let event: Event
    let presentation: TimelineCardPresentation
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title.isEmpty ? "未命名事件" : event.title)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                        .padding(.trailing, 20)
                    Text(presentation.locationText)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if !presentation.excerpt.isEmpty {
                        Text(presentation.excerpt)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("刪除事件卡片")
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay { border }
        .help(presentation.accessibilityText)
        .accessibilityLabel(presentation.accessibilityText)
    }

    @ViewBuilder
    private var border: some View {
        if presentation.isWritten {
            RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.55), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 9)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.secondary.opacity(0.65))
        }
    }
}

@MainActor
enum TimelineCardProjection {
    static func presentation(
        event: Event,
        book: Book,
        metadata: TimelineEventCardMetadata?,
        planningStore: StoryPlanningStore
    ) -> TimelineCardPresentation {
        let sections = BookStructure.orderedSections(in: book)
        let legacySection = event.section.flatMap { section in sections.first { $0.id == section.id } }
        var resolvedSection: Section?
        var sourceIsValid = false
        var excerpt = ""

        if let metadata,
           metadata.bookID == book.id,
           let outlineItemID = metadata.outlineItemID,
           planningStore.items(bookID: book.id).contains(where: { $0.id == outlineItemID }),
           let anchor = planningStore.anchor(outlineItemID: outlineItemID),
           anchor.bookID == book.id,
           let section = sections.first(where: { $0.id == anchor.sectionID }) {
            resolvedSection = section
            sourceIsValid = true
            excerpt = metadata.excerptMode == .manual
                ? TimelineEventCardMetadata.limitedExcerpt(metadata.manualExcerpt)
                : automaticExcerpt(anchor: anchor, section: section)
        } else if let metadata, metadata.excerptMode == .manual {
            excerpt = TimelineEventCardMetadata.limitedExcerpt(metadata.manualExcerpt)
        }

        let section = resolvedSection ?? legacySection
        let location: String
        if let section {
            let volume = section.volume?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sectionTitle = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            location = "\(volume.isEmpty ? "未命名卷次" : volume)・\(sectionTitle.isEmpty ? "未命名節次" : sectionTitle)"
        } else if metadata?.outlineItemID != nil {
            location = "來源失效"
        } else {
            location = "尚未綁定"
        }
        let isWritten = sourceIsValid || legacySection != nil
        let title = event.title.isEmpty ? "未命名事件" : event.title
        return TimelineCardPresentation(
            isWritten: isWritten,
            locationText: location,
            excerpt: excerpt,
            accessibilityText: "\(title)，\(isWritten ? "已寫入" : "未寫入")，\(location)\(excerpt.isEmpty ? "" : "，\(excerpt)")"
        )
    }

    static func automaticExcerpt(anchor: OutlineItemAnchor, section: Section) -> String {
        let plainText = String(section.content.characters)
        let offset = anchor.resolvedOffset(in: plainText)
        let nsText = plainText as NSString
        guard offset < nsText.length else { return normalizedExcerpt(anchor.anchorText) }
        let candidate = nsText.substring(from: offset)
        let normalized = normalizedExcerpt(candidate)
        return normalized.isEmpty ? normalizedExcerpt(anchor.anchorText) : normalized
    }

    static func normalizedExcerpt(_ value: String) -> String {
        let normalized = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(normalized.prefix(30))
    }
}

@MainActor
private struct TimelineEventCreationView: View {
    let book: Book
    let timeline: Timeline?
    let eras: [Era]
    let startsFromOutline: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(StoryPlanningStore.self) private var planningStore
    @Environment(\.dismiss) private var dismiss
    @State private var yearText = ""
    @State private var monthText = ""
    @State private var dayText = ""
    @State private var title = ""
    @State private var detail = ""
    @State private var selectedEraID: UUID?
    @State private var selectedOutlineItemID: UUID?
    @State private var excerptMode: TimelineExcerptMode = .automatic
    @State private var manualExcerpt = ""
    @State private var saveError: String?

    private var outlineItems: [OutlineItem] {
        planningStore.items(bookID: book.id).filter { planningStore.anchor(outlineItemID: $0.id) != nil }
    }

    private var parsedYear: Int? { Int(yearText).flatMap { $0 > 0 ? $0 : nil } }
    private var parsedMonth: Int? { monthText.isEmpty ? nil : Int(monthText).flatMap { (1...12).contains($0) ? $0 : nil } }
    private var parsedDay: Int? { dayText.isEmpty ? nil : Int(dayText).flatMap { (1...31).contains($0) ? $0 : nil } }
    private var canSave: Bool {
        parsedYear != nil && timeline != nil && (!startsFromOutline || selectedOutlineItemID != nil)
            && !(dayText.isEmpty == false && parsedMonth == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(startsFromOutline ? "從敘事大綱加入" : "新增預排事件").font(.title3.weight(.semibold))
                Spacer()
            }
            if startsFromOutline {
                Picker("敘事大綱項目", selection: $selectedOutlineItemID) {
                    Text("請選擇").tag(Optional<UUID>.none)
                    ForEach(outlineItems, id: \.id) { item in
                        Text(item.title.isEmpty ? "未命名項目" : item.title).tag(item.id as UUID?)
                    }
                }
            }
            Picker("紀元", selection: $selectedEraID) {
                Text("未指定紀元").tag(Optional<UUID>.none)
                ForEach(eras, id: \.id) { era in
                    Text(era.name.isEmpty ? "未命名紀元" : era.name).tag(era.id as UUID?)
                }
            }
            HStack {
                TextField("年", text: $yearText).frame(width: 90)
                TextField("月", text: $monthText).frame(width: 70)
                TextField("日", text: $dayText).frame(width: 70)
            }
            TextField("標題（最多 10 字，留白則使用月／日）", text: $title)
                .onChange(of: title) { _, value in title = String(value.prefix(10)) }
            TextField("事件詳情（選填）", text: $detail, axis: .vertical).lineLimit(2...4)
            Picker("節錄來源", selection: $excerptMode) {
                ForEach(TimelineExcerptMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            if excerptMode == .manual {
                TextField("手動節錄（最多 30 字）", text: $manualExcerpt, axis: .vertical)
                    .lineLimit(2...2)
                    .onChange(of: manualExcerpt) { _, value in manualExcerpt = String(value.prefix(30)) }
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("加入時間軸") { commit() }
                    .buttonStyle(PlanningActionStyle(prominent: true))
                    .disabled(!canSave)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 480)
        .onAppear {
            selectedEraID = book.currentEra?.id
            if startsFromOutline { selectedOutlineItemID = outlineItems.first?.id }
        }
    }

    private func commit() {
        guard let timeline, let year = parsedYear else { return }
        let node = Node(year: year, month: parsedMonth, day: parsedDay)
        node.timeline = timeline
        node.era = eras.first { $0.id == selectedEraID } ?? book.currentEra
        let fallbackTitle: String
        if let month = parsedMonth, let day = parsedDay { fallbackTitle = "\(month)/\(day)" }
        else if let month = parsedMonth { fallbackTitle = "\(month)月" }
        else { fallbackTitle = "\(year)年" }
        let event = Event(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : String(title.prefix(10)), detail: detail)
        event.node = node
        if let itemID = selectedOutlineItemID,
           let anchor = planningStore.anchor(outlineItemID: itemID) {
            event.section = BookStructure.orderedSections(in: book).first { $0.id == anchor.sectionID }
        }
        modelContext.insert(node)
        modelContext.insert(event)
        do {
            try modelContext.save()
            try planningStore.ensureTimelineMetadata(
                eventID: event.id,
                bookID: book.id,
                outlineItemID: selectedOutlineItemID,
                excerptMode: excerptMode,
                manualExcerpt: manualExcerpt
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - 事件列（操作鈕常駐淡顯）

@MainActor
private struct TimelineEventBindingControls: View {
    @Bindable var event: Event
    let book: Book
    @Environment(StoryPlanningStore.self) private var planningStore
    @Environment(\.modelContext) private var modelContext
    @State private var selectedOutlineItemID: UUID?
    @State private var excerptMode: TimelineExcerptMode = .automatic
    @State private var manualExcerpt = ""
    @State private var saveError: String?

    private var availableItems: [OutlineItem] {
        planningStore.items(bookID: book.id).filter { planningStore.anchor(outlineItemID: $0.id) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("時間卡片來源").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("敘事大綱項目", selection: $selectedOutlineItemID) {
                Text("尚未綁定").tag(Optional<UUID>.none)
                ForEach(availableItems, id: \.id) { item in
                    Text(item.title.isEmpty ? "未命名項目" : item.title).tag(item.id as UUID?)
                }
            }
            Picker("節錄來源", selection: $excerptMode) {
                ForEach(TimelineExcerptMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            if excerptMode == .manual {
                TextField("手動節錄（最多 30 字）", text: $manualExcerpt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...2)
                    .onChange(of: manualExcerpt) { _, value in manualExcerpt = String(value.prefix(30)) }
            }
            HStack {
                if let saveError { Text(saveError).font(.caption2).foregroundStyle(.red) }
                Spacer()
                Button("儲存卡片來源") { saveBinding() }
                    .buttonStyle(PlanningActionStyle(prominent: true))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            let metadata = planningStore.timelineMetadata(eventID: event.id)
            selectedOutlineItemID = metadata?.outlineItemID
            excerptMode = metadata?.excerptMode ?? .automatic
            manualExcerpt = metadata?.manualExcerpt ?? ""
        }
    }

    private func saveBinding() {
        let section = selectedOutlineItemID
            .flatMap { planningStore.anchor(outlineItemID: $0) }
            .flatMap { anchor in BookStructure.orderedSections(in: book).first { $0.id == anchor.sectionID } }
        event.section = section
        do {
            try modelContext.save()
            try planningStore.ensureTimelineMetadata(
                eventID: event.id,
                bookID: book.id,
                outlineItemID: selectedOutlineItemID,
                excerptMode: excerptMode,
                manualExcerpt: manualExcerpt
            )
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

@MainActor
private struct EventRow: View {
    @Bindable var event: Event
    let allCharacters: [Character]
    @Environment(\.modelContext) private var modelContext
    @State private var hovering = false
    @State private var editing = false
    @State private var selectedIDs: Set<String> = []
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            if editing {
                TextField("事件標題", text: $event.title)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .onChange(of: event.title) { _, value in
                        if value.count > 10 { event.title = String(value.prefix(10)) }
                    }
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
                        do { try modelContext.save(); saveError = nil }
                        catch { saveError = error.localizedDescription; return }
                        editing = false
                        hovering = false
                    }
                    .buttonStyle(PlanningActionStyle(prominent: true))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
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
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            event.isVisible.toggle()
                            do { try modelContext.save(); saveError = nil }
                            catch { event.isVisible.toggle(); saveError = error.localizedDescription }
                        } label: {
                            Label(event.isVisible ? "主軸：顯示中" : "主軸：已隱藏", systemImage: event.isVisible ? "eye.fill" : "eye.slash")
                        }
                        .buttonStyle(PlanningActionStyle())
                        .help("顯示於主時間軸")
                        Button {
                            selectedIDs = Set(event.characters.map { $0.id.uuidString })
                            editing = true
                        } label: {
                            Label("編輯事件", systemImage: "pencil")
                        }
                        .buttonStyle(PlanningActionStyle())
                        .help("編輯事件")
                        Button {
                            modelContext.delete(event)
                            do { try modelContext.save() }
                            catch { saveError = error.localizedDescription }
                        } label: {
                            Label("刪除事件", systemImage: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(PlanningActionStyle())
                        .help("刪除事件")
                    }
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
    @State private var saveError: String?

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

            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }

            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(PlanningActionStyle())
                Spacer()
                Button("新增") { commit() }
                    .buttonStyle(PlanningActionStyle(prominent: true))
                    .disabled(!canSave || target == nil)
            }
        }
        .padding(16)
        .frame(width: 260)
        .animation(.easeInOut(duration: 0.15), value: validationHint)
    }

    private func commit() {
        guard let y = parsedYear, let target else { return }
        let era = eras.first { $0.id == eraID } ?? book.currentEra
        let node = Node(year: y, month: parsedMonth, day: parsedDay)
        modelContext.insert(node)
        node.era = era
        node.timeline = target
        node.section = nil
        do { try modelContext.save() }
        catch {
            modelContext.delete(node)
            saveError = error.localizedDescription
            return
        }
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
    @State private var saveError: String?

    private var sortedEras: [Era] { eras.sorted { $0.startOrdinal < $1.startOrdinal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("年號管理").font(.system(.headline, design: .serif))
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
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
                Label("新增紀元", systemImage: "plus.circle")
            }
            .buttonStyle(PlanningActionStyle())
            HStack {
                Spacer()
                Button("完成") {
                    do { try modelContext.save() }
                    catch { saveError = error.localizedDescription; return }
                    dismiss()
                }
                .buttonStyle(PlanningActionStyle(prominent: true))
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
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("改元（踰年）").font(.system(.headline, design: .serif))
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
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
                    do {
                    _ = try TimelineEngine.EraChange.perform(
                        for: book,
                        input: .init(newName: name, newColor: selectedHex),
                        in: modelContext
                    )
                    } catch { saveError = error.localizedDescription; return }
                    dismiss()
                }
                .buttonStyle(PlanningActionStyle(prominent: true))
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
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("編輯年號").font(.system(.headline, design: .serif))
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
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
                    do { try modelContext.save() }
                    catch { saveError = error.localizedDescription; return }
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
