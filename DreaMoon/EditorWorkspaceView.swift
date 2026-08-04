import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

// MARK: - 三欄式編輯工作區 (PRD 3.3)
struct EditorWorkspaceView: View {
    let book: Book
    @State private var selectedSection: Section?
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var bridge = EditorBridge()

    init(book: Book, initialSection: Section) {
        self.book = book
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            EditorSidebarView(book: book, selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 300)
        } detail: {
            EditorCenterView(section: selectedSection, bridge: bridge, book: book)
                .navigationTitle("")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { toggleSidebar() } label: { Label("目錄", systemImage: "sidebar.left") }.help("顯示/隱藏左欄目錄")
                        Button { showInspector.toggle() } label: { Label("設定集", systemImage: "sidebar.right") }.help("顯示/隱藏右欄設定集")
                        Divider()
                        Button {
                            if let section = selectedSection {
                                let content = ExportManager.exportSectionToTXT(section: section)
                                ExportManager.presentSavePanel(for: book, defaultName: section.title, fileType: "txt", content: content)
                            } else {
                                let content = ExportManager.exportBookToTXT(book: book)
                                ExportManager.presentSavePanel(for: book, defaultName: book.title, fileType: "txt", content: content)
                            }
                        } label: {
                            Label("匯出 TXT", systemImage: "square.and.arrow.up")
                        }
                        .help("匯出當前章節或整本書為 TXT")
                        Button { EpubExporter.exportBook(book: book) } label: {
                            Label("匯出 EPUB", systemImage: "book.closed")
                        }
                        .help("匯出整本書為 EPUB 電子書")
                    }
                }
                .inspector(isPresented: $showInspector) {
                    // ⬇️ V3：唯一改動——掛分段 wrapper（設定集｜時間軸）
                    InspectorWithTimeline(book: book).inspectorColumnWidth(min: 250, ideal: 300, max: 400)
                }
        }
    }

    private func toggleSidebar() {
        columnVisibility = (columnVisibility == .detailOnly) ? .automatic : .detailOnly
    }
}

// MARK: - 左欄：目錄
struct EditorSidebarView: View {
    let book: Book
    @Binding var selectedSection: Section?
    @Environment(\.modelContext) private var modelContext

    @State private var draggingKind: DragKind? = nil
    @State private var dropTargetSectionID: UUID? = nil
    @State private var dropTargetSectionEndVolumeID: UUID? = nil
    @State private var collapsedVolumeIDs: Set<UUID> = []
    @State private var renamingID: UUID? = nil
    @State private var renameBuffer: String = ""
    @FocusState private var renameFocused: Bool
    @State private var deleteTarget: DeleteTarget? = nil

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
            .background(Color.appBackground) // ⚠️ 若報錯請改為 Color(NSColor.controlBackgroundColor)
            Divider()
            List {
                ForEach(book.volumes.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { volume in
                    volumeRow(for: volume)
                    if !collapsedVolumeIDs.contains(volume.id) {
                        ForEach(volume.sections.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { section in
                            sectionRow(for: section, in: volume)
                        }
                        if draggingSectionInSameVolume(volume.id) { sectionEndZone(for: volume) }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .alert("確認刪除",
               isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
               presenting: deleteTarget) { target in
            Button("取消", role: .cancel) { }
            Button("刪除", role: .destructive) { performDelete(target) }
        } message: { target in
            switch target {
            case .volume(let v): Text("確定要刪除卷「\(v.title)」嗎？其下所有章節將一併刪除，且無法復原。")
            case .section(let s): Text("確定要刪除章節「\(s.title)」嗎？此操作無法復原。")
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
                .onTapGesture { toggleVolume(volume.id) }
            if renamingID == volume.id {
                renameEditor(commit: { newName in volume.title = newName.isEmpty ? volume.title : newName })
            } else {
                Text(volume.title).lineLimit(1).fontWeight(.semibold)
                    .onTapGesture { startRenaming(id: volume.id, currentName: volume.title) }
            }
            Spacer()
            // 【新增】每個卷後面的 + 按鈕
            Button(action: { addSection(to: volume) }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain) // 使用 plain 避免破壞 List 的選取背景色
            .help("在此卷新增節次")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { toggleVolume(volume.id) } // 點擊空白處展開/收合
        .contextMenu {
            Button { addSection(to: volume) } label: { Label("新增章節", systemImage: "doc.badge.plus") }
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
            if renamingID == section.id {
                renameEditor(commit: { newName in section.title = newName.isEmpty ? section.title : newName })
            } else {
                Text("\(index). \(section.title)").lineLimit(1)
                    .onTapGesture {
                        selectedSection = section
                        startRenaming(id: section.id, currentName: section.title)
                    }
            }
        }
        .padding(.leading, 8).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selectedSection = section }
        .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(
            targetID: section.id, targetVolumeID: volume.id, draggingKind: $draggingKind, highlightID: $dropTargetSectionID,
            onMove: { draggedID in moveSection(in: volume, draggedID: draggedID, before: section.id) }
        ))
        .listRowBackground(selectedSection?.id == section.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(alignment: .top) { DropIndicator(active: dropTargetSectionID == section.id) }
        .contextMenu {
            Button { startRenaming(id: section.id, currentName: section.title) } label: { Label("重新命名", systemImage: "pencil") }
            Button { addSection(to: volume) } label: { Label("新增章節", systemImage: "doc.badge.plus") }
            Divider()
            Button(role: .destructive) { deleteTarget = .section(section) } label: { Label("刪除章節", systemImage: "trash") }
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

    private func startRenaming(id: UUID, currentName: String) { renameBuffer = currentName; renamingID = id }
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
        let newSection = Section(title: "新章節", sortOrder: next, volume: volume)
        volume.sections.append(newSection)
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
    @State private var liveWordCount: Int = 0
    @State private var cursorIsHeading: Bool = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let section {
                let index = sectionIndex(for: section, in: book)
                HStack(spacing: 4) {
                    Text("第 \(index) 節 ")
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
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.appBackground)
                Divider()
                RichEditorView(section: section, bridge: bridge, onWordCountChange: { liveWordCount = $0 }, onHeadingStateChange: { cursorIsHeading = $0 })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Spacer()
                    Text("\(liveWordCount) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.appBackground)
            } else {
                ContentUnavailableView("請從左側選擇或新增一個章節開始寫作", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.appBackground)
        .onAppear { liveWordCount = section?.wordCount ?? 0 }
        .onChange(of: section?.id) { _, _ in liveWordCount = section?.wordCount ?? 0 }
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
