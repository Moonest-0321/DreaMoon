import Foundation
import SwiftData

// MARK: - V1 Schema (最初版本：Book, Volume, Section)
enum NovelWriterSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            Volume.self,
            Section.self
        ]
    }
}

// MARK: - V2.0 Schema (目前最新版本：包含 AuthorProfile, Character, KinshipRelation)
enum NovelWriterSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            Volume.self,
            Section.self,
            AuthorProfile.self,
            Character.self,
            KinshipRelation.self
        ]
    }
}

// MARK: - 遷移計畫 (Migration Plan)
enum NovelWriterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            NovelWriterSchemaV1.self,
            NovelWriterSchemaV2.self
        ]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    // 從 V1 直接輕量遷移至 V2.0
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: NovelWriterSchemaV1.self,
        toVersion: NovelWriterSchemaV2.self
    )
}
