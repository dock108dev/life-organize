import Foundation

struct SeedScenarioRecordIDs {
    let chatMessages: Set<String>
    let extractionRuns: Set<String>
    let things: Set<String>
    let events: Set<String>
    let rules: Set<String>
    let notes: Set<String>
    let ledgerReviewItems: Set<String>
    let entityLinks: Set<String>

    private let duplicateErrors: [String]

    init(records: ExportRecords) {
        let chatMessageIDs = records.chatMessages.map(\.id)
        let extractionRunIDs = records.extractionRuns.map(\.id)
        let thingIDs = records.things.map(\.id)
        let eventIDs = records.events.map(\.id)
        let ruleIDs = records.rules.map(\.id)
        let noteIDs = records.notes.map(\.id)
        let reviewItemIDs = records.ledgerReviewItems.map(\.id)
        let entityLinkIDs = records.entityLinks.map(\.id)

        chatMessages = Set(chatMessageIDs)
        extractionRuns = Set(extractionRunIDs)
        things = Set(thingIDs)
        events = Set(eventIDs)
        rules = Set(ruleIDs)
        notes = Set(noteIDs)
        ledgerReviewItems = Set(reviewItemIDs)
        entityLinks = Set(entityLinkIDs)

        duplicateErrors = [
            Self.duplicateError(chatMessageIDs, label: "chatMessages"),
            Self.duplicateError(extractionRunIDs, label: "extractionRuns"),
            Self.duplicateError(thingIDs, label: "things"),
            Self.duplicateError(eventIDs, label: "events"),
            Self.duplicateError(ruleIDs, label: "rules"),
            Self.duplicateError(noteIDs, label: "notes"),
            Self.duplicateError(reviewItemIDs, label: "ledgerReviewItems"),
            Self.duplicateError(entityLinkIDs, label: "entityLinks"),
            Self.duplicateError(
                chatMessageIDs + extractionRunIDs + thingIDs + eventIDs + ruleIDs + noteIDs + reviewItemIDs + entityLinkIDs,
                label: "records"
            )
        ].compactMap { $0 }
    }

    func validateDuplicates() throws {
        if let duplicateError = duplicateErrors.first {
            throw SeedScenarioLoaderError.invalidFixture(duplicateError)
        }
    }

    func entityIDs(for type: String) -> Set<String> {
        switch type {
        case "chatMessage":
            chatMessages
        case "extractionRun":
            extractionRuns
        case "thing":
            things
        case "event":
            events
        case "rule":
            rules
        case "note":
            notes
        default:
            []
        }
    }

    func reviewItemEntityIDs(for type: String) -> Set<String> {
        switch type {
        case "chat_message":
            chatMessages
        case "thing":
            things
        case "event":
            events
        case "rule":
            rules
        case "none":
            []
        default:
            []
        }
    }

    private static func duplicateError(_ ids: [String], label: String) -> String? {
        let duplicates = Dictionary(grouping: ids, by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map(\.key)
            .sorted()
        guard let duplicate = duplicates.first else { return nil }
        return "\(label) contains duplicate id \(duplicate)."
    }
}
