import SwiftUI
import SwiftData

@main
struct SailuneApp: App {
    private enum StartupState {
        case ready(ModelContainer, ItemCopyStore, AbilityProgressStore, StoryPlanningStore)
        case failed(String)
    }

    private struct StartupStageError: LocalizedError {
        let stage: String
        let underlying: Error

        var errorDescription: String? {
            "\(stage)：\(SailuneApp.errorDetails(underlying))"
        }
    }
    
    // V5 uses a separate store so schema failures never mutate an older store.
    private static var storeURL: URL {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let overridePath = environment["SAILUNE_TEST_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }
        #endif
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
        return appSupportURL.appendingPathComponent("Sailune-v5.store")
    }

    private static var legacyV3StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("Sailune-v3.store")
    }

    private static var legacyV2StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("Sailune.store")
    }

    /// Copy data deliberately lives outside the released V5 store. The name is
    /// derived from an override during tests so test and production data can
    /// never be mixed.
    private static var itemCopyStoreURL: URL {
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        return storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)-item-copies.store")
    }

    private static var itemCopyLevelSelectionStoreURL: URL {
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        return storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)-item-copy-level-selections.store")
    }
    private static var abilityProgressStoreURL: URL { storeURL.deletingLastPathComponent().appendingPathComponent("\(storeURL.deletingPathExtension().lastPathComponent)-ability-progress.store") }
    private static var storyPlanningStoreURL: URL { storeURL.deletingLastPathComponent().appendingPathComponent("\(storeURL.deletingPathExtension().lastPathComponent)-story-planning.store") }

    private enum LegacyStoreSource {
        case v3(ModelContainer)
        case v2(ModelContainer)
    }
    
    private let startupState: StartupState

    init() {
        do {
            let (container, copyStore, abilityStore, planningStore) = try Self.makeModelContainer()
            startupState = .ready(container, copyStore, abilityStore, planningStore)
        } catch {
            startupState = .failed(error.localizedDescription)
        }
    }

    private static func makeModelContainer() throws -> (ModelContainer, ItemCopyStore, AbilityProgressStore, StoryPlanningStore) {
        // Open the released schema before V5. SwiftData caches model metadata
        // for shared top-level model types, so reversing this order makes it
        // attempt to open the V3 store with V5's expanded model graph.
        let legacySource: LegacyStoreSource?
        do {
            legacySource = try openLegacyStoreIfPresent()
        } catch {
            throw StartupStageError(stage: "舊資料庫載入失敗", underlying: error)
        }

        let mainSchema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        let mainConfig = ModelConfiguration(schema: mainSchema, url: storeURL)
        
        let container: ModelContainer
        do {
            container = try ModelContainer(for: mainSchema, configurations: [mainConfig])
        } catch {
            throw StartupStageError(stage: "V5 主資料庫載入失敗（Sailune-v5.store）", underlying: error)
        }
        do {
            try importLegacyStore(legacySource, into: container)
        } catch {
            throw StartupStageError(stage: "舊資料匯入 V5 失敗", underlying: error)
        }
        do {
            try PersistentStoreRepair.run(in: container.mainContext)
        } catch {
            throw StartupStageError(stage: "書籍懸空資料修復失敗", underlying: error)
        }
        do {
            try V4DataBackfill.migrateLegacyPsychology(in: container.mainContext)
        } catch {
            throw StartupStageError(stage: "心理資料轉換失敗", underlying: error)
        }
        do {
            try V4DataBackfill.migrateLegacyItemHistories(in: container.mainContext)
        } catch {
            throw StartupStageError(stage: "物品舊歷史轉換失敗", underlying: error)
        }
        do {
            try V5DataBackfill.removeOrphanedItemLevels(in: container.mainContext)
        } catch {
            throw StartupStageError(stage: "物品等級資料修復失敗", underlying: error)
        }
        let copyStore: ItemCopyStore
        do {
            let copySchema = Schema(versionedSchema: ItemCopySchemaV1.self)
            let copyConfig = ModelConfiguration(schema: copySchema, url: itemCopyStoreURL)
            let copyContainer = try ModelContainer(for: copySchema, configurations: [copyConfig])
            let selectionSchema = Schema(versionedSchema: ItemCopyLevelSelectionSchemaV1.self)
            let selectionConfig = ModelConfiguration(
                schema: selectionSchema,
                url: itemCopyLevelSelectionStoreURL
            )
            let selectionContainer = try ModelContainer(
                for: selectionSchema,
                configurations: [selectionConfig]
            )
            try V6ItemCopyBackfill.run(
                source: container.mainContext,
                destination: copyContainer.mainContext
            )
            try ItemCopyLevelSelectionRepair.run(
                source: container.mainContext,
                copyContext: copyContainer.mainContext,
                selectionContext: selectionContainer.mainContext
            )
            copyStore = try ItemCopyStore(
                container: copyContainer,
                levelSelectionContainer: selectionContainer
            )
        } catch {
            throw StartupStageError(stage: "獨立物品副本或當下等級資料庫載入失敗", underlying: error)
        }
        do {
            try V4DataBackfill.ensureInitialWritingStructure(in: container.mainContext)
        } catch {
            throw StartupStageError(stage: "初始寫作結構補齊失敗", underlying: error)
        }
        let abilityStore: AbilityProgressStore
        do {
            let schema = Schema(versionedSchema: AbilityProgressSchemaV1.self)
            let abilityContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: abilityProgressStoreURL)])
            abilityStore = try AbilityProgressStore(container: abilityContainer)
            abilityStore.migrateLegacy(try container.mainContext.fetch(FetchDescriptor<CharacterAbility>()))
        } catch { throw StartupStageError(stage: "能力進度資料庫載入失敗", underlying: error) }
        let planningStore: StoryPlanningStore
        do {
            let schema = Schema(versionedSchema: StoryPlanningSchemaV4.self)
            let planningContainer = try ModelContainer(
                for: schema,
                migrationPlan: StoryPlanningMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: storyPlanningStoreURL)]
            )
            planningStore = try StoryPlanningStore(container: planningContainer)
        } catch { throw StartupStageError(stage: "故事規劃資料庫載入失敗", underlying: error) }
        return (container, copyStore, abilityStore, planningStore)
    }

    private static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription); userInfo=\(nsError.userInfo)"
    }

    private static func openLegacyStoreIfPresent() throws -> LegacyStoreSource? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: legacyV3StoreURL.path) {
            let schema = Schema(versionedSchema: NovelWriterSchemaV3.self)
            let config = ModelConfiguration(schema: schema, url: legacyV3StoreURL)
            return .v3(try ModelContainer(for: schema, configurations: [config]))
        }
        guard fileManager.fileExists(atPath: legacyV2StoreURL.path) else { return nil }

        let legacySchema = Schema(versionedSchema: NovelWriterSchemaV2.self)
        let legacyConfig = ModelConfiguration(schema: legacySchema, url: legacyV2StoreURL)
        return .v2(try ModelContainer(for: legacySchema, configurations: [legacyConfig]))
    }

    private static func importLegacyStore(_ source: LegacyStoreSource?, into destination: ModelContainer) throws {
        guard source != nil else { return }

        let importContext = ModelContext(destination)
        importContext.autosaveEnabled = false

        switch source {
        case .v3(let container):
            try LegacyV3StoreImporter.importIfNeeded(from: container.mainContext, to: importContext)
        case .v2(let container):
            try LegacyV2StoreImporter.importIfNeeded(from: container.mainContext, to: importContext)
        case nil:
            break
        }
    }
    
    var body: some Scene {
        WindowGroup {
            switch startupState {
            case .ready(let container, let copyStore, let abilityStore, let planningStore):
                SailuneRootView(container: container, copyStore: copyStore, abilityStore: abilityStore, planningStore: planningStore)
            case .failed(let message):
                DatabaseStartupFailureView(message: message)
            }
        }
    }
}

private struct SailuneRootView: View {
    let container: ModelContainer
    @Bindable var copyStore: ItemCopyStore
    @Bindable var abilityStore: AbilityProgressStore
    @Bindable var planningStore: StoryPlanningStore

    var body: some View {
        ContentView()
            .modelContainer(container)
            .environment(copyStore)
            .environment(abilityStore)
            .environment(planningStore)
            .alert("物品副本無法儲存", isPresented: persistenceErrorBinding) {
                Button("好") { copyStore.clearPersistenceError() }
            } message: {
                Text(copyStore.persistenceErrorMessage ?? "未知錯誤")
            }
    }

    private var persistenceErrorBinding: Binding<Bool> {
        Binding(
            get: { copyStore.persistenceErrorMessage != nil },
            set: { if !$0 { copyStore.clearPersistenceError() } }
        )
    }
}

private struct DatabaseStartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("資料庫無法開啟").font(.title2.bold())
            Text("原始資料庫不會被刪除或覆寫。請保留此畫面中的錯誤資訊，以便進行修復。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 180)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 330)
    }
}

@MainActor
enum V5DataBackfill {
    /// ItemLevel has no database relationship by design, so remove only rows
    /// whose parent Item no longer exists. This is idempotent and preserves all
    /// valid level data through future launches.
    static func removeOrphanedItemLevels(in context: ModelContext) throws {
        let itemIDs = Set(try context.fetch(FetchDescriptor<Item>()).map(\.id))
        let levels = try context.fetch(FetchDescriptor<ItemLevel>())
        let orphans = levels.filter { !itemIDs.contains($0.itemID) }
        for level in orphans { context.delete(level) }
        let invalidHoldings = try context.fetch(FetchDescriptor<CharacterItem>()).filter { $0.quantity < 1 }
        for holding in invalidHoldings { holding.quantity = 1 }
        let unnamedItems = try context.fetch(FetchDescriptor<Item>()).filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for item in unnamedItems { item.name = "未命名物品" }
        let orphanIDs = Set(orphans.map(\.id))
        let unnamedLevels = levels.filter {
            !orphanIDs.contains($0.id) && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for level in unnamedLevels { level.name = "未命名等級" }
        let emptyHistories = try context.fetch(FetchDescriptor<ItemHistory>()).filter {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for history in emptyHistories { history.content = "未填寫描述" }
        if !orphans.isEmpty || !invalidHoldings.isEmpty || !unnamedItems.isEmpty || !unnamedLevels.isEmpty || !emptyHistories.isEmpty {
            try context.save()
        }
    }
}

@MainActor
enum V4DataBackfill {
    /// 舊版歷史附著在每一個持有關係。首次開啟新版時把它們收攏至物品，
    /// 同時保留原始紀錄，避免任何既有資料遺失。
    static func migrateLegacyItemHistories(in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<Item>())
        var didChange = false
        for item in items where item.histories.isEmpty {
            let legacy = item.characterItems
                .flatMap { relation in relation.history.map { (relation, $0) } }
                .sorted { $0.1.sortOrder < $1.1.sortOrder }
            for (index, entry) in legacy.enumerated() {
                let history = ItemHistory(
                    content: entry.1.content,
                    sortOrder: index,
                    node: entry.1.node,
                    item: item,
                    relatedCharacters: entry.0.character.map { [$0] } ?? []
                )
                item.histories.append(history)
                context.insert(history)
                didChange = true
            }
        }
        if didChange { try context.save() }
    }

    static func ensureInitialWritingStructure(in context: ModelContext) throws {
        let books = try context.fetch(FetchDescriptor<Book>())
        var didChange = false
        for book in books {
            if book.volumes.isEmpty {
                let volume = Volume(title: "第一卷", sortOrder: 0, book: book)
                let section = Section(title: "第一節", sortOrder: 0, volume: volume)
                volume.sections.append(section)
                book.volumes.append(volume)
                didChange = true
            } else if book.volumes.allSatisfy({ $0.sections.isEmpty }) {
                let firstVolume = book.volumes.min { $0.sortOrder < $1.sortOrder }!
                let section = Section(title: "第一節", sortOrder: 0, volume: firstVolume)
                firstVolume.sections.append(section)
                didChange = true
            }
        }
        if didChange { try context.save() }
    }

    static func migrateLegacyPsychology(in context: ModelContext) throws {
        let characters = try context.fetch(FetchDescriptor<Character>())
        var didChange = false

        for character in characters {
            if let personality = character.personality?.trimmingCharacters(in: .whitespacesAndNewlines), !personality.isEmpty {
                context.insert(CharacterPsychology(kind: .personality, content: personality, character: character))
                character.personality = nil
                didChange = true
            }
            if let principles = character.principles?.trimmingCharacters(in: .whitespacesAndNewlines), !principles.isEmpty {
                context.insert(CharacterPsychology(kind: .value, content: principles, character: character))
                character.principles = nil
                didChange = true
            }
        }

        if didChange { try context.save() }
    }
}
