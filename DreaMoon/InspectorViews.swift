import SwiftUI
import SwiftData

// MARK: - 導航狀態枚舉
enum InspectorRoute: Hashable {
    case list
    case detail(Character)
    case graph(Character)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .list: hasher.combine(0)
        case .detail(let c): hasher.combine(1); hasher.combine(c.id)
        case .graph(let c): hasher.combine(2); hasher.combine(c.id)
        }
    }

    static func == (lhs: InspectorRoute, rhs: InspectorRoute) -> Bool {
        switch (lhs, rhs) {
        case (.list, .list): return true
        case (.detail(let a), .detail(let b)): return a.id == b.id
        case (.graph(let a), .graph(let b)): return a.id == b.id
        default: return false
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case character = "人物"
    case ability = "能力"
    var id: String { rawValue }
}

// MARK: - 1. 設定集根視圖
struct InspectorRootView: View {
    let book: Book
    @State private var selectedTab: InspectorTab = .character
    @State private var route: InspectorRoute = .list

    init(book: Book) { self.book = book }

    var body: some View {
        VStack(spacing: 0) {
            Picker("設定種類", selection: $selectedTab) {
                Text("人物").tag(InspectorTab.character)
                Text("能力").tag(InspectorTab.ability)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch route {
            case .list:
                if selectedTab == .character {
                    CharacterListContainerView(
                        book: book,
                        onSelect: { route = .detail($0) },
                        onCreated: { route = .detail($0) }
                    )
                } else {
                    ContentUnavailableView("敬請期待", systemImage: "hammer")
                }
            case .detail(let character):
                CharacterDetailView(
                    character: character,
                    book: book,
                    onBack: { route = .list },
                    onShowGraph: { route = .graph(character) }
                )
            case .graph(let character):
                KinshipGraphView(
                    character: character,
                    book: book,
                    onBack: { route = .detail(character) },
                    onSelectCharacter: { route = .detail($0) }
                )
            }
        }
    }
}

// MARK: - 1b. 列表容器
struct CharacterListContainerView: View {
    let book: Book
    let onSelect: (Character) -> Void
    let onCreated: (Character) -> Void
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Character.sortOrder) private var allCharacters: [Character]

    private var characters: [Character] {
        allCharacters.filter { $0.book?.id == book.id }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var body: some View {
        CharacterListView(
            characters: characters,
            onSelect: onSelect,
            onAdd: addCharacter,
            onDelete: { modelContext.delete($0) }
        )
    }

    private func addCharacter() {
        let maxOrder = characters.map(\.sortOrder).max() ?? -1
        let newChar = Character(realName: "新角色", book: book)
        newChar.sortOrder = maxOrder + 1
        modelContext.insert(newChar)
        onCreated(newChar)
    }
}

// MARK: - 2. 列表頁
struct CharacterListView: View {
    let characters: [Character]
    let onSelect: (Character) -> Void
    let onAdd: () -> Void
    let onDelete: (Character) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(characters) { character in
                    CharacterRow(character: character)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(character) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onDelete(character) } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)

            Divider()
            Button(action: onAdd) {
                Label("新增角色", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor.opacity(0.1))
        }
    }
}

struct CharacterRow: View {
    let character: Character
    var body: some View {
        HStack(spacing: 12) {
            Button { character.isPinned.toggle() } label: {
                Image(systemName: character.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(character.isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(character.realName.isEmpty ? "未命名角色" : character.realName)
                    .font(.body).fontWeight(.medium)
                Text(String(format: "UID: %06d", character.sortOrder + 1))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 3. 詳情頁
struct CharacterDetailView: View {
    @Bindable var character: Character
    let book: Book
    let onBack: () -> Void
    let onShowGraph: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                    Text("返回列表")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    formSection("基本資訊") {
                        labeledField("真名 *") {
                            TextField("必填", text: $character.realName)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("UID") {
                            Text(String(format: "%06d", character.sortOrder + 1))
                                .foregroundStyle(.secondary)
                        }
                        labeledField("性別") {
                            Picker("性別", selection: Binding(
                                get: { character.gender ?? "未設定" },
                                set: { character.gender = ($0 == "未設定") ? nil : $0 }
                            )) {
                                Text("未設定").tag("未設定")
                                Text("男").tag("男")
                                Text("女").tag("女")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    formSection("出生") {
                        BirthDatePickerSection(
                            birthYear: character.birthYear,
                            birthMonth: character.birthMonth,
                            birthDay: character.birthDay,
                            birthSeason: character.birthSeason,
                            setYear: { character.birthYear = $0 },
                            setMonth: { character.birthMonth = $0 },
                            setDay: { character.birthDay = $0 },
                            setSeason: { character.birthSeason = $0 }
                        )
                        .equatable()

                        TextField("出身 (家族/地位)", text: Binding(
                            get: { character.originBackground ?? "" },
                            set: { character.originBackground = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextEditor(text: Binding(
                            get: { character.originStory ?? "" },
                            set: { character.originStory = $0 }
                        ))
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    }

                    formSection("內在") {
                        textEditorField("性格", text: $character.personality)
                        textEditorField("原則", text: $character.principles)
                    }

                    formSection("小記") {
                        textEditorField("私人備註 / 非血緣關係", text: $character.notes)
                    }

                    formSection("親屬關係 (血緣)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(character.kinships) { kinship in
                                if let target = kinship.targetCharacter {
                                    HStack {
                                        // 【修正】使用 displayName
                                        Text(kinship.role.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 80, alignment: .leading)
                                        Text(target.realName.isEmpty ? "未命名" : target.realName)
                                        Spacer()
                                        Button(action: { removeKinship(kinship) }, label: {
                                            Image(systemName: "xmark.circle")
                                                .foregroundStyle(.red)
                                        })
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    Button(action: onShowGraph) {
                        Label("檢視關係圖", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).frame(width: 60, alignment: .leading).font(.subheadline)
            content()
        }
    }

    @ViewBuilder
    private func textEditorField(_ title: String, text: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { text.wrappedValue ?? "" },
                set: { text.wrappedValue = $0 }
            ))
            .frame(height: 80)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
        }
    }

    private func removeKinship(_ kinship: KinshipRelation) {
        if let target = kinship.targetCharacter {
            target.kinships.removeAll { $0.targetCharacter?.id == character.id }
        }
        character.kinships.removeAll { $0.id == kinship.id }
        modelContext.delete(kinship)
    }
}

// MARK: - 3b. 出生年月日 Picker
struct BirthDatePickerSection: View, Equatable {
    let birthYear: String?
    let birthMonth: String?
    let birthDay: String?
    let birthSeason: String?
    let setYear: (String?) -> Void
    let setMonth: (String?) -> Void
    let setDay: (String?) -> Void
    let setSeason: (String?) -> Void

    private static let months = Array(1...12).map { String($0) }
    private static let days = Array(1...31).map { String($0) }

    static func == (lhs: BirthDatePickerSection, rhs: BirthDatePickerSection) -> Bool {
        lhs.birthYear == rhs.birthYear && lhs.birthMonth == rhs.birthMonth &&
        lhs.birthDay == rhs.birthDay && lhs.birthSeason == rhs.birthSeason
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日期").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("年", text: Binding(
                    get: { birthYear ?? "" },
                    set: { newValue in
                        let filtered = newValue.filter(\.isNumber)
                        setYear(filtered.isEmpty ? nil : filtered)
                    }
                ))
                .textFieldStyle(.roundedBorder).frame(width: 80)

                Picker("月", selection: Binding(
                    get: { birthMonth ?? "" },
                    set: { setMonth($0.isEmpty ? nil : $0) }
                )) {
                    Text("月").tag("")
                    ForEach(Self.months, id: \.self) { Text($0).tag($0) }
                }

                Picker("日", selection: Binding(
                    get: { birthDay ?? "" },
                    set: { setDay($0.isEmpty ? nil : $0) }
                )) {
                    Text("日").tag("")
                    ForEach(Self.days, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("季節 (例: 梅雨季)", text: Binding(
                get: { birthSeason ?? "" },
                set: { setSeason($0) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - 4. 關係圖頁
struct KinshipGraphView: View {
    let character: Character
    let book: Book
    let onBack: () -> Void
    let onSelectCharacter: (Character) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Character.sortOrder) private var allCharacters: [Character]
    @State private var showingAddSheet = false

    private var availableTargets: [Character] {
        allCharacters.filter { $0.id != character.id && $0.book?.id == book.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                    Text("返回詳情")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain).help("新增血緣關係")
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            ZStack {
                Color.appBackground.opacity(0.5)
                GeometryReader { geo in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let nodeSize: CGFloat = 60

                    let indexedKinships = Array(character.kinships.enumerated())

                    Path { path in
                        for (index, kinship) in indexedKinships {
                            guard kinship.targetCharacter != nil else { continue }
                            let targetPos = position(for: kinship, index: index, total: character.kinships.count, center: center)
                            path.move(to: center)
                            path.addLine(to: targetPos)
                        }
                    }
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)

                    nodeView(character, at: center, size: nodeSize, isCenter: true)

                    ForEach(indexedKinships, id: \.element.id) { index, kinship in
                        if let target = kinship.targetCharacter {
                            let pos = position(for: kinship, index: index, total: character.kinships.count, center: center)
                            ZStack {
                                nodeView(target, at: pos, size: nodeSize * 0.8, isCenter: false)
                                // 【修正】使用 displayName
                                Text(kinship.role.displayName)
                                    .font(.caption2).padding(4)
                                    .background(Color.appBackground).cornerRadius(4)
                                    .position(x: (center.x + pos.x) / 2, y: (center.y + pos.y) / 2)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddKinshipSheet(
                sourceCharacter: character,
                book: book,
                allCharacters: availableTargets
            )
        }
    }

    private func nodeView(_ char: Character, at pos: CGPoint, size: CGFloat, isCenter: Bool) -> some View {
        Button { onSelectCharacter(char) } label: {
            ZStack {
                Circle()
                    .fill(isCenter ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .frame(width: size, height: size).shadow(radius: 2)
                Text(char.realName.isEmpty ? "?" : char.realName)
                    .font(.caption).fontWeight(.medium).lineLimit(1).padding(.horizontal, 4)
            }
            .position(pos)
        }
        .buttonStyle(.plain)
    }

    // 【修正】使用 isElder / isJunior 取代舊的 switch case
    private func position(for kinship: KinshipRelation, index: Int, total: Int, center: CGPoint) -> CGPoint {
        let spacing: CGFloat = 100
        if kinship.role.isElder {
            return CGPoint(x: center.x + CGFloat(index - total / 2) * spacing, y: center.y - spacing * 1.5)
        } else if kinship.role.isJunior {
            return CGPoint(x: center.x + CGFloat(index - total / 2) * spacing, y: center.y + spacing * 1.5)
        } else {
            let side = index % 2 == 0 ? -1.0 : 1.0
            return CGPoint(x: center.x + side * spacing * 1.5, y: center.y + CGFloat(index / 2) * spacing)
        }
    }
}

// MARK: - 5. 新增關係彈出視窗
struct AddKinshipSheet: View {
    let sourceCharacter: Character
    let book: Book
    let allCharacters: [Character]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 【修正】使用新版 Enum case
    @State private var selectedRole: KinshipRole = .fatherToChild
    @State private var selectedTargetIDString: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("新增血緣關係").font(.headline)

            Form {
                Picker("關係類型 (從 \(sourceCharacter.realName.isEmpty ? "此角色" : sourceCharacter.realName) 的角度)", selection: $selectedRole) {
                    // 【修正】使用 selectableCases + displayName
                    ForEach(KinshipRole.selectableCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }

                Picker("目標角色", selection: $selectedTargetIDString) {
                    Text("請選擇...").tag("")
                    ForEach(allCharacters) { char in
                        Text(char.realName.isEmpty ? "未命名" : char.realName).tag(char.id.uuidString)
                    }
                }
            }
            .frame(minHeight: 150)

            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("建立") {
                    createRelation()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTargetIDString.isEmpty)
            }
        }
        .padding(20).frame(width: 400, height: 250)
    }

    private func createRelation() {
        guard let targetID = UUID(uuidString: selectedTargetIDString),
              let targetChar = allCharacters.first(where: { $0.id == targetID }) else { return }

        let forwardRelation = KinshipRelation(role: selectedRole, targetCharacter: targetChar)
        sourceCharacter.kinships.append(forwardRelation)
        modelContext.insert(forwardRelation)

        let inverseRelation = KinshipRelation(role: selectedRole.inverseRole, targetCharacter: sourceCharacter)
        targetChar.kinships.append(inverseRelation)
        modelContext.insert(inverseRelation)
    }
}
