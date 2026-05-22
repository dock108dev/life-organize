import SwiftUI

struct RelatedContextRowPresentation: Equatable {
    let primaryText: String
    let secondaryLines: [LedgerRowLine]
    let badge: LedgerBadgePresentation
    let badgeText: String
    let badgeTone: LedgerTone

    init(result: RelationshipTraversalResult, records: RelationshipTraversalRecords) {
        primaryText = Self.primaryText(for: result.target, records: records)
        secondaryLines = Self.secondaryLines(for: result, records: records)
        badge = LedgerBadgePresentation.relatedCategory(for: result.target.type)
        badgeText = badge.label
        badgeTone = badge.tone
    }

    private static func primaryText(for target: RelationshipNode, records: RelationshipTraversalRecords) -> String {
        let title = records.title(for: target).nilIfEmpty
        switch target {
        case .chatMessage:
            return title ?? "Message"
        case .event:
            return title ?? "Untitled event"
        case .note:
            return title.map { LedgerDisplayFormatting.noteTitle(for: $0) } ?? "Note"
        case .rule:
            return title ?? "Untitled reminder"
        case .thing:
            return title ?? "Thing"
        }
    }

    private static func secondaryLines(
        for result: RelationshipTraversalResult,
        records: RelationshipTraversalRecords
    ) -> [LedgerRowLine] {
        var lines = [LedgerRowLine(text: result.sourceLabel)]
        let date = records.sortDate(for: result.target)
        if date > .distantPast {
            lines.append(LedgerRowLine(text: DateFormatting.shortDate.string(from: date)))
        }
        return lines
    }

}

struct RelatedContextRows: View {
    let results: [RelationshipTraversalResult]
    let records: RelationshipTraversalRecords
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let messages: [ChatMessage]

    var body: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
            NavigationLink {
                RelatedContextDestinationView(
                    target: result.target,
                    things: things,
                    events: events,
                    rules: rules,
                    notes: notes,
                    messages: messages
                )
            } label: {
                RelatedContextRow(presentation: RelatedContextRowPresentation(result: result, records: records))
            }
            .buttonStyle(.plain)

            if index < results.count - 1 {
                Divider()
            }
        }
    }
}

struct RelatedContextRow: View {
    let presentation: RelatedContextRowPresentation

    var body: some View {
        LedgerRow(
            primary: presentation.primaryText,
            secondary: presentation.secondaryLines,
            density: LedgerSurfaceDensity.detailSummary.rowDensity
        ) {
            LedgerBadgePill(badge: presentation.badge, size: .small)
        }
    }
}

struct RelatedContextDestinationView: View {
    let target: RelationshipNode
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let messages: [ChatMessage]

    var body: some View {
        switch target {
        case .chatMessage(let id):
            if let message = messages.first(where: { $0.id == id }) {
                ChatMessageContextView(message: message)
            } else {
                MissingSearchRecordView()
            }
        case .event(let id):
            if let event = events.first(where: { $0.id == id }) {
                EventDetailView(event: event)
            } else {
                MissingSearchRecordView()
            }
        case .note(let id):
            if let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note)
            } else {
                MissingSearchRecordView()
            }
        case .rule(let id):
            if let rule = rules.first(where: { $0.id == id }) {
                RuleDetailView(rule: rule)
            } else {
                MissingSearchRecordView()
            }
        case .thing(let id):
            if let thing = things.first(where: { $0.id == id }) {
                ThingDetailView(thing: thing)
            } else {
                MissingSearchRecordView()
            }
        }
    }
}
