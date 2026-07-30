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
    var body: some View {
        HSplitView {
            BookInfoPanel(book: book).frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
            VolumeSectionTreeView(book: book, onSelectSection: { section in sectionToOpen = section })
                .frame(minWidth: 300, idealWidth: 400)
        }
        .navigationTitle(book.title)
        .navigationSubtitle("書籍總覽")
        .navigationDestination(item: $sectionToOpen) { section in
            EditorWorkspaceView(book: book, initialSection: section)
        }
    }
}

// MARK: - 左側：書本基本資訊面板
struct BookInfoPanel: View {
    @Bindable var book: Book
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("簡介").font(.headline).foregroundStyle(.secondary)
                    TextField("簡介（選填）", text: Binding(
                        get: { book.synopsis },
                        set: { book.synopsis = $0; book.updatedAt = Date() }
                    ), axis: .vertical).lineLimit(4...8).textFieldStyle(.roundedBorder)
                }
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
            case .volume(let v): Text("確定要刪除卷「\(v.title)」嗎？其下所有章節將一併刪除，且無法復原。")
            case .section(let s): Text("確定要刪除章節「\(s.title)」嗎？此操作無法復原。")
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
                    ForEach(volume.sections.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { section in
                        sectionRow(for: section, in: volume)
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
                .onTapGesture { toggleVolume(volume.id) }
            if renamingID == volume.id {
                renameEditor(commit: { newName in
                    volume.title = newName.isEmpty ? volume.title : newName
                    book.updatedAt = Date()
                })
            } else {
                Text(volume.title).lineLimit(1).fontWeight(.semibold)
                    .onTapGesture { startRenaming(id: volume.id, currentName: volume.title) }
            }
            Button { addSection(to: volume) } label: { Image(systemName: "plus").foregroundStyle(.secondary) }
                .buttonStyle(.borderless).help("在此卷新增章節")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { toggleVolume(volume.id) }
        .onDrop(of: [UTType.plainText], delegate: VolumeDropDelegate(
            targetID: volume.id, draggingKind: $draggingKind, highlightID: $dropTargetVolumeID,
            onMove: { draggedID in moveVolume(draggedID: draggedID, before: volume.id) }
        ))
        .contextMenu {
            Button { addSection(to: volume) } label: { Label("新增章節", systemImage: "doc.badge.plus") }
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
                // 【修正】總目錄這裡使用「第 X 節 標題」
                Text("第 \(index) 節 \(section.title)").lineLimit(1)
                    .onTapGesture { startRenaming(id: section.id, currentName: section.title) }
            }
        }
        .padding(.leading, 8).padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onSelectSection?(section) }
        .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(
            targetID: section.id, targetVolumeID: volume.id, draggingKind: $draggingKind, highlightID: $dropTargetSectionID,
            onMove: { draggedID in moveSection(in: volume, draggedID: draggedID, before: section.id) }
        ))
        .contextMenu {
            Button { startRenaming(id: section.id, currentName: section.title) } label: { Label("重新命名", systemImage: "pencil") }
            Button { addSection(to: volume) } label: { Label("新增章節", systemImage: "doc.badge.plus") }
            Divider()
            Button(role: .destructive) { deleteTarget = .section(section) } label: { Label("刪除章節", systemImage: "trash") }
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

    private func addVolume() {
        let next = (book.volumes.map(\.sortOrder).max() ?? -1) + 1
        book.volumes.append(Volume(title: "新卷", sortOrder: next, book: book))
        book.updatedAt = Date()
    }
    private func addSection(to volume: Volume) {
        let next = (volume.sections.map(\.sortOrder).max() ?? -1) + 1
        volume.sections.append(Section(title: "新章節", sortOrder: next, volume: volume))
        book.updatedAt = Date()
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
        switch target {
        case .volume(let v): modelContext.delete(v)
        case .section(let s): modelContext.delete(s)
        }
        book.updatedAt = Date()
        deleteTarget = nil
    }
}
