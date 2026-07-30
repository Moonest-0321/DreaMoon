import SwiftUI
import SwiftData

@main
struct NovelWriterApp: App {
    
    // 1. 明確指定資料庫存放路徑，方便我們後續進行備份與重置
    private static var storeURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
        return appSupportURL.appendingPathComponent("DreaMoon.store")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: NovelWriterSchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        
        do {
            // 嘗試正常啟動並進行遷移
            return try ModelContainer(
                for: schema,
                migrationPlan: NovelWriterMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            print("❌ [SwiftData] 資料庫遷移失敗: \(error)")
            // 啟動自癒機制：備份舊檔案，然後重置
            return Self.rescueAndResetDatabase(schema: schema, config: config)
        }
    }()
    
    // 🛡️ 自癒機制：備份並重置
    private static func rescueAndResetDatabase(schema: Schema, config: ModelConfiguration) -> ModelContainer {
        let fileManager = FileManager.default
        let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent("DreaMoon.store.backup-\(Int(Date().timeIntervalSince1970))")
        
        // 1. 備份損壞/無法遷移的舊資料庫
        try? fileManager.copyItem(at: storeURL, to: backupURL)
        print("⚠️ [SwiftData] 已將無法遷移的舊資料庫備份至: \(backupURL.lastPathComponent)")
        
        // 2. 刪除舊資料庫及其關聯的 WAL/SHM 暫存檔
        try? fileManager.removeItem(at: storeURL)
        try? fileManager.removeItem(at: storeURL.appendingPathExtension("store-wal"))
        try? fileManager.removeItem(at: storeURL.appendingPathExtension("store-shm"))
        
        // 3. 重新建立一個全新的乾淨資料庫
        do {
            print("✅ [SwiftData] 已重建全新資料庫，App 繼續運行...")
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("連重置都失敗，無法挽救: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
