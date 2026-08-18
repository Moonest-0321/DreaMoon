import SwiftUI
import SwiftData
import AppKit

struct InsetTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 90

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .font(.body)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }
}

struct CharacterSummarySectionView: View {
    let character: Character
    @Environment(\.modelContext) private var modelContext
    @Query private var allSummaries: [CharacterSummary]
    @Query(sort: \CharacterAlias.createdAt) private var allAliases: [CharacterAlias]
    @Query private var allMemberships: [CharacterOrganization]
    @Query private var allIdentities: [OrganizationIdentityHistory]
    @Query(sort: \CharacterAbility.createdAt) private var allAbilities: [CharacterAbility]
    @Query(sort: \CharacterPsychology.createdAt) private var allPsychologies: [CharacterPsychology]
    @Query(sort: \CharacterRelationship.createdAt) private var allRelationships: [CharacterRelationship]

    private var summary: CharacterSummary? { allSummaries.first { $0.character?.id == character.id } }
    private var aliases: [CharacterAlias] { allAliases.filter { $0.character?.id == character.id } }
    private var memberships: [CharacterOrganization] { allMemberships.filter { $0.character?.id == character.id } }
    private var identities: [OrganizationIdentityHistory] {
        let membershipIDs = Set(memberships.map(\.id))
        return allIdentities.filter { identity in identity.membership.map { membershipIDs.contains($0.id) } ?? false }
    }
    private var abilities: [CharacterAbility] { allAbilities.filter { $0.character?.id == character.id } }
    private var psychologies: [CharacterPsychology] { allPsychologies.filter { $0.character?.id == character.id } }
    private var relationships: [CharacterRelationship] { allRelationships.filter { $0.sourceCharacter?.id == character.id } }
    private var latestAlias: CharacterAlias? { aliases.max { $0.updatedAt < $1.updatedAt } }
    private var latestIdentity: OrganizationIdentityHistory? { identities.max { $0.updatedAt < $1.updatedAt } }
    private var latestAbility: CharacterAbility? { abilities.max { $0.updatedAt < $1.updatedAt } }
    private var latestPsychology: CharacterPsychology? { psychologies.max { $0.updatedAt < $1.updatedAt } }
    private var latestRelationship: CharacterRelationship? { relationships.max { $0.updatedAt < $1.updatedAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            summaryPicker("別名", automaticTitle: automaticTitle(latestAlias?.name), selection: aliasBinding) {
                ForEach(aliases) { Text($0.name).tag(Optional($0.id)) }
            }
            summaryPicker("組織身分", automaticTitle: automaticTitle(latestIdentity.map { "\($0.membership?.organization?.name ?? "組織")・\($0.identity)" }), selection: identityBinding) {
                ForEach(identities) { identity in
                    Text("\(identity.membership?.organization?.name ?? "組織")・\(identity.identity)").tag(Optional(identity.id))
                }
            }
            summaryPicker("能力", automaticTitle: automaticTitle(latestAbility?.name), selection: abilityBinding) {
                ForEach(abilities) { Text($0.name).tag(Optional($0.id)) }
            }
            summaryPicker("心理", automaticTitle: automaticTitle(latestPsychology.map(psychologyLabel)), selection: psychologyBinding) {
                ForEach(psychologies) { Text(psychologyLabel($0)).tag(Optional($0.id)) }
            }
            summaryPicker("關係", automaticTitle: automaticTitle(latestRelationship.map { "\($0.targetCharacter?.realName ?? "未知角色")・\($0.type)" }), selection: relationshipBinding) {
                ForEach(relationships) { relationship in
                    Text("\(relationship.targetCharacter?.realName ?? "未知角色")・\(relationship.type)").tag(Optional(relationship.id))
                }
            }
        }
    }

    private func summaryPicker<Content: View>(_ title: String, automaticTitle: String, selection: Binding<UUID?>, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).frame(width: 72, alignment: .leading).font(.subheadline)
            Picker(title, selection: selection) {
                Text(automaticTitle).tag(Optional<UUID>.none)
                content()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func automaticTitle(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "自動" }
        return "自動・\(value)"
    }

    private func currentSummary() -> CharacterSummary {
        if let summary { return summary }
        let created = CharacterSummary(character: character)
        modelContext.insert(created)
        return created
    }

    private var aliasBinding: Binding<UUID?> { Binding(get: { summary?.alias?.id }, set: { id in
        updateSummary(createIfNeeded: id != nil) { $0.alias = id.flatMap { selected in aliases.first { $0.id == selected } } }
    }) }
    private var identityBinding: Binding<UUID?> { Binding(get: { summary?.organizationIdentity?.id }, set: { id in
        updateSummary(createIfNeeded: id != nil) { $0.organizationIdentity = id.flatMap { selected in identities.first { $0.id == selected } } }
    }) }
    private var abilityBinding: Binding<UUID?> { Binding(get: { summary?.ability?.id }, set: { id in
        updateSummary(createIfNeeded: id != nil) { $0.ability = id.flatMap { selected in abilities.first { $0.id == selected } } }
    }) }
    private var psychologyBinding: Binding<UUID?> { Binding(get: { summary?.psychology?.id }, set: { id in
        updateSummary(createIfNeeded: id != nil) { $0.psychology = id.flatMap { selected in psychologies.first { $0.id == selected } } }
    }) }
    private var relationshipBinding: Binding<UUID?> { Binding(get: { summary?.relationship?.id }, set: { id in
        updateSummary(createIfNeeded: id != nil) { $0.relationship = id.flatMap { selected in relationships.first { $0.id == selected } } }
    }) }

    private func updateSummary(createIfNeeded: Bool, _ update: (CharacterSummary) -> Void) {
        if let summary {
            update(summary)
            deleteIfEmpty(summary)
        } else if createIfNeeded {
            update(currentSummary())
        }
    }

    private func deleteIfEmpty(_ summary: CharacterSummary) {
        if summary.alias == nil,
           summary.organizationIdentity == nil,
           summary.ability == nil,
           summary.psychology == nil,
           summary.relationship == nil {
            modelContext.delete(summary)
        }
    }

    private func psychologyLabel(_ psychology: CharacterPsychology) -> String {
        let type: String
        switch psychology.kind {
        case .personality: type = "性格"
        case .value: type = "價值觀"
        case .motivation: type = "動機"
        }
        return "\(type)・\(psychology.content.isEmpty ? "未填寫" : psychology.content)"
    }
}

private struct CharacterSectionEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct CharacterAliasSectionView: View {
    let character: Character
    var onRename: (CharacterAlias, String, String) -> Void = { _, _, _ in }
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CharacterAlias.createdAt) private var allAliases: [CharacterAlias]
    @State private var deletionErrorMessage: String?

    private var aliases: [CharacterAlias] { allAliases.filter { $0.character?.id == character.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if aliases.isEmpty {
                CharacterSectionEmptyState(title: "尚無別名", detail: "可加入化名、稱號或其他常用名稱。")
            } else {
                ForEach(aliases) { alias in
                    AliasRow(alias: alias, onRename: onRename, onDelete: { deleteAlias(alias) })
                }
            }
            Button { modelContext.insert(CharacterAlias(name: "新別名", character: character)) } label: {
                Label("新增別名", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .alert(
            "無法刪除別名",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "請稍後再試。")
        }
    }

    private func deleteAlias(_ alias: CharacterAlias) {
        NotificationCenter.default.post(name: .sailuneWillChangeCharacterReferences, object: nil)
        var changedSectionIDs = Set<UUID>()
        if let book = character.book {
            for section in book.volumes.flatMap(\.sections) {
                let attributed = NSMutableAttributedString(attributedString: NSAttributedString(section.content))
                var ranges: [NSRange] = []
                attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                    guard let value,
                          let reference = CharacterReferenceLink.reference(from: value),
                          reference.characterID == character.id,
                          reference.source == .alias(alias.id) else { return }
                    ranges.append(range)
                }
                guard !ranges.isEmpty else { continue }
                let legacyLink = CharacterReferenceLink.url(
                    for: CharacterReference(characterID: character.id, source: .legacy)
                )
                for range in ranges {
                    attributed.addAttribute(.link, value: legacyLink, range: range)
                }
                section.content = AttributedString(attributed)
                section.updatedAt = Date()
                changedSectionIDs.insert(section.id)
            }
            if !changedSectionIDs.isEmpty { book.updatedAt = Date() }
        }
        modelContext.delete(alias)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deletionErrorMessage = "別名刪除失敗，正文與角色資料均未變更。"
            return
        }
        if !changedSectionIDs.isEmpty {
            NotificationCenter.default.post(name: .sailuneCharacterReferencesChanged, object: changedSectionIDs)
        }
    }
}

private struct AliasRow: View {
    @Bindable var alias: CharacterAlias
    let onRename: (CharacterAlias, String, String) -> Void
    let onDelete: () -> Void
    @FocusState private var nameFieldFocused: Bool
    @State private var nameBeforeEditing = ""
    var body: some View {
        HStack {
            TextField("別名", text: $alias.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
            TextField("備註", text: $alias.note).textFieldStyle(.roundedBorder)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
        }
        .onAppear { nameBeforeEditing = alias.name }
        .onChange(of: nameFieldFocused) { _, isFocused in
            if isFocused {
                nameBeforeEditing = alias.name
            } else if nameBeforeEditing != alias.name {
                onRename(alias, nameBeforeEditing, alias.name)
            }
        }
        .onChange(of: alias.name) { alias.updatedAt = Date() }
        .onChange(of: alias.note) { alias.updatedAt = Date() }
    }
}

struct CharacterOrganizationSectionView: View {
    let character: Character
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Query private var allMemberships: [CharacterOrganization]
    @Query(sort: \Organization.name) private var allOrganizations: [Organization]

    private var memberships: [CharacterOrganization] { allMemberships.filter { $0.character?.id == character.id } }
    private var availableOrganizations: [Organization] {
        let assignedIDs = Set(memberships.compactMap { $0.organization?.id })
        return allOrganizations.filter { $0.book?.id == book.id && !assignedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if memberships.isEmpty {
                CharacterSectionEmptyState(title: "尚無組織資料", detail: "可記錄所屬組織、加入原因與備註。")
            } else {
                ForEach(memberships) { membership in
                    OrganizationMembershipRow(membership: membership, book: book, onDelete: { modelContext.delete(membership) })
                }
            }
            HStack(spacing: 12) {
                Button("新增組織", systemImage: "plus", action: addNewMembership)
                    .buttonStyle(.borderless)

                if !availableOrganizations.isEmpty {
                    Menu {
                        ForEach(availableOrganizations) { organization in
                            Button(organization.name.isEmpty ? "未命名組織" : organization.name) {
                                addMembership(for: organization)
                            }
                        }
                    } label: {
                        Label("加入既有組織", systemImage: "link.badge.plus")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    private func addNewMembership() {
        let organization = Organization(name: "新組織", book: book)
        modelContext.insert(organization)
        addMembership(for: organization)
    }

    private func addMembership(for organization: Organization) {
        modelContext.insert(CharacterOrganization(character: character, organization: organization))
    }
}

private struct OrganizationMembershipRow: View {
    @Bindable var membership: CharacterOrganization
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if let organization = membership.organization {
                    @Bindable var organization = organization
                    TextField("組織名稱", text: $organization.name).textFieldStyle(.roundedBorder)
                }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            HStack {
                TextField("加入原因", text: $membership.reason).textFieldStyle(.roundedBorder)
                TextField("備註", text: $membership.note).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("加入時間").font(.caption).foregroundStyle(.secondary)
                CharacterNodePicker(book: book, node: $membership.joinNode)
            }
            if let current = membership.identityHistory.sorted(by: { $0.sortOrder < $1.sortOrder }).last {
                Text("目前身分：\(current.identity)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("尚無身分歷史").font(.caption).foregroundStyle(.tertiary)
            }
            OrganizationIdentityHistoryEditor(membership: membership, book: book)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CharacterAbilitySectionView: View {
    let character: Character
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CharacterAbility.createdAt) private var allAbilities: [CharacterAbility]

    private var abilities: [CharacterAbility] { allAbilities.filter { $0.character?.id == character.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if abilities.isEmpty {
                CharacterSectionEmptyState(title: "尚無能力資料", detail: "可記錄能力名稱、目前階段與摘要。")
            } else {
                ForEach(abilities) { ability in AbilityRow(ability: ability, book: book, onDelete: { modelContext.delete(ability) }) }
            }
            Button { modelContext.insert(CharacterAbility(name: "新能力", character: character)) } label: {
                Label("新增能力", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct AbilityRow: View {
    @Bindable var ability: CharacterAbility
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField("能力名稱", text: $ability.name).textFieldStyle(.roundedBorder)
                TextField("目前階段", text: $ability.currentStage).textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            TextField("階段描述", text: $ability.stageDescription).textFieldStyle(.roundedBorder)
            TextField("摘要", text: $ability.summary).textFieldStyle(.roundedBorder)
            AbilityHistoryEditor(ability: ability, book: book)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: ability.name) { ability.updatedAt = Date() }
        .onChange(of: ability.currentStage) { ability.updatedAt = Date() }
        .onChange(of: ability.stageDescription) { ability.updatedAt = Date() }
        .onChange(of: ability.summary) { ability.updatedAt = Date() }
    }
}

struct CharacterAppearanceSectionView: View {
    let character: Character
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CharacterAppearance.createdAt) private var allAppearances: [CharacterAppearance]
    private var appearances: [CharacterAppearance] { allAppearances.filter { $0.character?.id == character.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appearances.isEmpty {
                CharacterSectionEmptyState(title: "尚無外觀資料", detail: "可新增服裝與身體特徵。")
            } else {
                ForEach(appearances) { appearance in AppearanceRow(appearance: appearance, book: book, onDelete: { modelContext.delete(appearance) }) }
            }
            Menu("新增外觀") {
                Button("服裝") { add(.outfit) }
                Button("身體特徵") { add(.bodyFeature) }
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func add(_ kind: CharacterAppearanceKind) {
        modelContext.insert(CharacterAppearance(kind: kind, descriptionText: "新外觀", character: character))
    }
}

private struct AppearanceRow: View {
    @Bindable var appearance: CharacterAppearance
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Picker("類型", selection: $appearance.kindRawValue) {
                    Text("服裝").tag(CharacterAppearanceKind.outfit.rawValue)
                    Text("身體特徵").tag(CharacterAppearanceKind.bodyFeature.rawValue)
                }.frame(width: 150)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            Text("外觀描述").font(.caption).foregroundStyle(.secondary)
            InsetTextEditor(text: $appearance.descriptionText, minHeight: 110)
            TextField(appearance.kind == .outfit ? "場景／用途" : "備註", text: appearance.kind == .outfit ? $appearance.usage : $appearance.note)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("時間定位").font(.caption).foregroundStyle(.secondary)
                CharacterNodePicker(book: book, node: $appearance.node)
            }
        }
    }
}

struct CharacterPsychologySectionView: View {
    let character: Character
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CharacterPsychology.createdAt) private var allPsychologies: [CharacterPsychology]
    private var psychologies: [CharacterPsychology] { allPsychologies.filter { $0.character?.id == character.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if psychologies.isEmpty {
                CharacterSectionEmptyState(title: "尚無心理資料", detail: "可新增性格、價值觀與動機。")
            } else {
                ForEach(psychologies) { psychology in PsychologyRow(psychology: psychology, book: book, onDelete: { modelContext.delete(psychology) }) }
            }
            Menu("新增心理資料") {
                Button("性格") { add(.personality) }
                Button("價值觀") { add(.value) }
                Button("動機") { add(.motivation) }
            }.menuStyle(.borderlessButton)
        }
    }

    private func add(_ kind: CharacterPsychologyKind) {
        modelContext.insert(CharacterPsychology(kind: kind, content: "", character: character))
    }
}

private struct PsychologyRow: View {
    @Bindable var psychology: CharacterPsychology
    let book: Book
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Picker("類型", selection: $psychology.kindRawValue) {
                    Text("性格").tag(CharacterPsychologyKind.personality.rawValue)
                    Text("價值觀").tag(CharacterPsychologyKind.value.rawValue)
                    Text("動機").tag(CharacterPsychologyKind.motivation.rawValue)
                }
                .frame(width: 150)

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Label("刪除心理資料", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("刪除心理資料")
            }

            TextField("內容", text: $psychology.content)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Text("時間定位")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CharacterNodePicker(book: book, node: $psychology.node)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: psychology.kindRawValue) { psychology.updatedAt = Date() }
        .onChange(of: psychology.content) { psychology.updatedAt = Date() }
    }
}

struct CharacterItemSectionView: View {
    let character: Character
    let book: Book
    var onOpenItem: ((Item) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var allCharacterItems: [CharacterItem]
    @Query(sort: \Item.name) private var allItems: [Item]
    private var characterItems: [CharacterItem] { allCharacterItems.filter { $0.character?.id == character.id } }
    private var availableItems: [Item] {
        let assignedIDs = Set(characterItems.compactMap { $0.item?.id })
        return allItems.filter { $0.book?.id == book.id && !assignedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if characterItems.isEmpty {
                CharacterSectionEmptyState(title: "尚無持有物品", detail: "可在物品設定中管理描述、數量與統一歷史。")
            } else {
                ForEach(characterItems) { characterItem in
                    ItemRow(
                        characterItem: characterItem,
                        book: book,
                        onOpenItem: onOpenItem,
                        onDelete: { modelContext.delete(characterItem) }
                    )
                }
            }
            HStack(spacing: 12) {
                Button("新增物品", systemImage: "plus", action: addNewItem)
                    .buttonStyle(.borderless)

                if !availableItems.isEmpty {
                    Menu {
                        ForEach(availableItems) { item in
                            Button(item.name.isEmpty ? "未命名物品" : item.name) {
                                addItem(item)
                            }
                        }
                    } label: {
                        Label("加入既有物品", systemImage: "link.badge.plus")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    private func addNewItem() {
        let item = Item(name: "新物品", book: book)
        modelContext.insert(item)
        addItem(item)
    }

    private func addItem(_ item: Item) {
        modelContext.insert(CharacterItem(character: character, item: item))
    }
}

private struct ItemRow: View {
    @Bindable var characterItem: CharacterItem
    let book: Book
    let onOpenItem: ((Item) -> Void)?
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if let item = characterItem.item {
                    @Bindable var item = item
                    TextField("物品名稱", text: $item.name).textFieldStyle(.roundedBorder)
                    if let onOpenItem {
                        Button { onOpenItem(item) } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("前往物品設定")
                    }
                }
                Stepper("數量 \(characterItem.quantity)", value: $characterItem.quantity, in: 0...9999).frame(width: 130)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            if let item = characterItem.item, !item.itemDescription.isEmpty {
                Text(item.itemDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct CharacterRelationshipSectionView: View {
    let character: Character
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Query private var allRelationships: [CharacterRelationship]
    @Query(sort: \Character.sortOrder) private var allCharacters: [Character]
    @State private var selectedTargetID: UUID?

    private var relationships: [CharacterRelationship] { allRelationships.filter { $0.sourceCharacter?.id == character.id } }
    private var targets: [Character] { allCharacters.filter { $0.book?.id == book.id && $0.id != character.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if relationships.isEmpty {
                CharacterSectionEmptyState(title: "尚無一般關係", detail: "關係為單向，同兩人可建立多種關係。")
            } else {
                ForEach(relationships) { relationship in RelationshipRow(relationship: relationship, book: book, onDelete: { modelContext.delete(relationship) }) }
            }
            HStack {
                Picker("目標角色", selection: $selectedTargetID) {
                    Text("選擇角色").tag(Optional<UUID>.none)
                    ForEach(targets) { Text($0.realName.isEmpty ? "未命名" : $0.realName).tag(Optional($0.id)) }
                }
                Button("新增關係", action: addRelationship).disabled(selectedTargetID == nil)
            }
        }
    }

    private func addRelationship() {
        guard let selectedTargetID, let target = targets.first(where: { $0.id == selectedTargetID }) else { return }
        guard !allRelationships.contains(where: {
            $0.sourceCharacter?.id == character.id && $0.targetCharacter?.id == target.id
        }) else { return }
        let relationship = CharacterRelationship(type: "朋友", sourceCharacter: character, targetCharacter: target)
        let history = RelationshipHistory(type: "朋友", relationship: relationship)
        relationship.history.append(history)
        modelContext.insert(relationship)
        modelContext.insert(history)
        self.selectedTargetID = nil
    }
}

private struct RelationshipRow: View {
    @Bindable var relationship: CharacterRelationship
    let book: Book
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(relationship.targetCharacter?.realName ?? "未知角色").frame(minWidth: 80, alignment: .leading)
                TextField("關係類型", text: $relationship.type).textFieldStyle(.roundedBorder)
                TextField("備註", text: $relationship.note).textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            RelationshipHistoryEditor(relationship: relationship, book: book)
        }
        .onChange(of: relationship.type) { relationship.updatedAt = Date() }
        .onChange(of: relationship.note) { relationship.updatedAt = Date() }
    }
}

struct CharacterEventSectionView: View {
    let character: Character
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.sortOrder) private var allEvents: [Event]
    @Query(sort: \Character.sortOrder) private var allCharacters: [Character]

    private var events: [Event] {
        allEvents.filter { event in event.characters.contains { $0.id == character.id } }
    }
    private var bookCharacters: [Character] {
        allCharacters.filter { $0.book?.id == book.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if events.isEmpty {
                CharacterSectionEmptyState(title: "尚無事件", detail: "")
            } else {
                ForEach(events) { event in
                    CharacterEventRow(event: event, character: character, book: book, allCharacters: bookCharacters) {
                        modelContext.delete(event)
                    }
                }
            }
            Button(action: addEvent) {
                Label("新增事件", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func addEvent() {
        let event = Event(title: "新事件")
        event.characters = [character]
        event.sortOrder = (allEvents.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(event)
    }
}

private struct CharacterEventRow: View {
    @Bindable var event: Event
    let character: Character
    let book: Book
    let allCharacters: [Character]
    let onDelete: () -> Void

    private var relatedCharacters: [Character] {
        event.characters.filter { $0.book?.id == book.id }
    }
    private var availableCharacters: [Character] {
        let relatedIDs = Set(relatedCharacters.map(\.id))
        return allCharacters.filter { !relatedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField("事件標題", text: $event.title).textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            TextField("摘要", text: $event.detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                CharacterNodePicker(book: book, node: $event.node)
                Menu {
                    ForEach(availableCharacters) { candidate in
                        Button(candidate.realName.isEmpty ? "未命名角色" : candidate.realName) {
                            event.characters.append(candidate)
                        }
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .menuStyle(.borderlessButton)
            }
            if relatedCharacters.count > 1 {
                HStack(spacing: 6) {
                    ForEach(relatedCharacters) { related in
                        if related.id == character.id {
                            Text(related.realName.isEmpty ? "未命名角色" : related.realName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                event.characters.removeAll { $0.id == related.id }
                            } label: {
                                Label(related.realName.isEmpty ? "未命名角色" : related.realName, systemImage: "xmark")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
