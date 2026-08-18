import SwiftUI
import SwiftData

@main
struct SailuneApp: App {
    
    // V4 uses a new store because the released V3 schema used live models.
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

    private static var legacyV4StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("Sailune-v4.store")
    }

    private static var legacyV3StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("Sailune-v3.store")
    }

    private static var legacyV2StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("Sailune.store")
    }

    private enum LegacyStoreSource {
        case v4(ModelContainer)
        case v3(ModelContainer)
        case v2(ModelContainer)
    }
    
    var sharedModelContainer: ModelContainer = {
        // Open the released schema before V4. SwiftData caches model metadata
        // for shared top-level model types, so reversing this order makes it
        // attempt to open the V3 store with V4's expanded model graph.
        let legacySource: LegacyStoreSource?
        do {
            legacySource = try openLegacyStoreIfPresent()
        } catch {
            fatalError("V3/V2 舊資料庫載入失敗: \(Self.errorDetails(error))")
        }

        let schema = Schema(versionedSchema: NovelWriterSchemaV5.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("V5 SwiftData 容器載入失敗（Sailune-v5.store）: \(Self.errorDetails(error))")
        }
        do {
            try importLegacyStore(legacySource, into: container)
        } catch {
            fatalError("舊資料匯入 V5 失敗: \(Self.errorDetails(error))")
        }
        do {
            try PersistentStoreRepair.run(in: container.mainContext)
        } catch {
            fatalError("書籍懸空資料修復失敗: \(Self.errorDetails(error))")
        }
        do {
            try V4DataBackfill.migrateLegacyPsychology(in: container.mainContext)
        } catch {
            fatalError("Psychology 舊資料轉換失敗: \(Self.errorDetails(error))")
        }
        do {
            try V4DataBackfill.migrateLegacyItemHistories(in: container.mainContext)
        } catch {
            fatalError("物品舊歷史轉換失敗: \(Self.errorDetails(error))")
        }
        do {
            try V5DataBackfill.removeOrphanedItemLevels(in: container.mainContext)
        } catch {
            fatalError("物品等級資料修復失敗: \(Self.errorDetails(error))")
        }
        do {
            try V4DataBackfill.ensureInitialWritingStructure(in: container.mainContext)
        } catch {
            fatalError("初始寫作結構補齊失敗: \(Self.errorDetails(error))")
        }
        return container
    }()

    private static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription); userInfo=\(nsError.userInfo)"
    }

    private static func openLegacyStoreIfPresent() throws -> LegacyStoreSource? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: legacyV4StoreURL.path) {
            let schema = Schema(versionedSchema: NovelWriterSchemaV4.self)
            let config = ModelConfiguration(schema: schema, url: legacyV4StoreURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            if try !container.mainContext.fetch(FetchDescriptor<Book>()).isEmpty {
                return .v4(container)
            }
        }
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
        case .v4(let container):
            try LegacyV4StoreImporter.importIfNeeded(from: container.mainContext, to: importContext)
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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
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
        guard !orphans.isEmpty else { return }
        for level in orphans { context.delete(level) }
        try context.save()
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
