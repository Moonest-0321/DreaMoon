import SwiftUI
import SwiftData

@main
struct NovelWriterApp: App {
    
    // V4 uses a new store because the released V3 schema used live models.
    private static var storeURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
        return appSupportURL.appendingPathComponent("DreaMoon-v4.store")
    }

    private static var legacyV3StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("DreaMoon-v3.store")
    }

    private static var legacyV2StoreURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("DreaMoon.store")
    }

    private enum LegacyStoreSource {
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

        let schema = Schema(versionedSchema: NovelWriterSchemaV4.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("V4 SwiftData 容器載入失敗（DreaMoon-v4.store）: \(Self.errorDetails(error))")
        }
        do {
            try importLegacyStore(legacySource, into: container)
        } catch {
            fatalError("V3/V2 資料匯入 V4 失敗: \(Self.errorDetails(error))")
        }
        do {
            try V4DataBackfill.migrateLegacyPsychology(in: container.mainContext)
        } catch {
            fatalError("Psychology 舊資料轉換失敗: \(Self.errorDetails(error))")
        }
        return container
    }()

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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

@MainActor
enum V4DataBackfill {
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
