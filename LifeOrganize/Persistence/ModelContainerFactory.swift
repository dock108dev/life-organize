import Foundation
import SwiftData

enum ModelContainerFactory {
    enum Configuration {
        case standard
        case inMemory
        case store(url: URL)
    }

    static let modelTypeNames = Set(V1ScopeContract.activePersistenceModels.map(\.rawValue))

    static func make(inMemory: Bool = false, storeURL: URL? = nil) -> ModelContainer {
        make(configuration: storeURL.map(Configuration.store) ?? (inMemory ? .inMemory : .standard))
    }

    static func make(configuration requestedConfiguration: Configuration) -> ModelContainer {
        let schema = Schema(versionedSchema: LifeOrganizeSchemaV3.self)
        let configuration: ModelConfiguration
        switch requestedConfiguration {
        case .standard:
            configuration = ModelConfiguration(schema: schema)
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        case .store(let storeURL):
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: LifeOrganizeMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            preconditionFailure("Unable to create SwiftData model container: \(error)")
        }
    }
}
