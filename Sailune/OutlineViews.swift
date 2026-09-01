import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("故事背景")
                .font(.headline)
            Text("記錄整本書共用的世界前提、核心方向與故事目的。這裡不會因大綱狀態而自動改變。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: backgroundBinding)
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
    }

    private var backgroundBinding: Binding<String> {
        Binding(
            get: { profile.backgroundText },
            set: {
                profile.backgroundText = $0
                profile.updatedAt = Date()
            }
        )
    }

    private func save() {
        do {
            try planningStore.saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct BookOutlineWorkspaceView: View {
    let book: Book
    let presentation: BookOutlinePresentation
    @Environment(StoryPlanningStore.self) private var planningStore
    @State private var selectedStoryLineID: UUID?
    @State private var errorMessage: String?

    private var storyLines: [OutlineStoryLine] {
        planningStore.storyLines(bookID: book.id)
    }

    private var selectedStoryLine: OutlineStoryLine? {
        storyLines.first { $0.id == selectedStoryLineID } ?? storyLines.first
    }

    var body: some View {
        VStack(spacing: 0) {
            storyLineToolbar
            Divider()
            if storyLines.isEmpty {
                emptyState
            } else if presentation == .timeline {
                TimelineStoryLinesView(
                    storyLines: storyLines,
                    errorMessage: $errorMessage
                )
            } else if let storyLine = selectedStoryLine {
                StoryLineContentView(
                    storyLine: storyLine,
                    presentation: presentation,
                    isEmbedded: false,
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
    }

    private var storyLineToolbar: some View {
        HStack(spacing: 8) {
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

            Menu {
                ForEach(OutlineStoryLineKind.allCases) { kind in
                    Button(kind.rawValue) { createStoryLine(kind) }
                        .disabled(kind == .main && hasMainStoryLine)
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .help("新增故事線")
        }
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

    private func selectFirstStoryLineIfNeeded() {
        guard !storyLines.isEmpty else {
            selectedStoryLineID = nil
            return
        }
        if !storyLines.contains(where: { $0.id == selectedStoryLineID }) {
            selectedStoryLineID = storyLines.first?.id
        }
    }

    private func createStoryLine(_ kind: OutlineStoryLineKind) {
        do {
            selectedStoryLineID = try planningStore.createStoryLine(bookID: book.id, kind: kind).id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StoryLineContentView: View {
    @Bindable var storyLine: OutlineStoryLine
    let presentation: BookOutlinePresentation
    let isEmbedded: Bool
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?

    private var stages: [OutlineStage] { planningStore.stages(storyLineID: storyLine.id) }
    private var items: [OutlineItem] { planningStore.items(storyLineID: storyLine.id) }

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
                itemList(items, stage: nil)
            }
        }
        .padding(12)
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
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var mainStoryContent: some View {
        if stages.isEmpty {
            ContentUnavailableView {
                Label("主線尚未分段", systemImage: "rectangle.stack")
            } description: {
                Text("建立至少兩個階段，就能依故事發展分段閱讀。")
            } actions: {
                Button("建立第一個階段", action: createStage)
            }
        } else {
            ForEach(stages) { stage in
                StageSectionView(
                    stage: stage,
                    storyLine: storyLine,
                    presentation: presentation,
                    allStages: stages,
                    items: items.filter { $0.stageID == stage.id },
                    errorMessage: $errorMessage
                )
            }
            let unassigned = items.filter { $0.stageID == nil }
            if !unassigned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未分階段").font(.subheadline.weight(.semibold))
                    itemList(unassigned, stage: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func itemList(_ displayedItems: [OutlineItem], stage: OutlineStage?) -> some View {
        ForEach(displayedItems) { item in
            OutlineItemEditor(
                item: item,
                presentation: presentation,
                availableStages: stages,
                errorMessage: $errorMessage
            )
        }
        Button("新增大綱項目", systemImage: "plus") {
            createItem(stage: stage)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
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
        do {
            _ = try planningStore.createStage(storyLine: storyLine)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createItem(stage: OutlineStage? = nil) {
        do {
            _ = try planningStore.createOutlineItem(storyLine: storyLine, stage: stage)
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
}

/// 時間軸同時展開每條故事線，讓作者直接比較前傳、主線、支線與後記；
/// 各欄仍使用與敘事大綱相同的 `OutlineItem`，不建立第二份內容。
private struct TimelineStoryLinesView: View {
    let storyLines: [OutlineStoryLine]
    @Binding var errorMessage: String?

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(storyLines) { storyLine in
                    StoryLineContentView(
                        storyLine: storyLine,
                        presentation: .timeline,
                        isEmbedded: true,
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

private struct StageSectionView: View {
    @Bindable var stage: OutlineStage
    let storyLine: OutlineStoryLine
    let presentation: BookOutlinePresentation
    let allStages: [OutlineStage]
    let items: [OutlineItem]
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(.secondary)
                TextField("階段名稱", text: stageTitleBinding)
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
            }
            ForEach(items) { item in
                OutlineItemEditor(
                    item: item,
                    presentation: presentation,
                    availableStages: allStages,
                    errorMessage: $errorMessage
                )
            }
            Button("新增大綱項目", systemImage: "plus") {
                do {
                    _ = try planningStore.createOutlineItem(storyLine: storyLine, stage: stage)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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

    private func save() {
        do {
            try planningStore.saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OutlineItemEditor: View {
    @Bindable var item: OutlineItem
    let presentation: BookOutlinePresentation
    let availableStages: [OutlineStage]
    @Environment(StoryPlanningStore.self) private var planningStore
    @Binding var errorMessage: String?

    var body: some View {
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
                TextField("大綱標題", text: titleBinding)
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                TextField("內容（選填）", text: detailBinding, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)

                HStack(spacing: 8) {
                    Picker("狀態", selection: statusBinding) {
                        ForEach(OutlineItemStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    TextField("順序", value: sortOrderBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .help("手動排序值")

                    if !availableStages.isEmpty {
                        Picker("階段", selection: stageBinding) {
                            Text("未分階段").tag(UUID?.none)
                            ForEach(availableStages) { stage in
                                Text(stage.title).tag(Optional(stage.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Spacer()
                    Button("儲存", systemImage: "square.and.arrow.down", action: save)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { item.title }, set: { newValue in update { item.title = newValue } })
    }

    private var detailBinding: Binding<String> {
        Binding(get: { item.detail }, set: { newValue in update { item.detail = newValue } })
    }

    private var statusBinding: Binding<OutlineItemStatus> {
        Binding(get: { item.status }, set: { newValue in update { item.status = newValue } })
    }

    private var sortOrderBinding: Binding<Int> {
        Binding(get: { item.sortOrder }, set: { newValue in update { item.sortOrder = max(0, newValue) } })
    }

    private var stageBinding: Binding<UUID?> {
        Binding(get: { item.stageID }, set: { newValue in update { item.stageID = newValue } })
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

}
