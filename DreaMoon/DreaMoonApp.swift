import SwiftUI
import SwiftData

@main
struct NovelWriterApp: App {
    
    // V3 uses a new store because the original V2 store predates versioned schemas.
    private static var storeURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
        return appSupportURL.appendingPathComponent("DreaMoon-v3.store")
    }

    private static var legacyStoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("DreaMoon.store")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: NovelWriterSchemaV3.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        
        do {
            // 嘗試正常啟動並進行遷移
            let container = try ModelContainer(
                for: schema,
                migrationPlan: NovelWriterMigrationPlan.self,
                configurations: [config]
            )
            try importLegacyV2StoreIfNeeded(into: container)
            return container
        } catch {
            fatalError("SwiftData 資料庫遷移失敗，請新增下一版 VersionedSchema 與 MigrationStage，不要刪除資料庫: \(error)")
        }
    }()

    private static func importLegacyV2StoreIfNeeded(into destination: ModelContainer) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else { return }

        let legacySchema = Schema(versionedSchema: NovelWriterSchemaV2.self)
        let legacyConfig = ModelConfiguration(schema: legacySchema, url: legacyStoreURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: [legacyConfig])
        try LegacyV2StoreImporter.importIfNeeded(
            from: legacyContainer.mainContext,
            to: destination.mainContext
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
