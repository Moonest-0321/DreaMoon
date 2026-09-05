import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private final class EditorKeyboardMonitor {
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.option) else { return event }
            if event.keyCode == 123 {
                NotificationCenter.default.post(name: .sailunePreviousSection, object: nil)
                return nil
            }
            if event.keyCode == 124 {
                NotificationCenter.default.post(name: .sailuneNextSection, object: nil)
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

// MARK: - 三欄式編輯工作區 (PRD 3.3)
struct EditorWorkspaceView: View {
    let book: Book
    @State private var selectedSection: Section?
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var bridge = EditorBridge()
    @State private var showingCommandPalette = false
    @State private var showingShortcutHelp = false
    @State private var keyboardMonitor = EditorKeyboardMonitor()
    @State private var focusedCharacter: Character?
    @State private var characterFocusRequestID = UUID()
    @State private var isShowingPlanningWorkspace = false
    @State private var writingColumnVisibility: NavigationSplitViewVisibility = .automatic

    private var neighboringSections: (previous: Section?, next: Section?) {
        let sections = BookStructure.orderedSections(in: book)
        guard let selectedSection,
              let index = sections.firstIndex(where: { $0.id == selectedSection.id }) else {
            return (nil, nil)
        }
        return (
            index > 0 ? sections[index - 1] : nil,
            index + 1 < sections.count ? sections[index + 1] : nil
        )
    }

    init(book: Book, initialSection: Section) {
        self.book = book
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        Group {
            if isShowingPlanningWorkspace {
                BookPlanningWorkspaceView(
                    book: book,
                    onReturnToWriting: returnToWriting,
                    onOpenOutlineItem: openOutlineItem
                )
                .toolbar { workspaceToolbar }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    EditorSidebarView(book: book, selectedSection: $selectedSection, bridge: bridge)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                } detail: {
                    EditorCenterView(section: selectedSection, bridge: bridge, book: book) { character in
                        focusedCharacter = character
                        characterFocusRequestID = UUID()
                        setInspectorPresented(true)
                    }
                    .toolbar { workspaceToolbar }
                }
            }
        }
        .navigationTitle("")
        .inspector(isPresented: $showInspector) {
            WorkspaceInspectorView(
                book: book,
                currentSection: selectedSection,
                focusedCharacter: focusedCharacter,
                focusRequestID: characterFocusRequestID,
                onSelectSection: { section in
                    bridge.flushPendingSave()
                    selectedSection = section
                },
                onOpenStoryTag: { tag in
                    guard let section = BookStructure.orderedSections(in: book).first(where: { $0.id == tag.sectionID }) else { return }
                    bridge.flushPendingSave()
                    let offset = tag.resolvedOffset(in: String(section.content.characters))
                    bridge.requestSelect(sectionID: section.id, range: NSRange(location: offset, length: 0))
                    selectedSection = section
                },
                onOpenOutlineItem: openOutlineItem
            )
            .workspaceFloatingPanel()
            .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .sheet(isPresented: $showingCommandPalette) {
            CommandPaletteView { command in
                showingCommandPalette = false
                perform(command)
            }
        }
        .sheet(isPresented: $showingShortcutHelp) {
            ShortcutHelpView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sailunePreviousSection)) { _ in
            if !isShowingPlanningWorkspace { navigate(to: neighboringSections.previous) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sailuneNextSection)) { _ in
            if !isShowingPlanningWorkspace { navigate(to: neighboringSections.next) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sailunePlanningMarkersChanged)) { _ in
            bridge.reloadVisibleContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sailuneWillChangeCharacterReferences)) { _ in
            // 名稱同步會直接改寫 Section.content；先提交作者正在輸入的內容，
            // 避免背景同步以較舊的模型內容覆蓋編輯器。
            bridge.flushPendingSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sailuneCharacterReferencesChanged)) { notification in
            guard let sectionIDs = notification.object as? Set<UUID>,
                  let selectedSection,
                  sectionIDs.contains(selectedSection.id) else { return }
            bridge.reloadVisibleContent()
        }
        .onAppear { keyboardMonitor.start() }
        .onDisappear { keyboardMonitor.stop() }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showingCommandPalette = true } label: { Label("指令", systemImage: "command") }
                .help("開啟指令面板 (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            Menu {
                Button { showingCommandPalette = true } label: { Label("指令面板", systemImage: "command") }
                Button {
                    if let section = selectedSection {
                        let content = ExportManager.exportSectionToTXT(section: section)
                        ExportManager.presentSavePanel(for: book, defaultName: section.title, fileType: "txt", content: content)
                    } else {
                        let content = ExportManager.exportBookToTXT(book: book)
                        ExportManager.presentSavePanel(for: book, defaultName: book.title, fileType: "txt", content: content)
                    }
                } label: { Label("匯出 TXT", systemImage: "doc.text") }
                Button { EpubExporter.exportBook(book: book) } label: { Label("匯出 EPUB", systemImage: "book.closed") }
            } label: { Label("更多", systemImage: "ellipsis.circle") }
            Button { setInspectorPresented(!showInspector) } label: {
                Label("設定集", systemImage: "sidebar.right")
            }
            .help("顯示/隱藏右欄設定集")
            Button(action: showPlanningWorkspace) {
                Label("大綱", systemImage: "rectangle.3.group")
            }
            .disabled(isShowingPlanningWorkspace)
            .help("開啟大綱工作區")
            Button { showingShortcutHelp = true } label: {
                Label("快捷鍵", systemImage: "keyboard")
            }
            .help("開啟快捷鍵說明")
        }
    }

    private func toggleSidebar() {
        columnVisibility = (columnVisibility == .detailOnly) ? .automatic : .detailOnly
    }

    private func showPlanningWorkspace() {
        bridge.flushPendingSave()
        writingColumnVisibility = columnVisibility
        columnVisibility = .detailOnly
        setInspectorPresented(false)
        isShowingPlanningWorkspace = true
    }

    private func returnToWriting() {
        isShowingPlanningWorkspace = false
        columnVisibility = writingColumnVisibility
    }

    private func openOutlineItem(_ item: OutlineItem, _ anchor: OutlineItemAnchor) {
        guard let section = BookStructure.orderedSections(in: book).first(where: { $0.id == anchor.sectionID }) else { return }
        let offset = anchor.resolvedOffset(in: String(section.content.characters))
        isShowingPlanningWorkspace = false
        columnVisibility = writingColumnVisibility
        selectedSection = section
        DispatchQueue.main.async {
            bridge.requestSelect(sectionID: section.id, range: NSRange(location: offset, length: 0))
        }
    }

    private func perform(_ command: PaletteCommand) {
        switch command {
        case .toggleOutline:
            if !isShowingPlanningWorkspace { toggleSidebar() }
        case .toggleInspector: setInspectorPresented(!showInspector)
        case .previousSection:
            if !isShowingPlanningWorkspace { navigate(to: neighboringSections.previous) }
        case .nextSection:
            if !isShowingPlanningWorkspace { navigate(to: neighboringSections.next) }
        case .toggleSceneHeading: bridge.requestToggleHeading()
        case .showShortcuts: showingShortcutHelp = true
        }
    }

    private func navigate(to section: Section?) {
        guard let section else { return }
        bridge.flushPendingSave()
        selectedSection = section
    }

    private func setInspectorPresented(_ presented: Bool) {
        // AppKit 的 inspector 展開會對中央 NSTextView 執行 live resize。
        // 先結束文字輸入並關閉動畫，避免文字配置與分欄動畫互相觸發重排。
        NSApp.keyWindow?.makeFirstResponder(nil)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            showInspector = presented
        }
    }
}

private enum PaletteCommand: String, CaseIterable, Identifiable {
    case toggleOutline = "顯示／隱藏目錄"
    case toggleInspector = "顯示／隱藏設定集"
    case previousSection = "上一節"
    case nextSection = "下一節"
    case toggleSceneHeading = "切換幕標題"
    case showShortcuts = "開啟快捷鍵說明"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .toggleOutline: return "sidebar.left"
        case .toggleInspector: return "sidebar.right"
        case .previousSection: return "chevron.left"
        case .nextSection: return "chevron.right"
        case .toggleSceneHeading: return "textformat.size"
        case .showShortcuts: return "keyboard"
        }
    }
    var shortcut: String {
        switch self {
        case .toggleOutline: return ""
        case .toggleInspector: return ""
        case .previousSection: return "⌥←"
        case .nextSection: return "⌥→"
        case .toggleSceneHeading: return "⌘2"
        case .showShortcuts: return ""
        }
    }
}

private struct CommandPaletteView: View {
    let onPerform: (PaletteCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var commands: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(PaletteCommand.allCases) }
        return PaletteCommand.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("輸入指令…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(14)
            Divider()
            List(commands) { command in
                Button {
                    onPerform(command)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: command.icon).frame(width: 20)
                        Text(command.rawValue)
                        Spacer()
                        if !command.shortcut.isEmpty {
                            Text(command.shortcut).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
            }
            .listStyle(.plain)
        }
        .frame(width: 420, height: 360)
        .onAppear { searchFocused = true }
    }
}

private struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("快捷鍵").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
            }
            Divider()
            shortcut("⌘K", "開啟指令面板")
            shortcut("⌘2", "切換幕標題／內文")
            shortcut("⌘↩", "開啟反白角色資料")
            shortcut("⌥←", "上一節")
            shortcut("⌥→", "下一節")
            Spacer()
        }
        .padding(24)
        .frame(width: 360, height: 260)
    }

    private func shortcut(_ key: String, _ title: String) -> some View {
        HStack {
            Text(key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            Text(title)
        }
    }
}

// MARK: - 左欄：目錄
struct EditorSidebarView: View {
    let book: Book
    @Binding var selectedSection: Section?
    let bridge: EditorBridge
    @Environment(\.modelContext) private var modelContext
    @Environment(StoryPlanningStore.self) private var planningStore

    @State private var draggingKind: DragKind? = nil
    @State private var dropTargetSectionID: UUID? = nil
    @State private var dropTargetSectionEndVolumeID: UUID? = nil
    @State private var collapsedVolumeIDs: Set<UUID> = []
    @State private var renamingID: UUID? = nil
    @State private var renameBuffer: String = ""
    @FocusState private var renameFocused: Bool
    @State private var deleteTarget: DeleteTarget? = nil
    @State private var undoTarget: DeleteTarget? = nil

    var body: some View {
        VStack(spacing: 0) {
            // MARK: 頂部全域操作按鈕
            HStack(spacing: 12) {
                Button(action: addVolume) {
                    Label("新增卷", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("新增卷")
                Button(action: addSection) {
                    Label("新增節", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("新增節")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.workspacePanelBackground)
            Divider()
            List {
                ForEach(book.volumes.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { volume in
                    volumeRow(for: volume)
                    if !collapsedVolumeIDs.contains(volume.id) {
                        if volume.sections.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("這一卷還沒有節").font(.caption).foregroundStyle(.secondary)
                                Button("新增第一節", systemImage: "plus") { addSection(to: volume) }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(.leading, 38).padding(.vertical, 8)
                        } else {
                            ForEach(volume.sections.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { section in
                                sectionRow(for: section, in: volume)
                            }
                        }
                        if draggingSectionInSameVolume(volume.id) { sectionEndZone(for: volume) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.workspacePanelBackground)
        }
        .background(Color.workspacePanelBackground)
        .alert("確認刪除",
               isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
               presenting: deleteTarget) { target in
            Button("取消", role: .cancel) { }
            Button("刪除", role: .destructive) { performDelete(target) }
        } message: { target in
            switch target {
            case .volume(let v): Text("確定要刪除卷「\(v.title)」嗎？其下所有節將一併刪除，且無法復原。")
            case .section(let s): Text("確定要刪除節「\(s.title)」嗎？此操作無法復原。")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let undoTarget {
                HStack(spacing: 12) {
                    Text(deleteSummary(undoTarget))
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("復原") { restore(undoTarget) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func sectionIndex(for section: Section, in book: Book) -> Int {
        guard let volume = section.volume else { return 1 }
        let sortedSections = volume.sections.sorted { $0.sortOrder < $1.sortOrder }
        if let index = sortedSections.firstIndex(where: { $0.id == section.id }) {
            return index + 1
        }
        return 1
    }

    // MARK: 卷的列 (包含新增的 + 按鈕)
    @ViewBuilder
    private func volumeRow(for volume: Volume) -> some View {
        HStack(spacing: 6) {
            Image(systemName: collapsedVolumeIDs.contains(volume.id) ? "chevron.right" : "chevron.down")
                .font(.caption).foregroundStyle(.secondary).frame(width: 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    commitCurrentRename()
                    toggleVolume(volume.id)
                }
            if renamingID == volume.id {
                renameEditor(commit: { newName in volume.title = newName.isEmpty ? volume.title : newName })
            } else {
                Text(volume.title).lineLimit(1).fontWeight(.semibold)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { startRenaming(id: volume.id, currentName: volume.title) }
            }
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    commitCurrentRename()
                    toggleVolume(volume.id)
                }
            // 【新增】每個卷後面的 + 按鈕
            Button(action: {
                commitCurrentRename()
                addSection(to: volume)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain) // 使用 plain 避免破壞 List 的選取背景色
                .help("在此卷新增節")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button { addSection(to: volume) } label: { Label("新增節", systemImage: "doc.badge.plus") }
            Divider()
            Button(role: .destructive) { deleteTarget = .volume(volume) } label: { Label("刪除卷", systemImage: "trash") }
        }
    }

    // MARK: 節的列
    @ViewBuilder
    private func sectionRow(for section: Section, in volume: Volume) -> some View {
        let index = sectionIndex(for: section, in: book)
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                .frame(width: 24, height: 22).contentShape(Rectangle())
                .onDrag {
                    clearDragState()
                    draggingKind = .section(section.id, volumeID: volume.id)
                    return NSItemProvider(object: NSString(string: section.id.uuidString))
                }
            Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 14)
                .onTapGesture {
                    commitCurrentRename()
                    selectedSection = section
                }
            if renamingID == section.id {
                renameEditor(commit: { newName in section.title = newName.isEmpty ? section.title : newName })
            } else {
                HStack(spacing: 0) {
                    Text("\(index)｜")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            commitCurrentRename()
                            selectedSection = section
                        }
                    Text(section.title).lineLimit(1)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { startRenaming(id: section.id, currentName: section.title) }
                    if let annotation = planningStore.annotation(sectionID: section.id),
                       !annotation.plannedOutline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Circle().fill(.green.opacity(0.5)).frame(width: 5, height: 5)
                    }
                    if let annotation = planningStore.annotation(sectionID: section.id),
                       !annotation.revisionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Circle().fill(.orange.opacity(0.6)).frame(width: 5, height: 5)
                    }
                }
            }
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    commitCurrentRename()
                    selectedSection = section
                }
        }
        .padding(.leading, 8).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(
            targetID: section.id, targetVolumeID: volume.id, draggingKind: $draggingKind, highlightID: $dropTargetSectionID,
            onMove: { draggedID in moveSection(in: volume, draggedID: draggedID, before: section.id) }
        ))
        .listRowBackground(selectedSection?.id == section.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(alignment: .top) { DropIndicator(active: dropTargetSectionID == section.id) }
        .contextMenu {
            Button { startRenaming(id: section.id, currentName: section.title) } label: { Label("重新命名", systemImage: "pencil") }
            Button {
                commitCurrentRename()
                addSection(to: volume)
            } label: { Label("新增節", systemImage: "doc.badge.plus") }
            Divider()
            Button(role: .destructive) { deleteTarget = .section(section) } label: { Label("刪除節", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func sectionEndZone(for volume: Volume) -> some View {
        DropEndZone(active: dropTargetSectionEndVolumeID == volume.id, label: "放到本卷末尾")
            .onDrop(of: [UTType.plainText], delegate: SectionEndDropDelegate(
                targetVolumeID: volume.id, draggingKind: $draggingKind, highlightVolumeID: $dropTargetSectionEndVolumeID,
                onMoveToEnd: { draggedID in moveSectionToEnd(in: volume, draggedID: draggedID) }
            ))
    }

    @ViewBuilder
    private func renameEditor(commit: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Text(renameBuffer.isEmpty ? "名稱" : renameBuffer)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 12)
                    .opacity(0)
                TextField("", text: $renameBuffer)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFocused)
                    .submitLabel(.done)
                    .onAppear { renameFocused = true }
                    .onSubmit { commitAndClose(commit: commit) }
            }
            .frame(minWidth: 60)
            Button { commitAndClose(commit: commit) } label: { Image(systemName: "checkmark").foregroundStyle(.green) }
                .buttonStyle(.borderless).help("確認 (Enter)")
            Button { cancelRenaming() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                .buttonStyle(.borderless).help("取消")
        }
        .onChange(of: renameFocused) { _, focused in if !focused { commitAndClose(commit: commit) } }
    }

    private func startRenaming(id: UUID, currentName: String) {
        commitCurrentRename()
        renameBuffer = currentName
        renamingID = id
    }
    private func commitCurrentRename() {
        guard let id = renamingID else { return }
        if let volume = book.volumes.first(where: { $0.id == id }) {
            volume.title = renameBuffer.isEmpty ? volume.title : renameBuffer
        } else if let section = book.volumes.flatMap(\.sections).first(where: { $0.id == id }) {
            section.title = renameBuffer.isEmpty ? section.title : renameBuffer
        }
        renamingID = nil
        renameFocused = false
    }
    private func commitAndClose(commit: (String) -> Void) { commit(renameBuffer); renamingID = nil; renameFocused = false }
    private func cancelRenaming() { renamingID = nil; renameFocused = false }
    private func toggleVolume(_ id: UUID) {
        if collapsedVolumeIDs.contains(id) { collapsedVolumeIDs.remove(id) } else { collapsedVolumeIDs.insert(id) }
    }

    // MARK: 新增邏輯
    private func addVolume() {
        let next = (book.volumes.map(\.sortOrder).max() ?? -1) + 1
        // ⚠️ 若您的 Volume 初始化需要傳入 book，請改為: Volume(title: "新卷", sortOrder: next, book: book)
        let newVolume = Volume(title: "新卷", sortOrder: next)
        book.volumes.append(newVolume)
    }
    private func addSection() {
        let targetVolume: Volume
        if let currentVolume = selectedSection?.volume {
            targetVolume = currentVolume
        } else if let firstVolume = book.volumes.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
            targetVolume = firstVolume
        } else {
            let newVolume = Volume(title: "第一卷", sortOrder: 0)
            book.volumes.append(newVolume)
            targetVolume = newVolume
        }
        addSection(to: targetVolume)
    }
    private func addSection(to volume: Volume) {
        let next = (volume.sections.map(\.sortOrder).max() ?? -1) + 1
        let newSection = Section(title: "新節", sortOrder: next, volume: volume)
        volume.sections.append(newSection)
        bridge.flushPendingSave()
        selectedSection = newSection // 自動選取並跳轉至中欄編輯
    }

    // MARK: 拖曳重排
    private func moveSection(in targetVolume: Volume, draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var sections = targetVolume.sections.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = sections.firstIndex(where: { $0.id == draggedID }) else { return }
        let item = sections.remove(at: from)
        guard let to = sections.firstIndex(where: { $0.id == targetID }) else { return }
        sections.insert(item, at: to)
        for (index, section) in sections.enumerated() { section.sortOrder = index }
    }
    private func moveSectionToEnd(in targetVolume: Volume, draggedID: UUID) {
        var sections = targetVolume.sections.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = sections.firstIndex(where: { $0.id == draggedID }) else { return }
        let item = sections.remove(at: from); sections.append(item)
        for (index, section) in sections.enumerated() { section.sortOrder = index }
    }

    // MARK: 拖曳狀態
    private func clearDragState() {
        draggingKind = nil; dropTargetSectionID = nil; dropTargetSectionEndVolumeID = nil
    }
    private func draggingSectionInSameVolume(_ vid: UUID) -> Bool {
        if case .section(_, let v) = draggingKind, v == vid { return true }; return false
    }

    // MARK: 刪除與 Fallback
    private func performDelete(_ target: DeleteTarget) {
        undoTarget = target
        switch target {
        case .volume(let v):
            if selectedSection?.volume?.id == v.id {
                selectedSection = findFallbackSectionForDeletedVolume(v, in: book)
            }
            modelContext.delete(v)
        case .section(let s):
            if selectedSection?.id == s.id {
                selectedSection = findFallbackSection(for: s, in: book)
            }
            modelContext.delete(s)
        }
        deleteTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if undoTarget?.id == target.id { undoTarget = nil }
        }
    }

    private func deleteSummary(_ target: DeleteTarget) -> String {
        switch target {
        case .volume(let volume): return "已刪除卷「\(volume.title)」"
        case .section(let section): return "已刪除節「\(section.title)」"
        }
    }

    private func restore(_ target: DeleteTarget) {
        switch target {
        case .volume(let volume):
            if !book.volumes.contains(where: { $0.id == volume.id }) {
                volume.book = book
                book.volumes.append(volume)
            }
            modelContext.insert(volume)
        case .section(let section):
            guard let volume = section.volume else { return }
            if !volume.sections.contains(where: { $0.id == section.id }) {
                volume.sections.append(section)
            }
            modelContext.insert(section)
            selectedSection = section
        }
        try? modelContext.save()
        undoTarget = nil
    }
    private func findFallbackSection(for deletedSection: Section, in book: Book) -> Section? {
        let sortedVolumes = book.volumes.sorted { $0.sortOrder < $1.sortOrder }
        guard let currentVolume = deletedSection.volume else { return nil }
        let sortedSections = currentVolume.sections.sorted { $0.sortOrder < $1.sortOrder }
        if let idx = sortedSections.firstIndex(where: { $0.id == deletedSection.id }) {
            if idx > 0 { return sortedSections[idx - 1] }
            if idx < sortedSections.count - 1 { return sortedSections[idx + 1] }
        }
        if let volIdx = sortedVolumes.firstIndex(where: { $0.id == currentVolume.id }) {
            for i in (0..<volIdx).reversed() {
                let prevSections = sortedVolumes[i].sections.sorted { $0.sortOrder < $1.sortOrder }
                if let last = prevSections.last { return last }
            }
            for i in (volIdx + 1)..<sortedVolumes.count {
                let nextSections = sortedVolumes[i].sections.sorted { $0.sortOrder < $1.sortOrder }
                if let first = nextSections.first { return first }
            }
        }
        return nil
    }
    private func findFallbackSectionForDeletedVolume(_ deletedVolume: Volume, in book: Book) -> Section? {
        let sortedVolumes = book.volumes.sorted { $0.sortOrder < $1.sortOrder }
        guard let volIdx = sortedVolumes.firstIndex(where: { $0.id == deletedVolume.id }) else { return nil }
        for i in (0..<volIdx).reversed() {
            let prevSections = sortedVolumes[i].sections.sorted { $0.sortOrder < $1.sortOrder }
            if let last = prevSections.last { return last }
        }
        for i in (volIdx + 1)..<sortedVolumes.count {
            let nextSections = sortedVolumes[i].sections.sorted { $0.sortOrder < $1.sortOrder }
            if let first = nextSections.first { return first }
        }
        return nil
    }
}

// MARK: - 中欄：真編輯器
struct EditorCenterView: View {
    let section: Section?
    let bridge: EditorBridge
    let book: Book
    let onOpenCharacter: (Character) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var liveWordCount: Int = 0
    @State private var cursorIsHeading: Bool = false
    @State private var saveState: EditorSaveState = .saved
    @State private var isContentLoading = false
    @State private var selectedText = ""
    @AppStorage("sailune.hasShownInlineAutosaveHint") private var hasShownInlineAutosaveHint = false
    @AppStorage("sailune.showCharacterSelectionInfo") private var showCharacterSelectionInfo = true
    @State private var showingInlineAutosaveHint = false
    @State private var activeAnnotation: ChapterAnnotation?
    @FocusState private var titleFieldFocused: Bool
    @Query(sort: \Character.sortOrder) private var allCharacters: [Character]
    @Query(sort: \CharacterAlias.createdAt) private var allAliases: [CharacterAlias]

    private var selectedCharacterMatch: Character? {
        characterMatch(for: selectedText)
    }

    private func characterMatch(for text: String) -> Character? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var matchesByID: [UUID: Character] = [:]
        for character in allCharacters where
            character.book?.id == book.id &&
            character.realName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            matchesByID[character.id] = character
        }
        for alias in allAliases where
            alias.character?.book?.id == book.id &&
            alias.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            if let character = alias.character { matchesByID[character.id] = character }
        }
        guard matchesByID.count == 1 else { return nil }
        return matchesByID.values.first
    }

    private func characterReference(from text: String) -> CharacterReference? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("\n") else { return nil }
        let canonicalMatches = allCharacters.filter {
            $0.book?.id == book.id &&
            $0.realName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let aliasMatches = allAliases.filter {
            $0.character?.book?.id == book.id &&
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let matchedCharacterIDs = Set(canonicalMatches.map(\.id) + aliasMatches.compactMap { $0.character?.id })
        guard matchedCharacterIDs.count == 1, let characterID = matchedCharacterIDs.first else { return nil }
        if canonicalMatches.contains(where: { $0.id == characterID }) {
            return CharacterReference(characterID: characterID, source: .canonical)
        }
        let matchingAliases = aliasMatches.filter { $0.character?.id == characterID }
        guard matchingAliases.count == 1 else { return nil }
        return CharacterReference(characterID: characterID, source: .alias(matchingAliases[0].id))
    }

    private func canCreateCharacter(from text: String) -> Bool {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.contains("\n") else { return false }
        let hasCanonicalMatch = allCharacters.contains {
            $0.book?.id == book.id &&
            $0.realName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let hasAliasMatch = allAliases.contains {
            $0.character?.book?.id == book.id &&
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return !hasCanonicalMatch && !hasAliasMatch
    }

    private func createCharacter(from text: String) -> CharacterReference? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCreateCharacter(from: name) else { return nil }
        let character = Character(realName: name, book: book)
        character.sortOrder = (allCharacters.filter { $0.book?.id == book.id }.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(character)
        do {
            try modelContext.save()
            onOpenCharacter(character)
            return CharacterReference(characterID: character.id, source: .canonical)
        } catch {
            modelContext.delete(character)
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let section {
                let index = sectionIndex(for: section, in: book)
                HStack(spacing: 4) {
                    Text("第 \(index) 節｜")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            titleFieldFocused = true
                        }
                    TextField("節次標題", text: Binding(
                        get: { section.title },
                        set: { section.title = $0 }
                    ))
                    .font(.system(size: 24, weight: .bold))
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onKeyPress(.tab) {
                        titleFieldFocused = false
                        bridge.focusEditor()
                        return .handled
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                Divider()
                HStack(spacing: 8) {
                    Label(cursorIsHeading ? "幕標題" : "內文", systemImage: cursorIsHeading ? "textformat.size" : "text.alignleft")
                        .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                    Spacer()
                    Button { bridge.requestToggleHeading() } label: {
                        Label("標題", systemImage: "textformat.size").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .help("將游標所在段落設為幕標題 / 內文 (⌘2)")
                    .keyboardShortcut("2", modifiers: .command)
                    Button {
                        activeAnnotation = planningStore.ensureAnnotation(sectionID: section.id, bookID: book.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                            if let annotation = planningStore.annotation(sectionID: section.id),
                               !annotation.plannedOutline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Circle().fill(.green.opacity(0.55)).frame(width: 5, height: 5)
                            }
                            if let annotation = planningStore.annotation(sectionID: section.id),
                               !annotation.revisionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Circle().fill(.orange.opacity(0.65)).frame(width: 5, height: 5)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("預定大綱與修改註記")
                    .popover(item: $activeAnnotation) { annotation in
                        SectionAnnotationsPopover(annotation: annotation)
                    }
                    Toggle("反白角色時顯示資訊", isOn: $showCharacterSelectionInfo)
                        .toggleStyle(.switch)
                        .font(.caption)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.appBackground)
                Divider()
                if showCharacterSelectionInfo, let character = selectedCharacterMatch {
                    CharacterSelectionInfoBar(character: character) {
                        onOpenCharacter(character)
                    }
                    Divider()
                }
                ZStack(alignment: .topLeading) {
                    RichEditorView(
                        section: section,
                        bridge: bridge,
                        onWordCountChange: { liveWordCount = $0 },
                        onHeadingStateChange: { cursorIsHeading = $0 },
                        onSaveStateChange: { saveState = $0 },
                        onEditorFocus: { showingInlineAutosaveHint = false },
                        onLoadingChange: { isContentLoading = $0 },
                        onSelectionTextChange: { selectedText = $0 },
                        onOpenSelectedText: { text in
                            guard let character = characterMatch(for: text) else { return false }
                            onOpenCharacter(character)
                            return true
                        },
                        onOpenCharacterReference: { characterID in
                            guard let character = allCharacters.first(where: {
                                $0.book?.id == book.id && $0.id == characterID
                            }) else { return false }
                            onOpenCharacter(character)
                            return true
                        },
                        canCreateCharacter: { canCreateCharacter(from: $0) },
                        onCreateCharacter: { createCharacter(from: $0) },
                        resolveCharacterReference: { characterReference(from: $0) },
                        characterSuggestions: {
                            let characters = allCharacters
                                .filter { $0.book?.id == book.id && !$0.realName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .sorted {
                                    if $0.isPinned != $1.isPinned { return $0.isPinned }
                                    return $0.sortOrder < $1.sortOrder
                                }
                            let trueNames = characters.map {
                                    CharacterMentionSuggestion(
                                        id: $0.id,
                                        characterName: $0.realName.trimmingCharacters(in: .whitespacesAndNewlines),
                                        insertionName: $0.realName.trimmingCharacters(in: .whitespacesAndNewlines),
                                        sortOrder: $0.sortOrder,
                                        source: .canonical
                                    )
                                }
                            let aliases = allAliases.compactMap { alias -> CharacterMentionSuggestion? in
                                guard let character = alias.character,
                                      character.book?.id == book.id else { return nil }
                                let aliasName = alias.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                let characterName = character.realName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !aliasName.isEmpty, !characterName.isEmpty else { return nil }
                                return CharacterMentionSuggestion(
                                    id: character.id,
                                    characterName: characterName,
                                    insertionName: aliasName,
                                    sortOrder: character.sortOrder,
                                    source: .alias(alias.id)
                                )
                            }
                            return trueNames + aliases
                        },
                        onCreateStoryTag: { kind, text, range in
                            // The marker refreshes the editor from the model;
                            // commit first so creating a tag never discards a
                            // just-typed paragraph that is still debouncing.
                            bridge.flushPendingSave()
                            let label = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                            do {
                                if kind.isStructuralOutlineKind {
                                    _ = try planningStore.createOutlineItemFromProse(
                                        kind: kind,
                                        title: label,
                                        anchorText: text,
                                        anchorOffset: range.location,
                                        bookID: book.id,
                                        sectionID: section.id,
                                        sections: BookStructure.orderedSections(in: book)
                                    )
                                } else {
                                    planningStore.createTag(title: label, kind: kind, anchorText: text, anchorOffset: range.location, bookID: book.id, sectionID: section.id)
                                }
                            } catch {
                                saveState = .failed
                            }
                            bridge.reloadVisibleContent()
                        },
                        storyTags: { planningStore.tags(sectionID: section.id) },
                        outlineMarkers: { planningStore.outlineMarkers(sectionID: section.id) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isContentLoading && !section.content.characters.isEmpty {
                        ProgressView("載入內容…")
                            .controlSize(.small)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .allowsHitTesting(false)
                    }

                    if showingInlineAutosaveHint && section.content.characters.isEmpty {
                        Text("內容會自動儲存，開始輸入正文…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary.opacity(0.48))
                            .padding(.leading, 24)
                            .padding(.top, 24)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                Divider()
                HStack {
                    Text(saveState.label)
                        .font(.caption)
                        .foregroundStyle(saveState == .failed ? .red : .secondary)
                    Spacer()
                    Text("\(liveWordCount) 字 · 第 \(index) 節 · \(section.volume?.title ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.appBackground)
            } else {
                ContentUnavailableView("從目錄選擇節，或新增一節開始寫作", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.appBackground)
        .onAppear {
            liveWordCount = section?.wordCount ?? 0
            if !hasShownInlineAutosaveHint {
                showingInlineAutosaveHint = true
                hasShownInlineAutosaveHint = true
            }
        }
        .onChange(of: section?.id) {
            liveWordCount = section?.wordCount ?? 0
            saveState = .saved
            selectedText = ""
        }
    }

    private func sectionIndex(for section: Section, in book: Book) -> Int {
        guard let volume = section.volume else { return 1 }
        let sortedSections = volume.sections.sorted { $0.sortOrder < $1.sortOrder }
        if let index = sortedSections.firstIndex(where: { $0.id == section.id }) {
            return index + 1
        }
        return 1
    }
}

private struct SectionAnnotationsPopover: View {
    @Bindable var annotation: ChapterAnnotation
    @Environment(StoryPlanningStore.self) private var planningStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("章節註記").font(.headline)
            annotationField("預定大綱", color: .green, text: $annotation.plannedOutline, prompt: "這一節預定要發生什麼…")
            annotationField("修改", color: .orange, text: $annotation.revisionNote, prompt: "此節還需要更新或補強什麼…")
        }
        .padding(16)
        .frame(width: 340)
        .onChange(of: annotation.plannedOutline) { _, _ in save() }
        .onChange(of: annotation.revisionNote) { _, _ in save() }
    }

    private func annotationField(_ title: String, color: Color, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color.opacity(0.8))
            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 76)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt).font(.caption).foregroundStyle(.tertiary).padding(11).allowsHitTesting(false)
                    }
                }
        }
    }

    private func save() {
        annotation.updatedAt = Date()
        planningStore.save()
    }
}

private struct CharacterSelectionInfoBar: View {
    let character: Character
    let onInspect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(character.realName.isEmpty ? "未命名角色" : character.realName)
                    .font(.subheadline.weight(.semibold))
                Text("已辨識反白的角色名稱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("在側欄查看", action: onInspect)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }
}
