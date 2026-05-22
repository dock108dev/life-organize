import Foundation
import SwiftData

@MainActor
extension ChatSendService {
    func existingEvent(for sourceMessage: ChatMessage, clientID: String) throws -> LedgerEvent? {
        try modelContext.fetch(FetchDescriptor<LedgerEvent>()).first {
            $0.sourceMessage?.id == sourceMessage.id && $0.sourceClientID == clientID
        }
    }

    func existingRule(for sourceMessage: ChatMessage, clientID: String) throws -> LedgerRule? {
        try modelContext.fetch(FetchDescriptor<LedgerRule>()).first {
            $0.sourceMessage?.id == sourceMessage.id && $0.sourceClientID == clientID
        }
    }

    func existingNote(for sourceMessage: ChatMessage, clientID: String) throws -> LedgerNote? {
        try modelContext.fetch(FetchDescriptor<LedgerNote>()).first {
            $0.sourceMessage?.id == sourceMessage.id && $0.sourceClientID == clientID
        }
    }

    func metadataEntries(from extractedMetadata: [ExtractedEventMetadata]) -> [LedgerEventMetadataEntry] {
        extractedMetadata.compactMap {
            LedgerEventMetadataValidation.normalizedExtractionEntry(
                keyRawValue: $0.key,
                valueKindRawValue: $0.valueKind,
                stringValue: $0.stringValue,
                numberValue: $0.numberValue,
                dateValue: $0.dateValue,
                boolValue: $0.boolValue,
                unit: $0.unit,
                sourceText: $0.sourceText
            )
        }
    }

    func hasCreatedEntities(_ attempt: ExtractionAttempt) -> Bool {
        !attempt.createdEventIDs.isEmpty
            || !attempt.createdRuleIDs.isEmpty
            || !attempt.createdNoteIDs.isEmpty
            || !attempt.createdThingIDs.isEmpty
    }

    @discardableResult
    func appendUnique(_ id: UUID, to ids: inout [UUID]) -> Bool {
        guard !ids.contains(id) else { return false }
        ids.append(id)
        return true
    }
}
