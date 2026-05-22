import SwiftData

enum LifeOrganizeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            LifeOrganizeSchemaV1.self,
            LifeOrganizeSchemaV2.self,
            LifeOrganizeSchemaV3.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1ToV2,
            migrateV2ToV3,
        ]
    }

    static let migrateV1ToV2 = MigrationStage.lightweight(
        fromVersion: LifeOrganizeSchemaV1.self,
        toVersion: LifeOrganizeSchemaV2.self
    )

    static let migrateV2ToV3 = MigrationStage.lightweight(
        fromVersion: LifeOrganizeSchemaV2.self,
        toVersion: LifeOrganizeSchemaV3.self
    )
}
