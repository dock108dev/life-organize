import Foundation
import SwiftData

extension SeedScenarioRecordBuilder {
    func requiredChatMessage(id text: String) throws -> ChatMessage {
        let id = try uuid(text, field: "chatMessages.id")
        guard let message = try fetchChatMessage(id: id) else {
            throw SeedScenarioLoaderError.invalidFixture("chatMessages.id references missing record \(text).")
        }
        return message
    }

    func requiredThing(id text: String) throws -> Thing {
        let id = try uuid(text, field: "things.id")
        guard let thing = try fetchThing(id: id) else {
            throw SeedScenarioLoaderError.invalidFixture("things.id references missing record \(text).")
        }
        return thing
    }

    func uuid(_ text: String, field: String) throws -> UUID {
        guard let id = UUID(uuidString: text) else {
            throw SeedScenarioLoaderError.invalidFixture("\(field) must be a UUID string: \(text).")
        }
        return id
    }

    func fetchChatMessage(id: UUID) throws -> ChatMessage? {
        var descriptor = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchExtractionAttempt(id: UUID) throws -> ExtractionAttempt? {
        var descriptor = FetchDescriptor<ExtractionAttempt>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchThing(id: UUID) throws -> Thing? {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchEvent(id: UUID) throws -> LedgerEvent? {
        var descriptor = FetchDescriptor<LedgerEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchRule(id: UUID) throws -> LedgerRule? {
        var descriptor = FetchDescriptor<LedgerRule>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchNote(id: UUID) throws -> LedgerNote? {
        var descriptor = FetchDescriptor<LedgerNote>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchEntityLink(id: UUID) throws -> EntityLink? {
        var descriptor = FetchDescriptor<EntityLink>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchReviewItem(id: UUID) throws -> LedgerReviewItem? {
        var descriptor = FetchDescriptor<LedgerReviewItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
