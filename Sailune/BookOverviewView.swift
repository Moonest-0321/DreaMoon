import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation

// MARK: - 拖曳層級標記
enum DragKind: Equatable {
    case volume(UUID)
    case section(UUID, volumeID: UUID)
    var id: UUID {
        switch self {
        case .volume(let id): return id
        case .section(let id, _): return id
        }
    }
}

// MARK: - 拖曳插入指示線
struct DropIndicator: View {
    let active: Bool
    var body: some View {
        if active {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 4)
                .transition(.opacity)
        }
    }
}

// MARK: - 末尾 drop 區
struct DropEndZone: View {
    let active: Bool
    let label: String
    var body: some View {
        ZStack {
            if active {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .background(Color.accentColor.opacity(0.06))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .overlay(alignment: .top) {
            if active {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(height: 3).padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Drop Delegates
struct VolumeDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingKind: DragKind?
    @Binding var highlightID: UUID?
    let onMove: (UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        if case .volume(let did) = draggingKind { return did != targetID }
        return false
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { highlightID = targetID } }
    func dropExited(info: DropInfo) { if highlightID == targetID { highlightID = nil } }
    func performDrop(info: DropInfo) -> Bool {
        highlightID = nil
        guard case .volume(let did) = draggingKind, validateDrop(info: info) else { return false }
        onMove(did)
        draggingKind = nil
        return true
    }
}

struct SectionDropDelegate: DropDelegate {
    let targetID: UUID
    let targetVolumeID: UUID
    @Binding var draggingKind: DragKind?
    @Binding var highlightID: UUID?
    let onMove: (UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        if case .section(let did, let vid) = draggingKind { return vid == targetVolumeID && did != targetID }
        return false
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { highlightID = targetID } }
    func dropExited(info: DropInfo) { if highlightID == targetID { highlightID = nil } }
    func performDrop(info: DropInfo) -> Bool {
        highlightID = nil
        guard case .section(let did, _) = draggingKind, validateDrop(info: info) else { return false }
        onMove(did)
        draggingKind = nil
        return true
    }
}

struct VolumeEndDropDelegate: DropDelegate {
    @Binding var draggingKind: DragKind?
    @Binding var isHighlighted: Bool
    let onMoveToEnd: (UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        if case .volume = draggingKind { return true }
        return false
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { isHighlighted = true } }
    func dropExited(info: DropInfo) { isHighlighted = false }
    func performDrop(info: DropInfo) -> Bool {
        isHighlighted = false
        guard case .volume(let did) = draggingKind, validateDrop(info: info) else { return false }
        onMoveToEnd(did)
        draggingKind = nil
        return true
    }
}

struct SectionEndDropDelegate: DropDelegate {
    let targetVolumeID: UUID
    @Binding var draggingKind: DragKind?
    @Binding var highlightVolumeID: UUID?
    let onMoveToEnd: (UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        if case .section(_, let vid) = draggingKind { return vid == targetVolumeID }
        return false
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { highlightVolumeID = targetVolumeID } }
    func dropExited(info: DropInfo) { if highlightVolumeID == targetVolumeID { highlightVolumeID = nil } }
    func performDrop(info: DropInfo) -> Bool {
        highlightVolumeID = nil
        guard case .section(let did, _) = draggingKind, validateDrop(info: info) else { return false }
        onMoveToEnd(did)
        draggingKind = nil
        return true
    }
}

// MARK: - 刪除確認用的列舉
enum DeleteTarget: Identifiable {
    case volume(Volume)
    case section(Section)
    var id: UUID {
        switch self {
        case .volume(let v): return v.id
        case .section(let s): return s.id
        }
    }
}

// MARK: - 書本總覽畫面 (PRD 3.2)
struct BookOverviewView: View {
    @Bindable var book: Book
    @State private var sectionToOpen: Section?
    @State private var isEditingBackground = false

    var body: some View {
        Group {
            if isEditingBackground {
                VStack(spacing: 0) {
                    HStack {
                        Button("返回書籍總覽", systemImage: "chevron.left") {
                            isEditingBackground = false
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    Divider()
                    ScrollView {
                        BookBackgroundView(book: book)
                            .frame(maxWidth: 900, alignment: .leading)
                            .padding(24)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                HSplitView {
                    BookInfoPanel(book: book, onOpenBackground: { isEditingBackground = true })
                        .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                    VolumeSectionTreeView(book: book, onSelectSection: openEditor)
                        .frame(minWidth: 300, idealWidth: 400)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationSubtitle("書籍總覽")
        .navigationDestination(item: $sectionToOpen) { section in
            EditorWorkspaceView(book: book, initialSection: section)
        }
    }

    private func openEditor(_ section: Section) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sectionToOpen = section
        }
    }
}

// MARK: - 左側：書本基本資訊面板
struct BookInfoPanel: View {
    @Bindable var book: Book
    let onOpenBackground: () -> Void
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var showingCoverImporter = false
    @State private var hasCustomCover = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("基本資訊").font(.headline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("書名").font(.subheadline).foregroundStyle(.secondary)
                        TextField("書名", text: Binding(
                            get: { book.title },
                            set: { book.title = $0; book.updatedAt = Date() }
                        )).textFieldStyle(.roundedBorder)
                        Text("作者").font(.subheadline).foregroundStyle(.secondary)
                        TextField("作者", text: Binding(
                            get: { book.author },
                            set: { book.author = $0; book.updatedAt = Date() }
                        )).textFieldStyle(.roundedBorder)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("封面").font(.headline).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 14) {
                        BookCoverArtwork(book: book)
                            .frame(width: 84, height: 118)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(hasCustomCover ? "已使用自訂封面" : "目前使用預設封面")
                                .font(.subheadline)
                            Text("建議使用直式圖片；未選擇時會自動顯示預設封面。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("選擇圖片", systemImage: "photo") {
                                    showingCoverImporter = true
                                }
                                if hasCustomCover {
                                    Button(role: .destructive) {
                                        removeCover()
                                    } label: {
                                        Label("移除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("簡介").font(.headline).foregroundStyle(.secondary)
                    TextField("簡介（選填）", text: Binding(
                        get: { book.synopsis },
                        set: { book.synopsis = $0; book.updatedAt = Date() }
                    ), axis: .vertical).lineLimit(4...8).textFieldStyle(.roundedBorder)
                }
                Divider()
                Button(action: onOpenBackground) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("故事背景")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        Text(backgroundSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("展開並編輯整本書的故事背景")
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("統計").font(.headline).foregroundStyle(.secondary)
                    HStack {
                        Text("全書總字數").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(calculateTotalWords()) 字").fontWeight(.semibold).font(.title3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .background(Color.appBackground)
        .onAppear { hasCustomCover = BookCoverStore.hasCover(for: book) }
        .fileImporter(
            isPresented: $showingCoverImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importCover(from: url)
        }
    }

    private var backgroundSummary: String {
        guard let profile = planningStore.profile(bookID: book.id) else {
            return "尚未設定。展開後可填寫世界背景、故事前提、主要衝突、主角目標與核心主題。"
        }
        let content = StoryBackgroundContent(storedValue: profile.backgroundText)
        let values = [
            content.worldBackground,
            content.premise,
            content.mainConflict,
            content.protagonistGoal,
            content.coreTheme,
            content.otherBackground
        ]
        let firstValue = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return firstValue ?? "尚未設定。展開後可填寫世界背景、故事前提、主要衝突、主角目標與核心主題。"
    }

    private func importCover(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let image = NSImage(contentsOf: url) else { return }
        do {
            try BookCoverStore.save(image: image, for: book)
            hasCustomCover = true
            book.updatedAt = Date()
        } catch {
            print("❌ 封面儲存失敗：\(error.localizedDescription)")
        }
    }

    private func removeCover() {
        do {
            try BookCoverStore.removeCover(for: book)
            hasCustomCover = false
            book.updatedAt = Date()
        } catch {
            print("❌ 封面移除失敗：\(error.localizedDescription)")
        }
    }

    private func calculateTotalWords() -> Int {
        var total = 0
        for volume in book.volumes { for section in volume.sections { total += section.wordCount } }
        return total
    }
}

// MARK: - 右側：卷/節目錄樹
struct VolumeSectionTreeView: View {
    let book: Book
    var onSelectSection: ((Section) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var renamingID: UUID? = nil
    @State private var renameBuffer: String = ""
    @FocusState private var renameFocused: Bool
    @State private var collapsedVolumeIDs: Set<UUID> = []
    @State private var deleteTarget: DeleteTarget? = nil
    @State private var undoTarget: DeleteTarget? = nil

    @State private var draggingKind: DragKind? = nil
    @State private var dropTargetVolumeID: UUID? = nil
    @State private var dropTargetSectionID: UUID? = nil
    @State private var dropTargetVolumeEnd: Bool = false
    @State private var dropTargetSectionEndVolumeID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("目錄").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    let content = ExportManager.exportBookToTXT(book: book)
                    ExportManager.presentSavePanel(for: book, defaultName: book.title, fileType: "txt", content: content)
                } label: {
                    Label("匯出 TXT", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless).help("匯出整本書為 TXT")
                Button { EpubExporter.exportBook(book: book) } label: {
                    Label("匯出 EPUB", systemImage: "book.closed")
                }
                .buttonStyle(.borderless).help("匯出整本書為 EPUB")
                Button { addVolume() } label: {
                    Label("新增卷", systemImage: "folder.badge.plus").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless).help("新增卷")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if book.volumes.isEmpty { emptyStateView } else { listView }
        }
        .background(Color.appBackground)
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
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("還沒有任何卷").foregroundStyle(.secondary)
            Button("新增第一卷") { addVolume() }.buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private var listView: some View {
        List {
            ForEach(book.volumes.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { volume in
                volumeRow(for: volume)
                if !collapsedVolumeIDs.contains(volume.id) {
                    if volume.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("這一卷還沒有節").font(.subheadline).foregroundStyle(.secondary)
                            Button("新增第一節", systemImage: "plus") { addSection(to: volume) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.leading, 42).padding(.vertical, 10)
                    } else {
                        ForEach(volume.sections.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { section in
                            sectionRow(for: section, in: volume)
                        }
                    }
                    if draggingSectionInSameVolume(volume.id) { sectionEndZone(for: volume) }
                }
            }
            if draggingVolume() { volumeEndZone }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
    
    // MARK: 輔助函數：計算節次序號
    private func sectionIndex(for section: Section, in volume: Volume) -> Int {
        let sortedSections = volume.sections.sorted { $0.sortOrder < $1.sortOrder }
        if let index = sortedSections.firstIndex(where: { $0.id == section.id }) {
            return index + 1
        }
        return 1
    }

    // MARK: 卷的列
    @ViewBuilder
    private func volumeRow(for volume: Volume) -> some View {
        HStack(spacing: 6) {
            dragHandle
                .onDrag {
                    clearDragState()
                    draggingKind = .volume(volume.id)
                    return NSItemProvider(object: NSString(string: volume.id.uuidString))
                }
            Image(systemName: collapsedVolumeIDs.contains(volume.id) ? "chevron.right" : "chevron.down")
                .font(.caption).foregroundStyle(.secondary).frame(width: 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    commitCurrentRename()
                    toggleVolume(volume.id)
                }
            if renamingID == volume.id {
                renameEditor(commit: { newName in
                    volume.title = newName.isEmpty ? volume.title : newName
                    book.updatedAt = Date()
                })
            } else {
                Text(volume.title).lineLimit(1).fontWeight(.semibold)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { startRenaming(id: volume.id, currentName: volume.title) }
            }
            Button {
                commitCurrentRename()
                addSection(to: volume)
            } label: { Image(systemName: "plus").foregroundStyle(.secondary) }
                .buttonStyle(.borderless).help("在此卷新增節")
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    commitCurrentRename()
                    toggleVolume(volume.id)
                }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], delegate: VolumeDropDelegate(
            targetID: volume.id, draggingKind: $draggingKind, highlightID: $dropTargetVolumeID,
            onMove: { draggedID in moveVolume(draggedID: draggedID, before: volume.id) }
        ))
        .contextMenu {
            Button { addSection(to: volume) } label: { Label("新增節", systemImage: "doc.badge.plus") }
            Button { addVolume() } label: { Label("新增卷", systemImage: "folder.badge.plus") }
            Divider()
            Button(role: .destructive) { deleteTarget = .volume(volume) } label: { Label("刪除卷", systemImage: "trash") }
        }
        .overlay(alignment: .top) { DropIndicator(active: dropTargetVolumeID == volume.id) }
    }

    // MARK: 節的列
    @ViewBuilder
    private func sectionRow(for section: Section, in volume: Volume) -> some View {
        let index = sectionIndex(for: section, in: volume)
        
        HStack(spacing: 6) {
            dragHandle
                .onDrag {
                    clearDragState()
                    draggingKind = .section(section.id, volumeID: volume.id)
                    return NSItemProvider(object: NSString(string: section.id.uuidString))
                }
            Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 14)
                .contentShape(Rectangle())
                .onTapGesture { onSelectSection?(section) }
            if renamingID == section.id {
                renameEditor(commit: { newName in
                    section.title = newName.isEmpty ? section.title : newName
                    section.updatedAt = Date()
                    book.updatedAt = Date()
                })
            } else {
                HStack(spacing: 0) {
                    Text("\(index)｜")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            commitCurrentRename()
                            onSelectSection?(section)
                        }
                    Text(section.title).lineLimit(1)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { startRenaming(id: section.id, currentName: section.title) }
                }
            }
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    commitCurrentRename()
                    onSelectSection?(section)
                }
        }
        .padding(.leading, 8).padding(.vertical, 2)
        .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(
            targetID: section.id, targetVolumeID: volume.id, draggingKind: $draggingKind, highlightID: $dropTargetSectionID,
            onMove: { draggedID in moveSection(in: volume, draggedID: draggedID, before: section.id) }
        ))
        .contextMenu {
            Button { startRenaming(id: section.id, currentName: section.title) } label: { Label("重新命名", systemImage: "pencil") }
            Button {
                commitCurrentRename()
                addSection(to: volume)
            } label: { Label("新增節", systemImage: "doc.badge.plus") }
            Divider()
            Button(role: .destructive) { deleteTarget = .section(section) } label: { Label("刪除節", systemImage: "trash") }
        }
        .overlay(alignment: .top) { DropIndicator(active: dropTargetSectionID == section.id) }
    }

    // MARK: 末尾 drop 區
    @ViewBuilder
    private func sectionEndZone(for volume: Volume) -> some View {
        DropEndZone(active: dropTargetSectionEndVolumeID == volume.id, label: "放到本卷末尾")
            .onDrop(of: [UTType.plainText], delegate: SectionEndDropDelegate(
                targetVolumeID: volume.id, draggingKind: $draggingKind, highlightVolumeID: $dropTargetSectionEndVolumeID,
                onMoveToEnd: { draggedID in moveSectionToEnd(in: volume, draggedID: draggedID) }
            ))
    }

    private var volumeEndZone: some View {
        DropEndZone(active: dropTargetVolumeEnd, label: "放到所有卷之後")
            .onDrop(of: [UTType.plainText], delegate: VolumeEndDropDelegate(
                draggingKind: $draggingKind, isHighlighted: $dropTargetVolumeEnd,
                onMoveToEnd: { draggedID in moveVolumeToEnd(draggedID: draggedID) }
            ))
    }

    // MARK: 拖曳把手
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            .frame(width: 24, height: 22).contentShape(Rectangle()).help("拖曳以排序")
    }

    // MARK: 改名編輯態
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
            book.updatedAt = Date()
        } else if let section = book.volumes.flatMap(\.sections).first(where: { $0.id == id }) {
            section.title = renameBuffer.isEmpty ? section.title : renameBuffer
            section.updatedAt = Date()
            book.updatedAt = Date()
        }
        renamingID = nil
        renameFocused = false
    }
    private func commitAndClose(commit: (String) -> Void) { commit(renameBuffer); renamingID = nil; renameFocused = false }
    private func cancelRenaming() { renamingID = nil; renameFocused = false }

    private func toggleVolume(_ id: UUID) {
        if collapsedVolumeIDs.contains(id) { collapsedVolumeIDs.remove(id) } else { collapsedVolumeIDs.insert(id) }
    }

    private func addVolume() {
        let next = (book.volumes.map(\.sortOrder).max() ?? -1) + 1
        book.volumes.append(Volume(title: "新卷", sortOrder: next, book: book))
        book.updatedAt = Date()
    }
    private func addSection(to volume: Volume) {
        let next = (volume.sections.map(\.sortOrder).max() ?? -1) + 1
        let newSection = Section(title: "新節", sortOrder: next, volume: volume)
        volume.sections.append(newSection)
        book.updatedAt = Date()
        onSelectSection?(newSection)
    }

    private func moveVolume(draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var arr = book.volumes.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = arr.firstIndex(where: { $0.id == draggedID }) else { return }
        let item = arr.remove(at: from)
        guard let to = arr.firstIndex(where: { $0.id == targetID }) else { return }
        arr.insert(item, at: to)
        for (i, v) in arr.enumerated() { v.sortOrder = i }
        book.updatedAt = Date()
    }
    private func moveSection(in volume: Volume, draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var arr = volume.sections.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = arr.firstIndex(where: { $0.id == draggedID }) else { return }
        let item = arr.remove(at: from)
        guard let to = arr.firstIndex(where: { $0.id == targetID }) else { return }
        arr.insert(item, at: to)
        for (i, s) in arr.enumerated() { s.sortOrder = i }
        book.updatedAt = Date()
    }
    private func moveVolumeToEnd(draggedID: UUID) {
        var arr = book.volumes.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = arr.firstIndex(where: { $0.id == draggedID }) else { return }
        let item = arr.remove(at: from); arr.append(item)
        for (i, v) in arr.enumerated() { v.sortOrder = i }
        book.updatedAt = Date()
    }
    private func moveSectionToEnd(in volume: Volume, draggedID: UUID) {
        var arr = volume.sections.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = arr.firstIndex(where: { $0.id == draggedID }) else { return }
        let item = arr.remove(at: from); arr.append(item)
        for (i, s) in arr.enumerated() { s.sortOrder = i }
        book.updatedAt = Date()
    }

    private func clearDragState() {
        draggingKind = nil
        dropTargetVolumeID = nil
        dropTargetSectionID = nil
        dropTargetVolumeEnd = false
        dropTargetSectionEndVolumeID = nil
    }
    private func draggingVolume() -> Bool {
        if case .volume = draggingKind { return true }
        return false
    }
    private func draggingSectionInSameVolume(_ vid: UUID) -> Bool {
        if case .section(_, let v) = draggingKind, v == vid { return true }
        return false
    }

    private func performDelete(_ target: DeleteTarget) {
        undoTarget = target
        switch target {
        case .volume(let v): modelContext.delete(v)
        case .section(let s): modelContext.delete(s)
        }
        book.updatedAt = Date()
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
            onSelectSection?(section)
        }
        book.updatedAt = Date()
        try? modelContext.save()
        undoTarget = nil
    }
}
