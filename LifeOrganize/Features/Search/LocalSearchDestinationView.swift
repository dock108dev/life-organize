import SwiftData
import SwiftUI

struct LocalSearchDestinationView: View {
    let navigationTarget: LocalSearchNavigationTarget
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let messages: [ChatMessage]

    init(
        result: LocalSearchResult,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage]
    ) {
        self.init(
            target: result.navigationTarget,
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            messages: messages
        )
    }

    init(
        target: LocalSearchNavigationTarget,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage]
    ) {
        self.navigationTarget = target
        self.things = things
        self.events = events
        self.rules = rules
        self.notes = notes
        self.messages = messages
    }

    static func hasAvailableRecord(
        for target: LocalSearchNavigationTarget,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage]
    ) -> Bool {
        switch target {
        case .thingDetail(let id):
            return things.contains { $0.id == id }
        case .eventDetail(let id):
            return events.contains { $0.id == id }
        case .ruleDetail(let id):
            return rules.contains { $0.id == id }
        case .noteDetail(let id):
            return notes.contains { $0.id == id }
        case .chatMessage(let id):
            return messages.contains { $0.id == id }
        case .timelineSlice:
            return true
        }
    }

    var body: some View {
        switch navigationTarget {
        case .thingDetail(let id):
            if let thing = things.first(where: { $0.id == id }) {
                ThingDetailView(thing: thing)
            } else {
                MissingSearchRecordView()
            }
        case .eventDetail(let id):
            if let event = events.first(where: { $0.id == id }) {
                EventDetailView(event: event)
            } else {
                MissingSearchRecordView()
            }
        case .ruleDetail(let id):
            if let rule = rules.first(where: { $0.id == id }) {
                RuleDetailView(rule: rule)
            } else {
                MissingSearchRecordView()
            }
        case .noteDetail(let id):
            if let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note)
            } else {
                MissingSearchRecordView()
            }
        case .chatMessage(let id):
            if let message = messages.first(where: { $0.id == id }) {
                ChatMessageContextView(message: message)
            } else {
                MissingSearchRecordView()
            }
        case .timelineSlice(let descriptor):
            TimelineSliceReplayView(descriptor: descriptor)
        }
    }
}

struct MissingSearchRecordView: View {
    @Environment(\.dismiss) private var dismiss

    private let presentation = MissingSearchRecordPresentation()

    var body: some View {
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.systemImage)
        } description: {
            Text(presentation.description)
        } actions: {
            Button(presentation.actionTitle) {
                dismiss()
            }
        }
        .navigationTitle(presentation.navigationTitle)
    }
}

struct MissingSearchRecordPresentation: Equatable {
    let title = "Record unavailable"
    let systemImage = "exclamationmark.circle"
    let description = "This saved result may have changed."
    let actionTitle = "Back"
    let navigationTitle = "Unavailable"
}

struct SearchDetailMetadata: Equatable {
    let label: String
    let value: String
}

struct SearchDetailMetadataRows: View {
    let metadata: [SearchDetailMetadata]

    var body: some View {
        ForEach(Array(metadata.enumerated()), id: \.offset) { index, row in
            LedgerSummaryMetric(label: row.label, value: row.value, fixedVerticalSizing: true)

            if index < metadata.count - 1 {
                Divider()
            }
        }
    }
}

struct NoteDetailPresentation: Equatable {
    let text: String
    let updatedLine: String
    let metadata: [SearchDetailMetadata]
    let sourceTitle: String
    let sourceDetail: String?

    init(note: LedgerNote) {
        text = note.text
        updatedLine = "Updated \(DateFormatting.fullDate.string(from: note.updatedAt))"
        metadata = [
            SearchDetailMetadata(label: "Created", value: DateFormatting.fullDate.string(from: note.createdAt)),
            SearchDetailMetadata(label: "Updated", value: DateFormatting.fullDate.string(from: note.updatedAt))
        ]
        let source = LedgerSourcePresentation(
            hasSourceMessage: note.sourceMessage != nil,
            manualDate: note.createdAt,
            extractedIDs: [note.sourceExtractionRunID].compactMap { $0 }
        )
        sourceTitle = source.title
        sourceDetail = source.detail
    }
}

struct NoteDetailView: View {
    @State private var isEditing = false
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \EntityLink.createdAt, order: .reverse) private var entityLinks: [EntityLink]

    let note: LedgerNote

    private let relationshipService = RelationshipTraversalService()

    private var presentation: NoteDetailPresentation {
        NoteDetailPresentation(note: note)
    }

    private var relatedRecords: [RelationshipTraversalResult] {
        relationshipService.relatedRecords(
            for: .note(note.id),
            in: traversalRecords,
            allowedTargetTypes: [.thing, .event, .rule, .chatMessage]
        )
    }

    private var traversalRecords: RelationshipTraversalRecords {
        RelationshipTraversalRecords(
            messages: messages,
            things: things,
            events: events,
            rules: rules,
            notes: [note],
            entityLinks: entityLinks
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                noteTextSection

                if !note.linkedThings.isEmpty {
                    linkedThingsSection
                }

                if !relatedRecords.isEmpty {
                    relatedRecordsSection
                }

                noteContextSection
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Note")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                NoteEditView(note: note, thing: note.linkedThings.first)
            }
        }
    }

    private var noteTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.updatedLine)
                .font(LedgerVisualSystem.Typography.rowSecondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var linkedThingsSection: some View {
        LedgerDetailSection(title: "Linked Things") {
            ForEach(Array(note.linkedThings.enumerated()), id: \.element.id) { index, thing in
                NavigationLink {
                    ThingDetailView(thing: thing)
                } label: {
                    LedgerRow(
                        primary: thing.name,
                        secondary: [LedgerRowLine(text: "Linked thing", tone: .muted)],
                        density: .detail
                    ) {
                        LedgerPill(text: "Thing", tone: .info, size: .small)
                    }
                }
                .buttonStyle(.plain)

                if index < note.linkedThings.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var relatedRecordsSection: some View {
        LedgerDetailSection(title: "Related Records") {
            RelatedContextRows(
                results: relatedRecords,
                records: traversalRecords,
                things: things,
                events: events,
                rules: rules,
                notes: [note],
                messages: messages
            )
        }
    }

    private var noteContextSection: some View {
        LedgerDetailSection(title: "Context") {
            SearchDetailMetadataRows(metadata: presentation.metadata)

            Divider()

            LedgerSummaryMetric(
                label: "Source",
                value: presentation.sourceTitle,
                detail: presentation.sourceDetail,
                fixedVerticalSizing: true
            )
        }
    }
}

struct ChatMessageContextPresentation: Equatable {
    let text: String
    let capturedLine: String
    let roleText: String
    let metadata: [SearchDetailMetadata]

    init(message: ChatMessage) {
        text = message.text
        capturedLine = "Captured \(DateFormatting.fullDate.string(from: message.createdAt))"
        roleText = message.role == .user ? "Original entry" : message.role.rawValue.capitalized
        metadata = [
            SearchDetailMetadata(label: "Captured", value: DateFormatting.fullDate.string(from: message.createdAt)),
            SearchDetailMetadata(label: "Context", value: roleText)
        ]
    }
}

struct ChatMessageContextView: View {
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \EntityLink.createdAt, order: .reverse) private var entityLinks: [EntityLink]

    let message: ChatMessage

    private let relationshipService = RelationshipTraversalService()

    private var presentation: ChatMessageContextPresentation {
        ChatMessageContextPresentation(message: message)
    }

    private var relatedRecords: [RelationshipTraversalResult] {
        relationshipService.relatedRecords(
            for: .chatMessage(message.id),
            in: traversalRecords
        )
    }

    private var traversalRecords: RelationshipTraversalRecords {
        RelationshipTraversalRecords(
            messages: [message],
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            entityLinks: entityLinks
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                messageTextSection

                if !relatedRecords.isEmpty {
                    relatedRecordsSection
                }

                messageContextSection
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Message")
    }

    private var messageTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(presentation.roleText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                LedgerPill(text: "Message", tone: .link)
            }

            Text(presentation.text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.capturedLine)
                .font(LedgerVisualSystem.Typography.rowSecondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var relatedRecordsSection: some View {
        LedgerDetailSection(title: "Related Records") {
            RelatedContextRows(
                results: relatedRecords,
                records: traversalRecords,
                things: things,
                events: events,
                rules: rules,
                notes: notes,
                messages: [message]
            )
        }
    }

    private var messageContextSection: some View {
        LedgerDetailSection(title: "Context") {
            SearchDetailMetadataRows(metadata: presentation.metadata)
        }
    }
}
