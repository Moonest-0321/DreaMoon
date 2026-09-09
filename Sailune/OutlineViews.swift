import SwiftUI

/// 大綱操作共用點擊範圍；保留系統的焦點與停用語意。
struct PlanningActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(minWidth: 28, minHeight: prominent ? 32 : 30)
            .foregroundStyle(
                configuration.role == .destructive
                    ? Color.red
                    : (prominent ? Color.white : Color.primary)
            )
            .background(prominent ? Color.accentColor : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.22), lineWidth: prominent ? 0 : 1))
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.65 : 1))
    }
}

private struct OutlineRowHeightsKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, height in height })
    }
}

enum BookOutlinePresentation {
    case narrative
    case timeline
}

@MainActor
struct BookBackgroundView: View {
    let book: Book
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var profile: BookPlanningProfile?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let profile {
                BookBackgroundEditor(profile: profile, errorMessage: $errorMessage)
            } else {
                ProgressView("載入故事背景…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: book.id) { loadProfile() }
        .alert("故事背景無法儲存", isPresented: errorPresented) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadProfile() {
        do {
            profile = try planningStore.ensureProfile(bookID: book.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookBackgroundEditor: View {
    @Bindable var profile: BookPlanningProfile
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?
    @State private var content = StoryBackgroundContent()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("故事背景")
                .font(.headline)
            Text("記錄整本書共用的世界前提、核心方向與故事目的。這裡不會因大綱狀態而自動改變。")
                .font(.caption)
                .foregroundStyle(.secondary)
            backgroundField("世界／時代背景", text: binding(for: \StoryBackgroundContent.worldBackground))
            backgroundField("故事前提", text: binding(for: \StoryBackgroundContent.premise))
            backgroundField("主要衝突", text: binding(for: \StoryBackgroundContent.mainConflict))
            backgroundField("主角目標", text: binding(for: \StoryBackgroundContent.protagonistGoal))
            backgroundField("核心主題", text: binding(for: \StoryBackgroundContent.coreTheme))
            Text("其他背景")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: binding(for: \StoryBackgroundContent.otherBackground))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 180)
            HStack {
                Spacer()
                Button("儲存", systemImage: "square.and.arrow.down", action: save)
                    .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .onAppear { content = StoryBackgroundContent(storedValue: profile.backgroundText) }
    }

    private func backgroundField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 72)
        }
    }

    private func binding(for keyPath: WritableKeyPath<StoryBackgroundContent, String>) -> Binding<String> {
        Binding(
            get: { content[keyPath: keyPath] },
            set: {
                content[keyPath: keyPath] = $0
            }
        )
    }

    private func save() {
        do {
            profile.backgroundText = content.encodedValue()
            profile.updatedAt = Date()
            try planningStore.saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum BookPlanningWorkspaceTab: String, CaseIterable, Identifiable {
    case narrative = "敘事大綱"
    case timeline = "時間軸"

    var id: String { rawValue }
}

/// 整本書的寬版規劃入口。正文目錄由外層工作區隱藏，這裡只呈現
/// 敘事大綱與以書籍結構為基準的時間軸。
@MainActor
struct BookPlanningWorkspaceView: View {
    let book: Book
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    var onOpenTimelineSection: ((Section) -> Void)? = nil
    @State private var selectedTab: BookPlanningWorkspaceTab = .narrative

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("大綱工作區")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("大綱呈現", selection: $selectedTab) {
                    ForEach(BookPlanningWorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            switch selectedTab {
            case .narrative:
                NarrativeOutlineTimelineView(book: book, onOpenOutlineItem: onOpenOutlineItem)
            case .timeline:
                TimelinePanelView(
                    book: book,
                    allowsWideLayout: true,
                    onOpenSection: onOpenTimelineSection
                )
            }
        }
        .background(Color.appBackground)
    }
}

private enum OutlineStructureBoardMode {
    case narrative
    case timeline
}

@MainActor
private struct NarrativeOutlineTimelineView: View {
    let book: Book
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @State private var showingOutlineManager = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("正文順序與敘事節奏", systemImage: "rectangle.3.group")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("依故事線與階段閱讀標題順序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("管理故事線與階段", systemImage: "slider.horizontal.3") {
                    showingOutlineManager = true
                }
                .buttonStyle(PlanningActionStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            NarrativeOutlineListView(
                book: book,
                onOpenOutlineItem: onOpenOutlineItem
            )
        }
        .sheet(isPresented: $showingOutlineManager) {
            VStack(spacing: 0) {
                HStack {
                    Text("故事線與階段")
                        .font(.headline)
                    Spacer()
                    Button("完成") { showingOutlineManager = false }
                        .buttonStyle(PlanningActionStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                Divider()
                BookOutlineWorkspaceView(
                    book: book,
                    presentation: .narrative,
                    onOpenOutlineItem: { item, anchor in
                        showingOutlineManager = false
                        onOpenOutlineItem?(item, anchor)
                    }
                )
            }
            .frame(minWidth: 520, idealWidth: 620, minHeight: 560)
        }
    }
}

@MainActor
private struct NarrativeOutlineListView: View {
    let book: Book
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var collapsedStoryLines: Set<UUID> = []
    @State private var collapsedSections: Set<String> = []
    @State private var selectedItemID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        let projection = planningStore.narrativeOutlineList(book: book)
        let itemsByID = Dictionary(uniqueKeysWithValues: planningStore.items(bookID: book.id).map { ($0.id, $0) })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if projection.storyLines.isEmpty {
                    ContentUnavailableView(
                        "尚未建立故事線",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("使用上方「管理故事線與階段」建立第一條故事線。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(projection.storyLines) { storyLine in
                        storyLineSection(storyLine, itemsByID: itemsByID)
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: selectedItemBinding) { item in
            itemDetail(item)
                .frame(minWidth: 420, idealWidth: 520, minHeight: 480)
        }
        .alert("大綱無法儲存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var selectedItemBinding: Binding<OutlineItem?> {
        Binding(
            get: {
                guard let selectedItemID else { return nil }
                return planningStore.items(bookID: book.id).first { $0.id == selectedItemID }
            },
            set: { selectedItemID = $0?.id }
        )
    }

    private func storyLineSection(
        _ storyLine: NarrativeOutlineList.StoryLine,
        itemsByID: [UUID: OutlineItem]
    ) -> some View {
        let collapsed = collapsedStoryLines.contains(storyLine.id)
        return VStack(alignment: .leading, spacing: 8) {
            disclosureButton(
                title: storyLine.title.isEmpty ? storyLine.kind.rawValue : storyLine.title,
                collapsed: collapsed,
                count: storyLine.stages.flatMap(\.itemIDs).count + storyLine.unassignedItemIDs.count + storyLine.pendingItemIDs.count
            ) {
                toggleStoryLine(storyLine.id)
            }
            .font(.headline)

            if !collapsed {
                VStack(alignment: .leading, spacing: 8) {
                    if storyLine.kind == .main {
                        if !storyLine.unassignedItemIDs.isEmpty || storyLine.stages.isEmpty {
                            itemSection(
                                id: "\(storyLine.id):unassigned",
                                title: "未分階段",
                                itemIDs: storyLine.unassignedItemIDs,
                                itemsByID: itemsByID
                            )
                        }
                        ForEach(storyLine.stages) { stage in
                            itemSection(
                                id: "\(storyLine.id):\(stage.id)",
                                title: stage.title.isEmpty ? "未命名階段" : stage.title,
                                itemIDs: stage.itemIDs,
                                itemsByID: itemsByID
                            )
                        }
                    } else {
                        itemRows(storyLine.unassignedItemIDs, itemsByID: itemsByID)
                    }
                    if !storyLine.pendingItemIDs.isEmpty {
                        itemSection(
                            id: "\(storyLine.id):pending",
                            title: "待安置",
                            itemIDs: storyLine.pendingItemIDs,
                            itemsByID: itemsByID
                        )
                    }
                    if storyLine.stages.isEmpty && storyLine.unassignedItemIDs.isEmpty && storyLine.pendingItemIDs.isEmpty {
                        Text("尚無項目")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 32)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(14)
        .background(Color.workspacePanelBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.16)))
    }

    private func itemSection(
        id: String,
        title: String,
        itemIDs: [UUID],
        itemsByID: [UUID: OutlineItem]
    ) -> some View {
        let collapsed = collapsedSections.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            disclosureButton(title: title, collapsed: collapsed, count: itemIDs.count) {
                toggleSection(id)
            }
            .font(.subheadline.weight(.semibold))
            if !collapsed {
                if itemIDs.isEmpty {
                    Text("尚無項目").font(.callout).foregroundStyle(.secondary).padding(.leading, 28)
                } else {
                    itemRows(itemIDs, itemsByID: itemsByID)
                }
            }
        }
    }

    private func itemRows(_ itemIDs: [UUID], itemsByID: [UUID: OutlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(itemIDs, id: \.self) { itemID in
                if let item = itemsByID[itemID] {
                    Button { open(item) } label: {
                        HStack(spacing: 10) {
                            Text(item.title.isEmpty ? "未命名大綱項目" : item.title)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    .help(item.title.isEmpty ? "未命名大綱項目" : item.title)
                }
            }
        }
        .padding(.leading, 18)
    }

    private func disclosureButton(
        title: String,
        collapsed: Bool,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .frame(width: 12)
                Text(title)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(collapsed ? "展開" : "收合")\(title)")
    }

    private func open(_ item: OutlineItem) {
        let validSectionIDs = Set(BookStructure.orderedSections(in: book).map(\.id))
        if let anchor = planningStore.anchor(outlineItemID: item.id), validSectionIDs.contains(anchor.sectionID) {
            onOpenOutlineItem?(item, anchor)
        } else {
            selectedItemID = item.id
        }
    }

    private func itemDetail(_ item: OutlineItem) -> some View {
        let stages = planningStore.orderedStages(
            storyLineID: item.storyLineID,
            sections: BookStructure.orderedSections(in: book)
        )
        return VStack(spacing: 0) {
            HStack {
                Text("項目詳情").font(.headline)
                Spacer()
                Button("關閉", systemImage: "xmark") { selectedItemID = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(PlanningActionStyle())
            }
            .padding(12)
            Divider()
            ScrollView {
                OutlineItemEditor(
                    book: book,
                    item: item,
                    presentation: .narrative,
                    availableStages: stages,
                    onOpenOutlineItem: onOpenOutlineItem,
                    errorMessage: $errorMessage,
                    initiallyExpanded: true
                )
                .padding(12)
            }
        }
        .background(Color.workspacePanelBackground)
    }

    private func toggleStoryLine(_ id: UUID) {
        withAnimation(.snappy) {
            if collapsedStoryLines.contains(id) { collapsedStoryLines.remove(id) }
            else { collapsedStoryLines.insert(id) }
        }
    }

    private func toggleSection(_ id: String) {
        withAnimation(.snappy) {
            if collapsedSections.contains(id) { collapsedSections.remove(id) }
            else { collapsedSections.insert(id) }
        }
    }
}

@MainActor
private struct BookStructureTimelineView: View {
    let book: Book
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil

    var body: some View {
        OutlineStructureBoardView(
            book: book,
            mode: .timeline,
            onOpenOutlineItem: onOpenOutlineItem
        )
    }
}

@MainActor
private struct OutlineStructureBoardView: View {
    let book: Book
    let mode: OutlineStructureBoardMode
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var selectedItemID: UUID?
    @State private var errorMessage: String?
    @State private var narrativeRowHeights: [String: CGFloat] = [:]

    private let laneWidth: CGFloat = 160
    private let columnWidth: CGFloat = 220

    var body: some View {
        let layout = mode == .narrative
            ? planningStore.narrativeTimelineLayout(book: book)
            : planningStore.timelineLayout(book: book)
        let itemsByID = Dictionary(uniqueKeysWithValues: planningStore.items(bookID: book.id).map { ($0.id, $0) })
        let validSectionIDs = Set(layout.columns.map(\.sectionID))

        GeometryReader { proxy in
            if layout.lanes.isEmpty {
                ContentUnavailableView {
                    Label("尚未建立故事線", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                } description: {
                    Text("先在右側大綱建立主線、支線或其他故事線。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .narrative, let selectedItem {
                if proxy.size.width >= 900 {
                    HStack(spacing: 0) {
                        board(layout: layout, itemsByID: itemsByID, validSectionIDs: validSectionIDs)
                        Divider()
                        itemDetail(selectedItem)
                            .frame(width: 340)
                    }
                } else {
                    board(layout: layout, itemsByID: itemsByID, validSectionIDs: validSectionIDs)
                        .sheet(item: selectedItemBinding) { item in
                            itemDetail(item)
                                .frame(minWidth: 360, idealWidth: 420, minHeight: 480)
                        }
                }
            } else {
                board(layout: layout, itemsByID: itemsByID, validSectionIDs: validSectionIDs)
            }
        }
        .onChange(of: itemsByID.keys.sorted(by: { $0.uuidString < $1.uuidString })) { _, itemIDs in
            if let selectedItemID, !itemIDs.contains(selectedItemID) {
                self.selectedItemID = nil
            }
        }
        .alert("大綱無法儲存", isPresented: errorPresented) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var selectedItem: OutlineItem? {
        guard let selectedItemID else { return nil }
        return planningStore.items(bookID: book.id).first { $0.id == selectedItemID }
    }

    private var selectedItemBinding: Binding<OutlineItem?> {
        Binding(
            get: { selectedItem },
            set: { selectedItemID = $0?.id }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @ViewBuilder
    private func board(
        layout: OutlineTimelineLayout,
        itemsByID: [UUID: OutlineItem],
        validSectionIDs: Set<UUID>
    ) -> some View {
        if mode == .narrative {
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(["卷次", "節次", "幕標題"], id: \.self) { title in
                                Text(title).font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: narrativeRowHeights["header"] ?? 84)
                        ForEach(layout.lanes) { lane in
                            VStack(alignment: .leading, spacing: 0) {
                                if !lane.stageBands.isEmpty {
                                    Text("主線階段").font(.caption.weight(.semibold))
                                        .frame(height: 38)
                                }
                                Text(lane.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                Text(lane.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    .padding(.top, 3)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: narrativeRowHeights[lane.id.uuidString] ?? 114, alignment: .top)
                            .overlay(alignment: .bottom) { Divider() }
                        }
                        if layout.lanes.contains(where: { !$0.pendingItemIDs.isEmpty }) {
                            Text("待安置").font(.subheadline.weight(.semibold))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: narrativeRowHeights["pending"] ?? 100, alignment: .top)
                        }
                    }
                    .frame(width: laneWidth + 20)
                    .background(Color.workspacePanelBackground)
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            timelineHeader(columns: layout.columns)
                                .background(rowHeightReader("header"))
                            ForEach(layout.lanes) { lane in
                                timelineLane(lane, columns: layout.columns, itemsByID: itemsByID, validSectionIDs: validSectionIDs)
                                    .background(rowHeightReader(lane.id.uuidString))
                            }
                            pendingItems(lanes: layout.lanes, itemsByID: itemsByID, validSectionIDs: validSectionIDs)
                                .background(rowHeightReader("pending"))
                        }
                        .fixedSize(horizontal: true, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .onPreferenceChange(OutlineRowHeightsKey.self) { heights in
                if narrativeRowHeights != heights { narrativeRowHeights = heights }
            }
        } else {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                timelineHeader(columns: layout.columns)
                ForEach(layout.lanes) { lane in
                    timelineLane(
                        lane,
                        columns: layout.columns,
                        itemsByID: itemsByID,
                        validSectionIDs: validSectionIDs
                    )
                }
                pendingItems(
                    lanes: layout.lanes,
                    itemsByID: itemsByID,
                    validSectionIDs: validSectionIDs
                )
            }
            .padding(20)
        }
        }
    }

    // 只同步內容高度；水平捲動不寫入狀態，也不觸發大綱資料重新投影。
    private func rowHeightReader(_ id: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: OutlineRowHeightsKey.self, value: [id: geometry.size.height])
        }
    }

    private func itemDetail(_ item: OutlineItem) -> some View {
        let sections = BookStructure.orderedSections(in: book)
        let stages = planningStore.orderedStages(storyLineID: item.storyLineID, sections: sections)
        return VStack(spacing: 0) {
            HStack {
                Text("項目詳情")
                    .font(.headline)
                Spacer()
                Button("關閉", systemImage: "xmark") { selectedItemID = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(PlanningActionStyle())
                    .help("關閉項目詳情")
            }
            .padding(12)
            Divider()
            ScrollView {
                OutlineItemEditor(
                    book: book,
                    item: item,
                    presentation: .narrative,
                    availableStages: stages,
                    onOpenOutlineItem: onOpenOutlineItem,
                    errorMessage: $errorMessage,
                    initiallyExpanded: true
                )
                .padding(12)
            }
        }
        .background(Color.workspacePanelBackground)
    }

    @ViewBuilder
    private func timelineHeader(columns: [OutlineTimelineLayout.Column]) -> some View {
        if mode == .narrative, !columns.isEmpty {
            VStack(spacing: 0) {
                groupedHeaderRow(label: "卷次", groups: headerGroups(columns.map(\.volumeTitle)), emphasized: true)
                groupedHeaderRow(label: "節次", groups: headerGroups(columns.map(\.sectionTitle)), emphasized: false)
                groupedHeaderRow(label: "幕標題", groups: headerGroups(columns.map(\.headingTitle)), emphasized: false)
            }
        } else {
            HStack(spacing: 0) {
                if mode == .timeline { pinnedHeaderLabel("故事線") }
                if columns.isEmpty {
                    Text("尚未建立卷次與節次")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: columnWidth, alignment: .center)
                } else {
                    ForEach(columns) { column in
                        VStack(spacing: 2) {
                            Text(column.volumeTitle).font(.caption.weight(.semibold))
                            Text(column.sectionTitle).font(.caption2).foregroundStyle(.secondary)
                        }
                        .lineLimit(1).frame(width: columnWidth).padding(.vertical, 9)
                        .overlay(alignment: .leading) { Divider().frame(width: 1) }
                    }
                }
            }
        }
    }

    private func pinnedHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: laneWidth, alignment: .leading).padding(.horizontal, 10)
            .background(Color.workspacePanelBackground)
    }

    private func groupedHeaderRow(label: String, groups: [(title: String, count: Int)], emphasized: Bool) -> some View {
        HStack(spacing: 0) {
            if mode == .timeline { pinnedHeaderLabel(label) }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Text(group.title)
                    .font(emphasized ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: CGFloat(group.count) * columnWidth)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.06))
                    .overlay(alignment: .leading) { Divider().frame(width: 1) }
            }
        }
    }

    private func headerGroups(_ values: [String]) -> [(title: String, count: Int)] {
        values.reduce(into: []) { groups, value in
            if groups.last?.title == value { groups[groups.count - 1].count += 1 }
            else { groups.append((value, 1)) }
        }
    }

    private func timelineLane(
        _ lane: OutlineTimelineLayout.Lane,
        columns: [OutlineTimelineLayout.Column],
        itemsByID: [UUID: OutlineItem],
        validSectionIDs: Set<UUID>
    ) -> some View {
        VStack(spacing: 0) {
            if mode == .narrative, !lane.stageBands.isEmpty {
                stageBandRow(lane.stageBands, columns: columns)
            }
            HStack(alignment: .top, spacing: 0) {
                if mode == .timeline {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lane.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lane.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                .frame(width: laneWidth, alignment: .leading)
                .padding(10)
                .background(Color.workspacePanelBackground.opacity(0.98))
                .zIndex(1)
                }

                if columns.isEmpty {
                    Color.clear.frame(width: columnWidth, height: 76)
                } else {
                    ForEach(columns) { column in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(lane.entries.filter { $0.columnIndex == column.index }) { entry in
                                if let item = itemsByID[entry.itemID] {
                                    TimelineOutlineItemCard(
                                        item: item,
                                        validSectionIDs: validSectionIDs,
                                        isSelected: selectedItemID == item.id,
                                        onSelect: mode == .narrative ? { selectedItemID = item.id } : nil,
                                        onOpenOutlineItem: onOpenOutlineItem
                                    )
                                }
                            }
                        }
                        .padding(7)
                        .frame(width: columnWidth, alignment: .topLeading)
                        .frame(minHeight: 76, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(width: 1)
                        }
                    }
                }
            }
            .background(Color.workspacePanelBackground.opacity(0.65))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func stageBandRow(
        _ stageBands: [OutlineTimelineLayout.StageBand],
        columns: [OutlineTimelineLayout.Column]
    ) -> some View {
        HStack(spacing: 0) {
            if mode == .timeline {
            Label("主線階段", systemImage: "rectangle.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: laneWidth, alignment: .leading)
                .padding(.horizontal, 10)
                .background(Color.workspacePanelBackground.opacity(0.98))
                .zIndex(1)
            }

            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: CGFloat(columns.count) * columnWidth, height: 38)
                ForEach(stageBands) { stageBand in
                    Text(stageBand.title.isEmpty ? "未命名階段" : stageBand.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(
                            width: CGFloat(stageBand.endColumnIndex - stageBand.startColumnIndex + 1) * columnWidth - 6,
                            height: 28,
                            alignment: .leading
                        )
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: CGFloat(stageBand.startColumnIndex) * columnWidth + 3)
                }
            }
        }
        .background(Color.workspacePanelBackground.opacity(0.82))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func pendingItems(
        lanes: [OutlineTimelineLayout.Lane],
        itemsByID: [UUID: OutlineItem],
        validSectionIDs: Set<UUID>
    ) -> some View {
        let lanesWithPending = lanes.filter { !$0.pendingItemIDs.isEmpty }
        if !lanesWithPending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("待安置", systemImage: "tray")
                    .font(.subheadline.weight(.semibold))
                Text("下列項目沒有可用的卷次／節次位置，\(mode == .narrative ? "敘事大綱" : "時間軸")不會替作者猜測位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyHStack(alignment: .top, spacing: 8) {
                    ForEach(lanesWithPending) { lane in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lane.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(lane.pendingItemIDs, id: \.self) { itemID in
                                if let item = itemsByID[itemID] {
                                    TimelineOutlineItemCard(
                                        item: item,
                                        validSectionIDs: validSectionIDs,
                                        isSelected: selectedItemID == item.id,
                                        onSelect: mode == .narrative ? { selectedItemID = item.id } : nil,
                                        onOpenOutlineItem: onOpenOutlineItem
                                    )
                                        .frame(width: columnWidth - 20)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
            .padding(.top, 14)
        }
    }
}

@MainActor
private struct TimelineOutlineItemCard: View {
    let item: OutlineItem
    let validSectionIDs: Set<UUID>
    var isSelected = false
    var onSelect: (() -> Void)? = nil
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore

    var body: some View {
        Group {
            if let onSelect {
                Button(action: onSelect) { cardContent }
                    .buttonStyle(.plain)
                    .help("查看項目詳情")
            } else if let anchor = resolvedAnchor {
                Button { onOpenOutlineItem?(item, anchor) } label: { cardContent }
                    .buttonStyle(.plain)
                    .help("回到正文")
            } else {
                cardContent
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(statusDescription)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
            Text(locationDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if hasDeletedSource { return .orange }
        if resolvedAnchor != nil, item.status == .occurred { return .green }
        if planningStore.anchor(outlineItemID: item.id) == nil, item.status == .occurred { return .orange }
        return .accentColor
    }

    private var statusDescription: String {
        if planningStore.anchor(outlineItemID: item.id) == nil, item.status == .occurred {
            return "需要調整狀態"
        }
        return item.status.displayTitle
    }

    private var locationDescription: String {
        if resolvedAnchor != nil { return "正文來源" }
        if hasDeletedSource { return "來源已刪除" }
        guard let placement = planningStore.placement(outlineItemID: item.id) else { return "待安置" }
        switch placement.kind {
        case .pending: return "待安置"
        case .stageStart: return "幕首"
        case .stageEnd: return "幕末"
        case .afterItem:
            return placement.relativeItemTitleSnapshot.isEmpty
                ? "接在項目後"
                : "接在「\(placement.relativeItemTitleSnapshot)」後"
        }
    }

    private var resolvedAnchor: OutlineItemAnchor? {
        guard let anchor = planningStore.anchor(outlineItemID: item.id),
              validSectionIDs.contains(anchor.sectionID) else {
            return nil
        }
        return anchor
    }

    private var hasDeletedSource: Bool {
        planningStore.anchor(outlineItemID: item.id) != nil && resolvedAnchor == nil
    }
}

@MainActor
struct BookOutlineWorkspaceView: View {
    let book: Book
    let presentation: BookOutlinePresentation
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var selectedStoryLineID: UUID?
    @State private var deleteStoryLineTarget: OutlineStoryLine?
    @State private var errorMessage: String?

    private var storyLines: [OutlineStoryLine] {
        planningStore.storyLines(bookID: book.id)
    }

    private var selectedStoryLine: OutlineStoryLine? {
        storyLines.first { $0.id == selectedStoryLineID } ?? preferredStoryLine
    }

    var body: some View {
        VStack(spacing: 0) {
            storyLineToolbar
            Divider()
            if storyLines.isEmpty {
                emptyState
            } else if presentation == .timeline {
                TimelineStoryLinesView(
                    book: book,
                    storyLines: storyLines,
                    onOpenOutlineItem: onOpenOutlineItem,
                    errorMessage: $errorMessage
                )
            } else if let storyLine = selectedStoryLine {
                StoryLineContentView(
                    book: book,
                    storyLine: storyLine,
                    presentation: presentation,
                    isEmbedded: false,
                    onOpenOutlineItem: onOpenOutlineItem,
                    errorMessage: $errorMessage
                )
            }
        }
        .background(Color.workspacePanelBackground)
        .onAppear { selectFirstStoryLineIfNeeded() }
        .onChange(of: storyLines.map(\.id)) { _, _ in selectFirstStoryLineIfNeeded() }
        .alert("大綱無法儲存", isPresented: errorPresented) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
        .confirmationDialog("刪除故事線？", isPresented: Binding(get: { deleteStoryLineTarget != nil }, set: { if !$0 { deleteStoryLineTarget = nil } }), presenting: deleteStoryLineTarget) { storyLine in
            Button("刪除故事線", role: .destructive) { deleteStoryLine(storyLine) }
            Button("取消", role: .cancel) { deleteStoryLineTarget = nil }
        } message: { storyLine in
            let itemCount = planningStore.items(storyLineID: storyLine.id).count
            let stageCount = planningStore.stages(storyLineID: storyLine.id).count
            Text("將刪除「\(storyLine.title)」及其 \(stageCount) 個階段、\(itemCount) 個大綱項目與正文來源；正文不會被刪除。")
        }
    }

    private var storyLineToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if presentation == .narrative {
                Picker("故事線", selection: selectedStoryLineBinding) {
                    if storyLines.isEmpty {
                        Text("尚無故事線").tag(UUID?.none)
                    }
                    ForEach(storyLines) { storyLine in
                        Text("\(storyLine.kind.rawValue)｜\(storyLine.title)")
                            .tag(Optional(storyLine.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            } else {
                Label("故事線時間軸", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(OutlineStoryLineKind.allCases) { kind in
                        Button(kind.rawValue) { createStoryLine(kind) }
                            .disabled(kind == .main && hasMainStoryLine)
                    }
                } label: {
                    Label("新增故事線", systemImage: "plus")
                }
                .controlSize(.large)
                .help("新增故事線")

                if presentation == .narrative, let selectedStoryLine {
                    Button(role: .destructive) { deleteStoryLineTarget = selectedStoryLine } label: {
                        Label("刪除故事線", systemImage: "trash")
                    }
                    .buttonStyle(PlanningActionStyle())
                    .help("刪除故事線")
                }
            }
        }
        .buttonStyle(PlanningActionStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("尚未建立故事線", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        } description: {
            Text("先建立前傳、主線、支線或後記，再加入大綱項目。")
        } actions: {
            Menu("建立故事線", systemImage: "plus") {
                ForEach(OutlineStoryLineKind.allCases) { kind in
                    Button(kind.rawValue) { createStoryLine(kind) }
                }
            }
        }
    }

    private var selectedStoryLineBinding: Binding<UUID?> {
        Binding(
            get: { selectedStoryLine?.id },
            set: { selectedStoryLineID = $0 }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var hasMainStoryLine: Bool {
        storyLines.contains { $0.kind == .main }
    }

    private var preferredStoryLine: OutlineStoryLine? {
        storyLines.first { $0.kind == .main } ?? storyLines.first
    }

    private func selectFirstStoryLineIfNeeded() {
        guard !storyLines.isEmpty else {
            selectedStoryLineID = nil
            return
        }
        if !storyLines.contains(where: { $0.id == selectedStoryLineID }) {
            selectedStoryLineID = preferredStoryLine?.id
        }
    }

    private func createStoryLine(_ kind: OutlineStoryLineKind) {
        do {
            selectedStoryLineID = try planningStore.createStoryLine(bookID: book.id, kind: kind).id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteStoryLine(_ storyLine: OutlineStoryLine) {
        do {
            try planningStore.deleteStoryLine(storyLine)
            deleteStoryLineTarget = nil
            let remaining = planningStore.storyLines(bookID: book.id)
            selectedStoryLineID = remaining.first(where: { $0.kind == .main })?.id ?? remaining.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StoryLineContentView: View {
    let book: Book
    @Bindable var storyLine: OutlineStoryLine
    let presentation: BookOutlinePresentation
    let isEmbedded: Bool
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?
    @State private var showingStageStartSheet = false

    private var stages: [OutlineStage] { planningStore.orderedStages(storyLineID: storyLine.id, sections: sections) }
    private var sections: [Section] { BookStructure.orderedSections(in: book) }

    var body: some View {
        Group {
            if isEmbedded {
                storyLineContent
            } else {
                ScrollView {
                    storyLineContent
                }
            }
        }
    }

    private var storyLineContent: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            storyLineHeader

            if storyLine.kind == .main {
                mainStoryContent
            } else {
                itemList(orderedItems(stageID: nil), stage: nil)
            }
        }
        .padding(12)
        .sheet(isPresented: $showingStageStartSheet) {
            StageStartEditorSheet(book: book, storyLine: storyLine, errorMessage: $errorMessage)
        }
    }

    private var storyLineHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(storyLine.kind.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("故事線名稱", text: storyLineTitleBinding)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if storyLine.kind == .main {
                Button("新增主線階段", systemImage: "rectangle.stack.badge.plus") {
                    createStage()
                }
                .buttonStyle(PlanningActionStyle())
            }
        }
    }

    @ViewBuilder
    private var mainStoryContent: some View {
        if stages.isEmpty {
            UnassignedStageSectionView(
                book: book,
                storyLine: storyLine,
                presentation: presentation,
                allStages: [],
                items: orderedItems(stageID: nil),
                onOpenOutlineItem: onOpenOutlineItem,
                errorMessage: $errorMessage
            )
            Button("建立第一個階段", action: createStage)
                .buttonStyle(PlanningActionStyle(prominent: true))
        } else {
            ForEach(stages) { stage in
                StageSectionView(
                    book: book,
                    stage: stage,
                    storyLine: storyLine,
                    presentation: presentation,
                    allStages: stages,
                    items: orderedItems(stageID: stage.id),
                    onOpenOutlineItem: onOpenOutlineItem,
                    errorMessage: $errorMessage
                )
            }
            UnassignedStageSectionView(
                book: book,
                storyLine: storyLine,
                presentation: presentation,
                allStages: stages,
                items: orderedItems(stageID: nil),
                onOpenOutlineItem: onOpenOutlineItem,
                errorMessage: $errorMessage
            )
        }
    }

    @ViewBuilder
    private func itemList(_ displayedItems: [OutlineItem], stage: OutlineStage?) -> some View {
        ForEach(displayedItems) { item in
            OutlineItemEditor(
                book: book,
                item: item,
                presentation: presentation,
                availableStages: stages,
                onOpenOutlineItem: onOpenOutlineItem,
                errorMessage: $errorMessage
            )
        }
        Button("新增大綱項目", systemImage: "plus") {
            createItem(stage: stage)
        }
        .buttonStyle(PlanningActionStyle(prominent: true))
    }

    private var storyLineTitleBinding: Binding<String> {
        Binding(
            get: { storyLine.title },
            set: {
                storyLine.title = $0
                storyLine.updatedAt = Date()
            }
        )
    }

    private func createStage() {
        showingStageStartSheet = true
    }

    private func createItem(stage: OutlineStage? = nil) {
        do {
            let defaultStage = stage ?? (storyLine.kind == .main ? stages.last : nil)
            _ = try planningStore.createOutlineItem(storyLine: storyLine, stage: defaultStage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try planningStore.saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func orderedItems(stageID: UUID?) -> [OutlineItem] {
        planningStore.orderedItems(storyLineID: storyLine.id, stageID: stageID, sections: sections)
    }
}

/// 時間軸同時展開每條故事線，讓作者直接比較前傳、主線、支線與後記；
/// 各欄仍使用與敘事大綱相同的 `OutlineItem`，不建立第二份內容。
private struct TimelineStoryLinesView: View {
    let book: Book
    let storyLines: [OutlineStoryLine]
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Binding var errorMessage: String?

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(storyLines) { storyLine in
                    StoryLineContentView(
                        book: book,
                        storyLine: storyLine,
                        presentation: .timeline,
                        isEmbedded: true,
                        onOpenOutlineItem: onOpenOutlineItem,
                        errorMessage: $errorMessage
                    )
                    .frame(width: 300, alignment: .top)
                    .background(
                        Color.secondary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }
            .padding(12)
        }
    }
}

private struct StageStartEditorSheet: View {
    let book: Book
    let storyLine: OutlineStoryLine
    var stage: OutlineStage? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @Environment(\.dismiss) private var dismiss
    @Binding var errorMessage: String?
    @State private var title = ""
    @State private var selectedVolumeID: UUID?
    @State private var selectedSectionID: UUID?
    @State private var selectedHeadingOffset: Int?

    private var volumes: [Volume] { BookStructure.orderedVolumes(in: book) }
    private var sections: [Section] {
        guard let selectedVolumeID, let volume = volumes.first(where: { $0.id == selectedVolumeID }) else { return [] }
        return BookStructure.orderedSections(in: volume)
    }
    private var selectedSection: Section? { sections.first { $0.id == selectedSectionID } }
    private var headings: [(offset: Int, title: String)] {
        guard let selectedSection else { return [] }
        let attributed = NSAttributedString(selectedSection.content)
        let text = attributed.string as NSString
        var values: [(Int, String)] = []
        var offset = 0
        while offset < text.length {
            let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
            let title = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if !title.isEmpty, isSceneHeadingFont(font) { values.append((range.location, title)) }
            let next = NSMaxRange(range)
            if next <= offset { break }
            offset = next
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(stage == nil ? "建立主線階段" : "重新設定開始位置").font(.headline)
            if stage == nil { TextField("階段名稱", text: $title) }
            Picker("開始卷次", selection: volumeSelection) {
                Text("選擇卷次").tag(Optional<UUID>.none)
                ForEach(volumes) { volume in Text(volume.title.isEmpty ? "未命名卷次" : volume.title).tag(Optional(volume.id)) }
            }
            Picker("開始節次", selection: sectionSelection) {
                Text("停在卷次").tag(Optional<UUID>.none)
                ForEach(sections) { section in Text(section.title.isEmpty ? "未命名節次" : section.title).tag(Optional(section.id)) }
            }
            .disabled(selectedVolumeID == nil)
            Picker("開始幕標題", selection: $selectedHeadingOffset) {
                Text("停在節次").tag(Optional<Int>.none)
                ForEach(headings, id: \.offset) { heading in Text(heading.title).tag(Optional(heading.offset)) }
            }
            .disabled(selectedSectionID == nil)
            if volumes.isEmpty {
                Text("請先建立卷次，才能為主線設定開始位置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(PlanningActionStyle())
                Button(stage == nil ? "建立" : "儲存定位", action: create)
                    .buttonStyle(PlanningActionStyle(prominent: true))
                    .disabled(selectedVolumeID == nil)
            }
        }
        .padding(20).frame(width: 360)
        .onAppear(perform: loadExistingLocation)
    }

    private func create() {
        guard let volumeID = selectedVolumeID,
              let volume = volumes.first(where: { $0.id == volumeID }) else { return }
        let section = selectedSection
        let heading = headings.first { $0.offset == selectedHeadingOffset }
        do {
            let location = OutlineStageStartLocation(
                    volumeID: volumeID,
                    sectionID: section?.id,
                    volumeTitle: volume.title,
                    sectionTitle: section?.title ?? "",
                    headingText: heading?.title ?? "",
                    headingOffset: heading?.offset
            )
            if let stage {
                try planningStore.setStageStart(stage, to: location)
            } else {
                _ = try planningStore.createStage(storyLine: storyLine, title: title, start: location)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadExistingLocation() {
        guard let stage, let anchor = planningStore.stageStart(stageID: stage.id) else { return }
        selectedVolumeID = anchor.volumeID
        let detail = planningStore.stageStartDetail(stageID: stage.id)
        if detail?.granularity != .volume { selectedSectionID = anchor.sectionID }
        if detail?.granularity == .heading { selectedHeadingOffset = detail?.headingOffset }
    }

    private var volumeSelection: Binding<UUID?> {
        Binding(get: { selectedVolumeID }, set: {
            selectedVolumeID = $0
            selectedSectionID = nil
            selectedHeadingOffset = nil
        })
    }

    private var sectionSelection: Binding<UUID?> {
        Binding(get: { selectedSectionID }, set: {
            selectedSectionID = $0
            selectedHeadingOffset = nil
        })
    }
}

private struct StageSectionView: View {
    let book: Book
    @Bindable var stage: OutlineStage
    let storyLine: OutlineStoryLine
    let presentation: BookOutlinePresentation
    let allStages: [OutlineStage]
    let items: [OutlineItem]
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?
    @State private var isExpanded = false
    @State private var showingDeleteConfirmation = false
    @State private var showingStartEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "收合階段" : "展開階段")
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(.secondary)
                TextField("階段名稱", text: stageTitleBinding)
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                Spacer()
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("刪除階段", systemImage: "trash")
                }
                .buttonStyle(PlanningActionStyle())
                .help("刪除階段")
            }
            Text(stageStartDescription)
                .font(.caption)
                .foregroundStyle(stageStartIsMissing ? .red : .secondary)
            Button(stageStartIsMissing ? "設定開始位置" : "重新定位", systemImage: "mappin.and.ellipse") {
                showingStartEditor = true
            }
            .buttonStyle(PlanningActionStyle())
            if isExpanded {
                ForEach(items) { item in
                    OutlineItemEditor(
                        book: book,
                        item: item,
                        presentation: presentation,
                        availableStages: allStages,
                        onOpenOutlineItem: onOpenOutlineItem,
                        errorMessage: $errorMessage
                    )
                }
                Button("新增大綱項目", systemImage: "plus", action: createItem)
                    .buttonStyle(PlanningActionStyle(prominent: true))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showingStartEditor) {
            StageStartEditorSheet(book: book, storyLine: storyLine, stage: stage, errorMessage: $errorMessage)
        }
        .confirmationDialog("刪除階段？", isPresented: $showingDeleteConfirmation) {
            Button("刪除階段", role: .destructive, action: deleteStage)
            Button("取消", role: .cancel) { }
        } message: {
            Text("將刪除「\(stage.title)」及其中 \(items.count) 個大綱項目與正文標記；正文內容不會被刪除。")
        }
    }

    private var stageTitleBinding: Binding<String> {
        Binding(
            get: { stage.title },
            set: {
                stage.title = $0
                stage.updatedAt = Date()
            }
        )
    }

    private var stageStartIsMissing: Bool {
        guard let start = planningStore.stageStart(stageID: stage.id) else { return true }
        guard let volume = BookStructure.orderedVolumes(in: book).first(where: { $0.id == start.volumeID }) else { return true }
        let detail = planningStore.stageStartDetail(stageID: stage.id)
        if detail?.granularity == .volume { return false }
        guard let section = BookStructure.orderedSections(in: volume).first(where: { $0.id == start.sectionID }) else { return true }
        if detail?.granularity == .heading {
            let scenes = ProseStructureParser.scenes(in: section)
            return !scenes.contains { $0.title == detail?.headingTextSnapshot }
        }
        return false
    }

    private var stageStartDescription: String {
        guard let start = planningStore.stageStart(stageID: stage.id) else { return "需要設定開始位置" }
        let detail = planningStore.stageStartDetail(stageID: stage.id)
        let suffix = detail?.granularity == .heading ? " · \(detail?.headingTextSnapshot ?? "")" : ""
        if stageStartIsMissing { return "原定位：\(start.volumeTitleSnapshot)\(start.sectionTitleSnapshot.isEmpty ? "" : " · \(start.sectionTitleSnapshot)")\(suffix)（來源已刪除）" }
        let volume = BookStructure.orderedVolumes(in: book).first { $0.id == start.volumeID }
        if detail?.granularity == .volume { return "開始於：\(volume?.title ?? start.volumeTitleSnapshot)" }
        let section = volume.flatMap { BookStructure.orderedSections(in: $0).first { $0.id == start.sectionID } }
        return "開始於：\(volume?.title ?? start.volumeTitleSnapshot) · \(section?.title ?? start.sectionTitleSnapshot)\(suffix)"
    }

    private func save() {
        do {
            try planningStore.saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createItem() {
        do {
            _ = try planningStore.createOutlineItem(storyLine: storyLine, stage: stage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteStage() {
        do {
            try planningStore.deleteStage(stage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UnassignedStageSectionView: View {
    let book: Book
    let storyLine: OutlineStoryLine
    let presentation: BookOutlinePresentation
    let allStages: [OutlineStage]
    let items: [OutlineItem]
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isExpanded.toggle() } label: {
                Label("未分階段", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            if isExpanded {
                ForEach(items) { item in
                    OutlineItemEditor(book: book, item: item, presentation: presentation, availableStages: allStages, onOpenOutlineItem: onOpenOutlineItem, errorMessage: $errorMessage)
                }
                Button("新增大綱項目", systemImage: "plus", action: createItem)
                    .buttonStyle(PlanningActionStyle(prominent: true))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func createItem() {
        do {
            _ = try planningStore.createOutlineItem(storyLine: storyLine)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OutlineItemEditor: View {
    let book: Book
    @Bindable var item: OutlineItem
    let presentation: BookOutlinePresentation
    let availableStages: [OutlineStage]
    var onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var isExpanded: Bool

    init(
        book: Book,
        item: OutlineItem,
        presentation: BookOutlinePresentation,
        availableStages: [OutlineStage],
        onOpenOutlineItem: ((OutlineItem, OutlineItemAnchor) -> Void)? = nil,
        errorMessage: Binding<String?>,
        initiallyExpanded: Bool = false
    ) {
        self.book = book
        self.item = item
        self.presentation = presentation
        self.availableStages = availableStages
        self.onOpenOutlineItem = onOpenOutlineItem
        _errorMessage = errorMessage
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let source = sourceLocation
        HStack(alignment: .top, spacing: 8) {
            if presentation == .timeline {
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 2, height: 126)
                }
                .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(isExpanded: $isExpanded) {
                TextField("大綱標題", text: titleBinding)
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                TextField("內容（選填）", text: detailBinding, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)

                if let anchor = planningStore.anchor(outlineItemID: item.id), sourceIsAvailable {
                    Button("來源：回到正文", systemImage: "text.book.closed") {
                        onOpenOutlineItem?(item, anchor)
                    }
                    .buttonStyle(PlanningActionStyle())
                } else if planningStore.anchor(outlineItemID: item.id) != nil {
                    Label("來源已刪除", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if planningStore.anchor(outlineItemID: item.id) != nil {
                        Label("狀態：\(item.status.displayTitle)", systemImage: item.status == .occurred ? "checkmark.circle.fill" : "doc.text")
                            .foregroundStyle(summaryColor)
                            .font(.caption.weight(.semibold))
                    } else if item.status == .occurred {
                        Menu {
                            Button("改為草稿") { setLegacyManualStatus(.draft) }
                            Button("改為預定") { setLegacyManualStatus(.planned) }
                            Button("改為背景") { setLegacyManualStatus(.background) }
                        } label: {
                            Label("需要調整狀態", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    } else {
                        Picker("狀態", selection: manualStatusBinding) {
                            ForEach(OutlineItemStatus.allCases.filter { $0 != .occurred }) { status in
                                Text(status.displayTitle).tag(status)
                            }
                        }
                        .fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Label("卷：\(source.volume)", systemImage: "books.vertical")
                        Label("節：\(source.section)", systemImage: "text.book.closed")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !availableStages.isEmpty {
                        Menu {
                            Button("未分階段") { move(to: nil) }
                            ForEach(availableStages) { stage in
                                Button(stage.title) { move(to: stage) }
                            }
                        } label: {
                            Label("階段：\(currentStageTitle)", systemImage: "arrow.left.arrow.right")
                                .lineLimit(2)
                        }
                        .controlSize(.large)
                    }
                }

                if planningStore.anchor(outlineItemID: item.id) == nil {
                    Menu {
                        Button("待安置") { place(.pending) }
                        Button("放在本幕開頭") { place(.stageStart) }
                        Button("放在本幕結尾") { place(.stageEnd) }
                        if let placement = planningStore.placement(outlineItemID: item.id), placement.kind != .pending {
                            Divider()
                            Button("同位置向上移") { reorder(earlier: true) }
                            Button("同位置向下移") { reorder(earlier: false) }
                        }
                        Divider()
                        ForEach(availablePlacementTargets) { target in
                            Button("接在「\(target.title)」後") { place(.afterItem, after: target) }
                        }
                    } label: {
                        Label("位置：\(placementTitle)", systemImage: "arrowshape.turn.up.right")
                            .lineLimit(2)
                    }
                    .controlSize(.large)
                }

                HStack {
                    Spacer()
                    Button("儲存", systemImage: "square.and.arrow.down", action: save)
                    .buttonStyle(PlanningActionStyle(prominent: true))
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("刪除項目", systemImage: "trash")
                    }
                    .buttonStyle(PlanningActionStyle())
                    .help("刪除大綱項目")
                }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(summaryColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(summaryLocation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(summaryStatus).font(.caption.weight(.semibold)).foregroundStyle(summaryColor)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .confirmationDialog("刪除大綱項目？", isPresented: $showingDeleteConfirmation) {
            Button("刪除", role: .destructive, action: deleteItem)
            Button("取消", role: .cancel) { }
        } message: {
            Text("大綱項目與其正文來源會移除；正文不會被刪除。")
        }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { item.title }, set: { newValue in update { item.title = newValue } })
    }

    private var detailBinding: Binding<String> {
        Binding(get: { item.detail }, set: { newValue in update { item.detail = newValue } })
    }

    private var manualStatusBinding: Binding<OutlineItemStatus> {
        Binding(get: { item.status }, set: { newValue in
            do { try planningStore.setManualStatus(item, to: newValue) }
            catch { errorMessage = error.localizedDescription }
        })
    }

    private var currentStageTitle: String {
        availableStages.first(where: { $0.id == item.stageID })?.title ?? "未分階段"
    }

    private var summaryColor: Color {
        if planningStore.anchor(outlineItemID: item.id) != nil, !sourceIsAvailable { return .orange }
        if planningStore.anchor(outlineItemID: item.id) != nil { return item.status == .occurred ? .green : .accentColor }
        return item.status == .occurred ? .orange : .accentColor
    }

    private var summaryStatus: String {
        if planningStore.anchor(outlineItemID: item.id) != nil { return item.status.displayTitle }
        return item.status == .occurred ? "需要調整" : item.status.displayTitle
    }

    private var summaryLocation: String {
        if planningStore.anchor(outlineItemID: item.id) != nil {
            return sourceIsAvailable
                ? "正文：\(sourceLocation.volume) · \(sourceLocation.section)"
                : "正文來源已刪除"
        }
        return "安置：\(placementTitle)"
    }

    private var sourceIsAvailable: Bool {
        guard let anchor = planningStore.anchor(outlineItemID: item.id) else { return false }
        return BookStructure.orderedSections(in: book).contains { $0.id == anchor.sectionID }
    }

    private var availablePlacementTargets: [OutlineItem] {
        planningStore.items(storyLineID: item.storyLineID)
            .filter { $0.stageID == item.stageID && $0.id != item.id }
    }

    private var placementTitle: String {
        guard let placement = planningStore.placement(outlineItemID: item.id) else { return "待安置" }
        switch placement.kind {
        case .pending: return placement.relativeItemTitleSnapshot.isEmpty ? "待安置" : "原安置位置已失效，請重新安置"
        case .stageStart: return "幕首"
        case .stageEnd: return "幕末"
        case .afterItem:
            guard let target = availablePlacementTargets.first(where: { $0.id == placement.relativeItemID }) else {
                return "原安置位置已失效，請重新安置"
            }
            return "接在「\(target.title)」後"
        }
    }

    private var sourceLocation: OutlineItemSourceLocation {
        guard let anchor = planningStore.anchor(outlineItemID: item.id) else { return .missing }

        for volume in BookStructure.orderedVolumes(in: book) {
            guard let section = BookStructure.orderedSections(in: volume).first(where: { $0.id == anchor.sectionID }) else {
                continue
            }
            let volumeTitle = volume.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let sectionTitle = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return OutlineItemSourceLocation(
                volume: volumeTitle.isEmpty ? "從缺" : volumeTitle,
                section: sectionTitle.isEmpty ? "從缺" : sectionTitle
            )
        }
        return .missing
    }

    private func update(_ change: () -> Void) {
        change()
        item.updatedAt = Date()
    }

    private func save() {
        do {
            try planningStore.saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem() {
        do {
            try planningStore.deleteOutlineItem(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(to stage: OutlineStage?) {
        do {
            try planningStore.moveOutlineItem(item, to: stage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func place(_ kind: OutlineItemPlacementKind, after target: OutlineItem? = nil) {
        do { try planningStore.setPlacement(item, kind: kind, after: target) }
        catch { errorMessage = error.localizedDescription }
    }

    private func setLegacyManualStatus(_ status: OutlineItemStatus) {
        do { try planningStore.setManualStatus(item, to: status) }
        catch { errorMessage = error.localizedDescription }
    }

    private func reorder(earlier: Bool) {
        do { try planningStore.moveManualItem(item, earlier: earlier) }
        catch { errorMessage = error.localizedDescription }
    }

}

private struct OutlineItemSourceLocation {
    let volume: String
    let section: String

    static let missing = OutlineItemSourceLocation(volume: "從缺", section: "從缺")
}
