import SwiftUI
import SwiftData

struct WritingReferenceScanner {
    static func plainText(_ section: Section) -> String {
        NSAttributedString(section.content).string
    }

    static func contains(_ name: String, in section: Section) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return plainText(section).localizedCaseInsensitiveContains(trimmed)
    }

    static func sections(for character: Character, in book: Book) -> [Section] {
        sections(for: character, aliases: [], in: book)
    }

    static func sections(for character: Character, aliases: [CharacterAlias], in book: Book) -> [Section] {
        let names = characterNames(for: character, aliases: aliases)
        return allSections(in: book).filter { section in
            names.contains { contains($0, in: section) }
        }
    }

    static func contains(_ character: Character, aliases: [CharacterAlias], in section: Section) -> Bool {
        !matchingNames(for: character, aliases: aliases, in: section).isEmpty
    }

    static func matchingNames(for character: Character, aliases: [CharacterAlias], in section: Section) -> [String] {
        characterNames(for: character, aliases: aliases).filter { contains($0, in: section) }
    }

    static func characterNames(for character: Character, aliases: [CharacterAlias]) -> [String] {
        ([character.realName] + aliases
            .filter { $0.character?.id == character.id }
            .map(\.name))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func sections(for item: Item, in book: Book) -> [Section] {
        allSections(in: book).filter { contains(item.name, in: $0) }
    }

    static func allSections(in book: Book) -> [Section] {
        book.volumes.sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { $0.sections.sorted { $0.sortOrder < $1.sortOrder } }
    }
}

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
    case character = "角色"
    case ability = "能力"
    case item = "物品"
    var id: String { rawValue }
}

// MARK: - 1. 設定集根視圖
struct InspectorRootView: View {
    let book: Book
    let currentSection: Section?
    let onSelectSection: ((Section) -> Void)?
    @State private var selectedTab: InspectorTab = .character
    @State private var route: InspectorRoute = .list

    init(book: Book, currentSection: Section? = nil, onSelectSection: ((Section) -> Void)? = nil) {
        self.book = book
        self.currentSection = currentSection
        self.onSelectSection = onSelectSection
    }

    var body: some View {
        VStack(spacing: 0) {
            if let currentSection {
                WritingReferenceSummaryView(book: book, section: currentSection)
            }
            Picker("設定種類", selection: $selectedTab) {
                Text("角色").tag(InspectorTab.character)
                Text("能力").tag(InspectorTab.ability)
                Text("物品").tag(InspectorTab.item)
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
                        currentSection: currentSection,
                        onSelectSection: onSelectSection,
                        onSelect: { route = .detail($0) },
                        onCreated: { route = .detail($0) }
                    )
                } else if selectedTab == .ability {
                    AbilityListContainerView(book: book)
                } else {
                    ItemListContainerView(book: book, currentSection: currentSection, onSelectSection: onSelectSection)
                }
            case .detail(let character):
                CharacterDetailView(
                    character: character,
                    book: book,
                    onBack: { route = .list },
                    onShowGraph: { route = .graph(character) },
                    onSelectSection: onSelectSection
                )
            case .graph(let character):
                KinshipGraphView(
                    character: character,
                    book: book,
                    onBack: { route = .detail(character) },
                    onSelectCharacter: { route = .graph($0) }
                )
            }
        }
    }
}

private struct ItemListContainerView: View {
    let book: Book
    let currentSection: Section?
    let onSelectSection: ((Section) -> Void)?
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @State private var searchText = ""
    @State private var showCurrentSectionOnly = false

    private var items: [Item] {
        let bookItems = allItems.filter { $0.book?.id == book.id }
        let related = showCurrentSectionOnly && currentSection != nil
            ? bookItems.filter { WritingReferenceScanner.contains($0.name, in: currentSection!) }
            : bookItems
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return related }
        return related.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.itemDescription.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋物品", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12).padding(.top, 10)

            if currentSection != nil {
                Toggle("只顯示本節引用物品", isOn: $showCurrentSectionOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                Spacer().frame(height: 10)
            }

            List {
                if items.isEmpty {
                    ContentUnavailableView("尚無符合的物品", systemImage: "shippingbox")
                } else {
                    ForEach(items) { item in
                        ItemReferenceRow(item: item, book: book, onSelectSection: onSelectSection)
                    }
                }
            }
            .listStyle(.plain)

        }
    }
}

private struct ItemReferenceRow: View {
    @Bindable var item: Item
    let book: Book
    let onSelectSection: ((Section) -> Void)?

    private var referencedSections: [Section] {
        WritingReferenceScanner.sections(for: item, in: book)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("物品名稱", text: $item.name)
                .textFieldStyle(.roundedBorder)
            TextField("描述", text: $item.itemDescription)
                .textFieldStyle(.roundedBorder)
            if referencedSections.isEmpty {
                Text("尚未在正文中出現")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("出現於")
                        .font(.caption2).foregroundStyle(.secondary)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(referencedSections) { section in
                                Button("第 \(sectionNumber(section, in: book)) 節｜\(section.title)") {
                                    onSelectSection?(section)
                                }
                                .buttonStyle(.link)
                                .font(.caption2)
                                .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 72)
                }
            }
            if !item.characterItems.isEmpty {
                let linkedNames = item.characterItems.compactMap { $0.character?.realName.isEmpty == false ? $0.character?.realName : nil }
                if !linkedNames.isEmpty {
                    Text("關聯角色：" + linkedNames.joined(separator: "、"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5)
        .onChange(of: item.name) { item.updatedAt = Date() }
        .onChange(of: item.itemDescription) { item.updatedAt = Date() }
    }

    private func sectionNumber(_ section: Section, in book: Book) -> Int {
        guard let volume = section.volume else { return 1 }
        return volume.sections.sorted { $0.sortOrder < $1.sortOrder }
            .firstIndex(where: { $0.id == section.id }).map { $0 + 1 } ?? 1
    }
}

private struct WritingReferenceSummaryView: View {
    let book: Book
    let section: Section
    @Query private var allItems: [Item]
    @Query private var allAliases: [CharacterAlias]

    private var referencedItems: [Item] {
        allItems.filter { $0.book?.id == book.id && WritingReferenceScanner.contains($0.name, in: section) }
    }
    private var referencedCharacters: [Character] {
        book.characters.filter { WritingReferenceScanner.contains($0, aliases: allAliases, in: section) }
    }
    private var referencedCharacterLabels: [String] {
        referencedCharacters.map { character in
            let matchedAliases = WritingReferenceScanner.matchingNames(for: character, aliases: allAliases, in: section)
                .filter { $0.compare(character.realName, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
            let name = character.realName.isEmpty ? "未命名角色" : character.realName
            return matchedAliases.isEmpty ? name : "\(name)（別名：\(matchedAliases.joined(separator: "、"))）"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("本節引用", systemImage: "link")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("角色 \(referencedCharacters.count) · 物品 \(referencedItems.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if referencedCharacters.isEmpty && referencedItems.isEmpty {
                Text("尚未找到設定集項目引用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text((referencedCharacterLabels + referencedItems.map { $0.name })
                    .filter { !$0.isEmpty }
                    .joined(separator: "、"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }
}

private struct AbilityListContainerView: View {
    let book: Book
    @Query(sort: \CharacterAbility.createdAt) private var allAbilities: [CharacterAbility]
    @Query(sort: \Character.createdAt) private var allCharacters: [Character]

    private var characters: [Character] { allCharacters.filter { $0.book?.id == book.id } }
    private var abilities: [CharacterAbility] {
        let ids = Set(characters.map(\.id))
        return allAbilities.filter { $0.character.map { ids.contains($0.id) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            if abilities.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("尚無能力資料")
                        .font(.headline)
                    Text(characters.isEmpty ? "先新增角色，再從角色詳細資料建立能力。" : "可從角色詳細資料建立第一項能力。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                List(abilities) { ability in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ability.name.isEmpty ? "未命名能力" : ability.name).font(.headline)
                        Text(ability.character?.realName.isEmpty == false ? ability.character!.realName : "未命名角色")
                            .font(.caption).foregroundStyle(.secondary)
                        if !ability.currentStage.isEmpty { Text(ability.currentStage).font(.caption2).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - 1b. 列表容器
struct CharacterListContainerView: View {
    let book: Book
    let currentSection: Section?
    let onSelectSection: ((Section) -> Void)?
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
            currentSection: currentSection,
            onSelect: onSelect,
            onAdd: addCharacter,
            onDelete: { character in
                do {
                    try PersistentModelDeletion.deleteCharacter(character, in: modelContext)
                } catch {
                    print("❌ 角色刪除失敗：\(error.localizedDescription)")
                }
            }
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
    let currentSection: Section?
    let onSelect: (Character) -> Void
    let onAdd: () -> Void
    let onDelete: (Character) -> Void
    @State private var searchText = ""
    @State private var showCurrentSectionOnly = false
    @Query private var allAliases: [CharacterAlias]

    private var filteredCharacters: [Character] {
        let source = showCurrentSectionOnly && currentSection != nil
            ? characters.filter { WritingReferenceScanner.contains($0, aliases: allAliases, in: currentSection!) }
            : characters
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { character in
            character.realName.localizedCaseInsensitiveContains(query) ||
            character.notes?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜尋角色", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)

            if currentSection != nil {
                Toggle("只顯示本節相關角色", isOn: $showCurrentSectionOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            List {
                if filteredCharacters.isEmpty {
                    ContentUnavailableView("找不到角色", systemImage: "person.crop.circle.badge.questionmark")
                } else {
                    ForEach(filteredCharacters) { character in
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
    let onSelectSection: ((Section) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Query private var allProfiles: [CharacterProfile]

    private var profile: CharacterProfile? {
        allProfiles.first { $0.character?.id == character.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("返回列表", systemImage: "chevron.left")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    characterHeader

                    CharacterReferenceSectionsView(character: character, book: book, onSelectSection: onSelectSection)

                    detailSection("摘要", systemImage: "text.quote") {
                        CharacterSummarySectionView(character: character)
                    }

                    detailSection("基本資訊", systemImage: "person.text.rectangle") {
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
                        Divider()
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

                        Text("來歷").font(.caption).foregroundStyle(.secondary)
                        InsetTextEditor(text: Binding(
                            get: { character.originStory ?? "" },
                            set: { character.originStory = $0 }
                        ), minHeight: 90)
                        textEditorField("私人備註 / 非血緣關係", text: $character.notes)
                    }

                    detailSection("別名", systemImage: "person.badge.key") {
                        CharacterAliasSectionView(character: character)
                    }

                    detailSection("組織", systemImage: "building.2") {
                        CharacterOrganizationSectionView(character: character, book: book)
                    }

                    detailSection("能力", systemImage: "sparkles") {
                        CharacterAbilitySectionView(character: character, book: book)
                    }

                    detailSection("外觀", systemImage: "person.crop.rectangle") {
                        CharacterAppearanceSectionView(character: character, book: book)
                    }

                    detailSection("心理", systemImage: "brain.head.profile") {
                        CharacterPsychologySectionView(character: character, book: book)
                    }

                    detailSection("物品", systemImage: "shippingbox") {
                        CharacterItemSectionView(character: character, book: book)
                    }

                    detailSection("關係", systemImage: "point.3.connected.trianglepath.dotted") {
                        Button(action: onShowGraph) {
                            Label("開啟關係網", systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    detailSection("事件", systemImage: "calendar.badge.clock") {
                        CharacterEventSectionView(character: character, book: book)
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private var characterHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("角色真名", text: $character.realName)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .frame(minHeight: 32, alignment: .center)
                .padding(.vertical, 2)
            TextField("角色定位，例如：男主角", text: roleBinding)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var roleBinding: Binding<String> {
        Binding(
            get: { profile?.role ?? "" },
            set: { newValue in
                if let profile {
                    profile.role = newValue
                } else if !newValue.isEmpty {
                    let created = CharacterProfile(role: newValue, character: character)
                    modelContext.insert(created)
                }
            }
        )
    }

    @ViewBuilder
    private func detailSection<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        CollapsibleDetailSection(title: title, systemImage: systemImage, characterID: character.id, content: content)
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
            InsetTextEditor(text: Binding(
                get: { text.wrappedValue ?? "" },
                set: { text.wrappedValue = $0 }
            ), minHeight: 90)
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

private struct CharacterReferenceSectionsView: View {
    let character: Character
    let book: Book
    let onSelectSection: ((Section) -> Void)?
    @Query private var allAliases: [CharacterAlias]
    @AppStorage private var isCollapsed: Bool

    init(character: Character, book: Book, onSelectSection: ((Section) -> Void)?) {
        self.character = character
        self.book = book
        self.onSelectSection = onSelectSection
        _isCollapsed = AppStorage(wrappedValue: false, "dreaMoon.characterDetail.\(character.id.uuidString).正文引用.collapsed")
    }

    var body: some View {
        let sections = WritingReferenceScanner.sections(for: character, aliases: allAliases, in: book)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("正文引用", systemImage: "link")
                    .font(.headline)
                Spacer()
                Button { isCollapsed.toggle() } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "展開正文引用" : "收合正文引用")
            }
            if !isCollapsed && sections.isEmpty {
                Text("尚未在正文中找到此角色名稱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isCollapsed {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(sections) { section in
                            Button("第 \(sectionNumber(section, in: book)) 節｜\(section.title)") {
                                onSelectSection?(section)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionNumber(_ section: Section, in book: Book) -> Int {
        guard let volume = section.volume else { return 1 }
        return volume.sections.sorted { $0.sortOrder < $1.sortOrder }
            .firstIndex(where: { $0.id == section.id }).map { $0 + 1 } ?? 1
    }
}

private struct CollapsibleDetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content
    @AppStorage private var isCollapsed: Bool

    init(title: String, systemImage: String, characterID: UUID, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
        _isCollapsed = AppStorage(
            wrappedValue: false,
            "dreaMoon.characterDetail.\(characterID.uuidString).\(title).collapsed"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Button { isCollapsed.toggle() } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "展開\(title)" : "收合\(title)")
            }
            if !isCollapsed {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12)))
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
    @Query(sort: \CharacterRelationship.createdAt) private var allRelationships: [CharacterRelationship]
    @Query private var allProfiles: [CharacterProfile]
    @State private var showingAddSheet = false
    @State private var showingAddGeneralRelationship = false
    @State private var selectedView = RelationshipView.network
    @State private var selectedGroup: RelationshipGroup?
    @State private var searchText = ""
    @State private var selectedFilter = "全部"
    @State private var canvasScale: CGFloat = 1

    private enum RelationshipView: String, CaseIterable, Identifiable {
        case network = "關係網"
        case list = "關係列表"
        var id: String { rawValue }
    }

    private var availableTargets: [Character] {
        allCharacters.filter { $0.id != character.id && $0.book?.id == book.id }
    }

    private var graphGroups: [RelationshipGroup] {
        RelationshipGroupBuilder.directGroups(for: character, relationships: allRelationships)
    }

    private var graphNodes: [Character] {
        var ids = Set<UUID>()
        return visibleGroups.compactMap { group in
            let peer = group.source.id == character.id ? group.target : group.source
            return ids.insert(peer.id).inserted ? peer : nil
        }
    }

    private var filterOptions: [String] {
        var values = Set<String>()
        for group in graphGroups {
            if !group.kinships.isEmpty { values.insert("血緣") }
            values.formUnion(group.currentNames)
        }
        return ["全部"] + values.sorted()
    }

    private var visibleGroups: [RelationshipGroup] {
        graphGroups.filter { group in
            let peer = group.source.id == character.id ? group.target : group.source
            let matchesSearch = searchText.isEmpty || peer.realName.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = selectedFilter == "全部" ||
                (selectedFilter == "血緣" ? !group.kinships.isEmpty : group.currentNames.contains(selectedFilter))
            return matchesSearch && matchesFilter
        }
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
                Menu {
                    Button("新增關係") { showingAddGeneralRelationship = true }
                    Button("新增血緣關係") { showingAddSheet = true }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Picker("檢視", selection: $selectedView) {
                ForEach(RelationshipView.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            HStack {
                TextField("搜尋角色", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("篩選", selection: $selectedFilter) {
                    ForEach(filterOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 130)
                if selectedView == .network {
                    Button { canvasScale = max(0.6, canvasScale - 0.1) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    Button { canvasScale = min(2, canvasScale + 0.1) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if selectedView == .list {
                RelationshipListView(center: character, book: book, searchText: searchText, selectedFilter: selectedFilter)
            } else {
                GeometryReader { viewport in
                    let baseSize = CGSize(
                        width: max(viewport.size.width, CGFloat(graphNodes.count) * 150),
                        height: max(viewport.size.height, 360)
                    )
                    let scaledSize = CGSize(width: baseSize.width * canvasScale, height: baseSize.height * canvasScale)
                    ScrollView([.horizontal, .vertical]) {
                        graphCanvas(size: baseSize)
                            .frame(width: baseSize.width, height: baseSize.height)
                            .scaleEffect(canvasScale, anchor: .topLeading)
                            .frame(width: scaledSize.width, height: scaledSize.height, alignment: .topLeading)
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
        .sheet(isPresented: $showingAddGeneralRelationship) {
            AddGeneralRelationshipSheet(
                center: character,
                book: book,
                characters: availableTargets
            )
        }
        .popover(item: $selectedGroup, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) { group in
            RelationshipDetailSheet(group: group, book: book)
        }
    }

    @ViewBuilder
    private func graphCanvas(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let nodeSize: CGFloat = 76
        let indexedNodes = Array(graphNodes.enumerated())

        ZStack {
            Color.appBackground.opacity(0.5)
            Path { path in
                for group in visibleGroups {
                    let peer = group.source.id == character.id ? group.target : group.source
                    guard let index = graphNodes.firstIndex(where: { $0.id == peer.id }) else { continue }
                    let targetPos = position(index: index, total: graphNodes.count, center: center)
                    path.move(to: center)
                    path.addLine(to: targetPos)
                }
            }
            .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)

            nodeView(character, at: center, size: nodeSize, isCenter: true)
            ForEach(indexedNodes, id: \.element.id) { index, node in
                nodeView(node, at: position(index: index, total: indexedNodes.count, center: center), size: nodeSize * 0.8, isCenter: false)
            }
            ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { groupIndex, group in
                let peer = group.source.id == character.id ? group.target : group.source
                if let index = graphNodes.firstIndex(where: { $0.id == peer.id }) {
                    let pos = position(index: index, total: graphNodes.count, center: center)
                    Button { selectedGroup = group } label: {
                        Text("\(group.source.id == character.id ? "→" : "←") \(group.currentNames.prefix(2).joined(separator: "・"))")
                            .font(.caption2).lineLimit(1).padding(8)
                            .background(Color.appBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .position(x: (center.x + pos.x) / 2, y: (center.y + pos.y) / 2 + CGFloat(groupIndex.isMultiple(of: 2) ? -10 : 10))
                }
            }
        }
    }

    private func nodeView(_ char: Character, at pos: CGPoint, size: CGFloat, isCenter: Bool) -> some View {
        Button { onSelectCharacter(char) } label: {
            ZStack {
                Circle()
                    .fill(isCenter ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .frame(width: size, height: size).shadow(radius: 2)
                VStack(spacing: 2) {
                    Text(char.realName.isEmpty ? "?" : char.realName)
                        .font(.caption).fontWeight(.medium).lineLimit(1).padding(.horizontal, 4)
                    if isCenter, let role = allProfiles.first(where: { $0.character?.id == char.id })?.role, !role.isEmpty {
                        Text(role).font(.caption2).lineLimit(1).padding(.horizontal, 4)
                    }
                }
            }
            .position(pos)
        }
        .buttonStyle(.plain)
    }

    private func position(index: Int, total: Int, center: CGPoint) -> CGPoint {
        guard total > 0 else { return center }
        let radius: CGFloat = 130
        let angle = (Double(index) / Double(total)) * (.pi * 2) - (.pi / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
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
