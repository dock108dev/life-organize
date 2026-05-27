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

    func correctionTargetEvent(
        for extractedEvent: ExtractedEvent,
        thing: Thing?,
        sourceMessage: ChatMessage
    ) throws -> LedgerEvent? {
        guard isCorrectionMessage(sourceMessage.text) else { return nil }
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        let sourceCreatedAt = sourceMessage.createdAt
        let candidates = events.filter { event in
            guard event.sourceMessage?.id != sourceMessage.id,
                  event.createdAt <= sourceCreatedAt,
                  sourceCreatedAt.timeIntervalSince(event.createdAt) <= 48 * 60 * 60 else {
                return false
            }
            if let thing {
                return event.thing?.id == thing.id || eventTitleMatchesThing(event, thing: thing)
            }
            return eventTitleMatches(event, extractedEvent: extractedEvent)
        }
        return candidates.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }.first
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

    func updatedExistingRecord(in attempt: ExtractionAttempt, sourceMessage: ChatMessage) throws -> Bool {
        guard isCorrectionMessage(sourceMessage.text), !attempt.createdEventIDs.isEmpty else { return false }
        let eventIDs = Set(attempt.createdEventIDs)
        return try modelContext.fetch(FetchDescriptor<LedgerEvent>()).contains {
            eventIDs.contains($0.id) && $0.sourceMessage?.id != sourceMessage.id
        }
    }

    @discardableResult
    func appendUnique(_ id: UUID, to ids: inout [UUID]) -> Bool {
        guard !ids.contains(id) else { return false }
        ids.append(id)
        return true
    }

    private func isCorrectionMessage(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return [
            "whoops",
            "oops",
            "correction",
            "actually",
            "i meant",
            "meant to say",
            "no wait"
        ].contains { normalized == $0 || normalized.hasPrefix("\($0) ") }
    }

    private func eventTitleMatchesThing(_ event: LedgerEvent, thing: Thing) -> Bool {
        let targetKeys = LedgerTextMatching.thingKeys(for: thing)
        let targetTokenKey = thing.normalizedKey.nilIfEmpty ?? ThingNormalizer.normalizeKey(thing.name)
        let eventKeys = [
            event.title,
            event.rawText,
            event.thing?.name ?? ""
        ].map(ThingNormalizer.normalizeKey)
        return eventKeys.contains { key in
            LedgerTextMatching.textMatches(
                key,
                targetKeys: targetKeys,
                targetTokens: LedgerTextMatching.tokens(in: targetTokenKey)
            )
        }
    }

    private func eventTitleMatches(_ event: LedgerEvent, extractedEvent: ExtractedEvent) -> Bool {
        let sourceKey = ThingNormalizer.normalizeKey(extractedEvent.title)
        let targetKeys = Set([sourceKey].filter { !$0.isEmpty })
        let targetTokens = LedgerTextMatching.tokens(in: sourceKey)
        return [event.title, event.rawText].map(ThingNormalizer.normalizeKey).contains { key in
            LedgerTextMatching.textMatches(key, targetKeys: targetKeys, targetTokens: targetTokens)
        }
    }
}
