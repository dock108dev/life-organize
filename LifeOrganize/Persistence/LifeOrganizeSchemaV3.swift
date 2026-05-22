import SwiftData

enum LifeOrganizeSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            ChatMessage.self,
            ExtractionAttempt.self,
            EntityLink.self,
            Thing.self,
            LedgerEvent.self,
            LedgerRule.self,
            LedgerNote.self,
            LedgerReviewItem.self,
        ]
    }
}
