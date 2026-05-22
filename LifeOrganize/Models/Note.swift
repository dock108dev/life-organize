import Foundation
import SwiftData

@Model
final class LedgerNote {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var sourceClientID: String?
    var sourceExtractionRunID: UUID?
    var sourceMessage: ChatMessage?

    @Relationship(deleteRule: .nullify)
    var linkedThings: [Thing]

    var body: String {
        get { text }
        set {
            text = newValue
            updatedAt = Date()
        }
    }

    var linkedThingIDs: [UUID] {
        linkedThings.map(\.id)
    }

    var sourceMessageID: UUID? {
        sourceMessage?.id
    }

    init(
        id: UUID = UUID(),
        body: String? = nil,
        text: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceClientID: String? = nil,
        sourceExtractionRunID: UUID? = nil,
        sourceMessage: ChatMessage? = nil,
        linkedThings: [Thing] = []
    ) {
        self.id = id
        self.text = text ?? body ?? ""
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceClientID = sourceClientID
        self.sourceExtractionRunID = sourceExtractionRunID
        self.sourceMessage = sourceMessage
        self.linkedThings = linkedThings
    }
}
