import Foundation
import SwiftData

@MainActor
struct LocalDataClearService {
    let modelContext: ModelContext

    func clearLedgerData() throws {
        try deleteAll(EntityLink.self)
        try deleteAll(LedgerReviewItem.self)
        try deleteAll(ExtractionAttempt.self)
        try deleteAll(LedgerEvent.self)
        try deleteAll(LedgerRule.self)
        try deleteAll(LedgerNote.self)
        try deleteAll(Thing.self)
        try deleteAll(ChatMessage.self)
        try modelContext.save()
    }

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type) throws {
        let records = try modelContext.fetch(FetchDescriptor<T>())
        records.forEach(modelContext.delete)
    }
}
