import Foundation

extension LocalJSONExportService {
    func validate(_ records: ExportRecords) throws {
        let chatMessageIDs = Set(records.chatMessages.map(\.id))
        let extractionRunIDs = Set(records.extractionRuns.map(\.id))
        let thingIDs = Set(records.things.map(\.id))
        let eventIDs = Set(records.events.map(\.id))
        let ruleIDs = Set(records.rules.map(\.id))
        let noteIDs = Set(records.notes.map(\.id))

        try validateIdentifiers(
            chatMessageIDs
                .union(extractionRunIDs)
                .union(thingIDs)
                .union(eventIDs)
                .union(ruleIDs)
                .union(noteIDs)
        )
        try validateMessageRecords(records.chatMessages, extractionRunIDs: extractionRunIDs)
        try validateLedgerRecords(
            records,
            chatMessageIDs: chatMessageIDs,
            extractionRunIDs: extractionRunIDs,
            thingIDs: thingIDs,
            eventIDs: eventIDs,
            ruleIDs: ruleIDs,
            noteIDs: noteIDs
        )
    }

    private func validateMessageRecords(
        _ messages: [ChatMessageExport],
        extractionRunIDs: Set<String>
    ) throws {
        for message in messages {
            try validateReference(message.extractionRunId, existsIn: extractionRunIDs, label: "chat message extraction run")
            try validateReference(message.latestExtractionRunId, existsIn: extractionRunIDs, label: "latest chat message extraction run")
            for runID in message.extractionRunIds + message.successfulExtractionRunIds {
                try validateReference(runID, existsIn: extractionRunIDs, label: "chat message extraction run")
            }
        }
    }

    private func validateLedgerRecords(
        _ records: ExportRecords,
        chatMessageIDs: Set<String>,
        extractionRunIDs: Set<String>,
        thingIDs: Set<String>,
        eventIDs: Set<String>,
        ruleIDs: Set<String>,
        noteIDs: Set<String>
    ) throws {
        for event in records.events {
            try validateReference(event.thingId, existsIn: thingIDs, label: "event thing")
            try validateSource(event.source, chatMessageIDs: chatMessageIDs, extractionRunIDs: extractionRunIDs)
        }
        for rule in records.rules {
            try validateReference(rule.thingId, existsIn: thingIDs, label: "rule thing")
            try validateSource(rule.source, chatMessageIDs: chatMessageIDs, extractionRunIDs: extractionRunIDs)
        }
        for note in records.notes {
            for thingID in note.linkedThingIds {
                try validateReference(thingID, existsIn: thingIDs, label: "note thing")
            }
            try validateSource(note.source, chatMessageIDs: chatMessageIDs, extractionRunIDs: extractionRunIDs)
        }
        for thing in records.things {
            try validateSource(thing.source, chatMessageIDs: chatMessageIDs, extractionRunIDs: extractionRunIDs)
        }
        try validateEntityLinks(
            records.entityLinks,
            chatMessageIDs,
            extractionRunIDs,
            thingIDs,
            eventIDs,
            ruleIDs,
            noteIDs
        )
        try validateReviewItems(records.ledgerReviewItems, chatMessageIDs, thingIDs, eventIDs, ruleIDs)
    }

    private func validateEntityLinks(
        _ links: [EntityLinkExport],
        _ chatMessageIDs: Set<String>,
        _ extractionRunIDs: Set<String>,
        _ thingIDs: Set<String>,
        _ eventIDs: Set<String>,
        _ ruleIDs: Set<String>,
        _ noteIDs: Set<String>
    ) throws {
        for link in links {
            try validateEntityLinkEndpoint(
                type: link.fromEntityType,
                id: link.fromEntityId,
                ids: entityIDs(for: link.fromEntityType, chatMessageIDs, extractionRunIDs, thingIDs, eventIDs, ruleIDs, noteIDs)
            )
            try validateEntityLinkEndpoint(
                type: link.toEntityType,
                id: link.toEntityId,
                ids: entityIDs(for: link.toEntityType, chatMessageIDs, extractionRunIDs, thingIDs, eventIDs, ruleIDs, noteIDs)
            )
            try validateSource(link.source, chatMessageIDs: chatMessageIDs, extractionRunIDs: extractionRunIDs)
        }
    }

    private func validateReviewItems(
        _ items: [LedgerReviewItemExport],
        _ chatMessageIDs: Set<String>,
        _ thingIDs: Set<String>,
        _ eventIDs: Set<String>,
        _ ruleIDs: Set<String>
    ) throws {
        for item in items {
            if let targetID = item.targetId {
                try validateEndpoint(
                    type: item.targetType,
                    id: targetID,
                    ids: reviewItemEntityIDs(for: item.targetType, chatMessageIDs, thingIDs, eventIDs, ruleIDs)
                )
            }
            for evidence in item.evidence {
                try validateEndpoint(
                    type: evidence.sourceType,
                    id: evidence.sourceId,
                    ids: reviewItemEntityIDs(for: evidence.sourceType, chatMessageIDs, thingIDs, eventIDs, ruleIDs)
                )
            }
        }
    }

    private func validateIdentifiers(_ ids: Set<String>) throws {
        if ids.contains(where: { $0.isEmpty }) {
            throw LocalJSONExportError.invalidIdentifier("Export contains an empty record identifier.")
        }
    }

    private func validateReference(_ id: String?, existsIn ids: Set<String>, label: String) throws {
        guard let id else { return }
        if !ids.contains(id) {
            throw LocalJSONExportError.invalidReference("Export contains a missing \(label) reference.")
        }
    }

    private func validateSource(_ source: ExportSource, chatMessageIDs: Set<String>, extractionRunIDs: Set<String>) throws {
        try validateReference(source.chatMessageId, existsIn: chatMessageIDs, label: "source chat message")
        try validateReference(source.extractionRunId, existsIn: extractionRunIDs, label: "source extraction run")
    }

    private func validateEndpoint(type: String, id: String, ids: Set<String>) throws {
        if !ids.contains(id) {
            throw LocalJSONExportError.invalidReference("Export contains a missing \(type) reference.")
        }
    }

    private func validateEntityLinkEndpoint(type: String, id: String, ids: Set<String>) throws {
        if !ids.contains(id) {
            throw LocalJSONExportError.invalidReference("Export contains a missing \(type) entity link reference.")
        }
    }

    private func entityIDs(
        for type: String,
        _ chatMessageIDs: Set<String>,
        _ extractionRunIDs: Set<String>,
        _ thingIDs: Set<String>,
        _ eventIDs: Set<String>,
        _ ruleIDs: Set<String>,
        _ noteIDs: Set<String>
    ) -> Set<String> {
        switch type {
        case "chatMessage":
            chatMessageIDs
        case "extractionRun":
            extractionRunIDs
        case "thing":
            thingIDs
        case "event":
            eventIDs
        case "rule":
            ruleIDs
        case "note":
            noteIDs
        default:
            []
        }
    }

    private func reviewItemEntityIDs(
        for type: String,
        _ chatMessageIDs: Set<String>,
        _ thingIDs: Set<String>,
        _ eventIDs: Set<String>,
        _ ruleIDs: Set<String>
    ) -> Set<String> {
        switch type {
        case "chat_message":
            chatMessageIDs
        case "thing":
            thingIDs
        case "event":
            eventIDs
        case "rule":
            ruleIDs
        default:
            []
        }
    }
}
