import SwiftData
import SwiftUI

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var reminders: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \EntityLink.createdAt, order: .reverse) private var entityLinks: [EntityLink]
    let event: LedgerEvent

    @State private var activeSheet: EventDetailSheet?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingUnlink = false
    @State private var errorMessage: String?

    private let relationshipService = RelationshipTraversalService()

    private var relationshipRecords: [RelationshipTraversalResult] {
        relationshipService.relatedRecords(
            for: .event(event.id),
            in: traversalRecords,
            allowedTargetTypes: [.rule, .note]
        )
    }

    private var traversalRecords: RelationshipTraversalRecords {
        RelationshipTraversalRecords(
            messages: messages,
            things: relatedThings,
            events: [event],
            rules: reminders,
            notes: notes,
            entityLinks: entityLinks
        )
    }

    private var relatedThings: [Thing] {
        var thingsByID: [UUID: Thing] = [:]
        if let thing = event.thing {
            thingsByID[thing.id] = thing
        }
        for reminder in reminders {
            if let thing = reminder.thing {
                thingsByID[thing.id] = thing
            }
        }
        for note in notes {
            for thing in note.linkedThings {
                thingsByID[thing.id] = thing
            }
        }
        return Array(thingsByID.values)
    }

    private var relatedReminders: [LedgerRule] {
        let remindersByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        return relationshipRecords.compactMap { result in
            guard case .rule(let id) = result.target else { return nil }
            return remindersByID[id]
        }
    }

    private var relatedNotes: [LedgerNote] {
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return relationshipRecords.compactMap { result in
            guard case .note(let id) = result.target else { return nil }
            return notesByID[id]
        }
    }

    private var relatedNoteResults: [RelationshipTraversalResult] {
        relationshipRecords.filter {
            if case .note = $0.target { true } else { false }
        }
    }

    private func relationshipSourceLabel(for node: RelationshipNode) -> String? {
        relationshipRecords.first { $0.target == node }?.sourceLabel
    }

    private func relatedReminderRowLines(for reminder: LedgerRule) -> [LedgerRowLine] {
        var lines = EventRelatedReminderRow.lines(for: reminder)
        if let label = relationshipSourceLabel(for: .rule(reminder.id)) {
            lines.append(LedgerRowLine(text: label))
        }
        return lines
    }

    private var operationalMetadataEntries: [LedgerEventMetadataEntry] {
        EventMetadataDisplayFormatter
            .orderedDetailEntries(event.metadataEntries, eventType: event.eventType)
            .filter { $0.key != .sourceText }
    }

    private var sourceMetadataEntries: [LedgerEventMetadataEntry] {
        EventMetadataDisplayFormatter
            .orderedDetailEntries(event.metadataEntries, eventType: event.eventType)
            .filter { $0.key == .sourceText }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                eventSummarySection

                if !operationalMetadataEntries.isEmpty {
                    metadataSection
                }

                if let note = event.note?.nilIfEmpty {
                    noteSection(note)
                }

                if !relatedReminders.isEmpty {
                    relatedRemindersSection
                }

                if !relatedNotes.isEmpty {
                    relatedNotesSection
                }

                if debugAccessPolicy.allowsExtractionDebugScreens {
                    diagnosticsSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    activeSheet = .edit
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if event.thing != nil {
                        Button("Unlink Thing", role: .destructive) {
                            isConfirmingUnlink = true
                        }
                    }
                    Button("Delete Event", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .edit:
                    EventEditView(event: event, thing: event.thing, allowsDelete: false)
                }
            }
        }
        .confirmationDialog("Unlink Thing?", isPresented: $isConfirmingUnlink, titleVisibility: .visible) {
            Button("Unlink Thing", role: .destructive) {
                unlinkThing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This keeps the event and removes only its current thing classification.")
        }
        .confirmationDialog("Delete Event?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                deleteEvent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the event. Your timeline entry will remain.")
        }
        .alert(
            "Couldn't Update Event",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var eventSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.title.nilIfEmpty ?? "Untitled event")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                LedgerPill(text: event.eventType.displayName, tone: .success)
            }

            LedgerSummaryMetric(
                label: "Occurred",
                value: DateFormatting.fullDate.string(from: event.occurredAt),
                fixedVerticalSizing: true
            )

            if let thing = event.thing {
                NavigationLink {
                    ThingDetailView(thing: thing)
                } label: {
                    LedgerRow(
                        primary: thing.name,
                        secondary: [LedgerRowLine(text: "Linked thing")],
                        density: .detail
                    ) {
                        LedgerPill(text: "THING", tone: .link, size: .small)
                    }
                }
                .buttonStyle(.plain)
            } else {
                LedgerSummaryMetric(label: "Linked thing", value: "None", fixedVerticalSizing: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var metadataSection: some View {
        LedgerDetailSection(title: "Operational Details") {
            ForEach(Array(operationalMetadataEntries.enumerated()), id: \.offset) { index, entry in
                LedgerSummaryMetric(
                    label: entry.key.displayName,
                    value: EventMetadataDisplayFormatter.displayValue(for: entry),
                    fixedVerticalSizing: true
                )

                if index < operationalMetadataEntries.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func noteSection(_ note: String) -> some View {
        LedgerDetailSection(title: "Note") {
            Text(note)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var relatedRemindersSection: some View {
        LedgerDetailSection(title: "Related Reminders") {
            ForEach(Array(relatedReminders.enumerated()), id: \.element.id) { index, reminder in
                NavigationLink {
                    RuleDetailView(rule: reminder)
                } label: {
                    EventRelatedReminderRow(reminder: reminder, lines: relatedReminderRowLines(for: reminder))
                }
                .buttonStyle(.plain)

                if index < relatedReminders.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var relatedNotesSection: some View {
        LedgerDetailSection(title: "Related Notes") {
            RelatedContextRows(
                results: relatedNoteResults,
                records: traversalRecords,
                things: relatedThings,
                events: [event],
                rules: reminders,
                notes: notes,
                messages: messages
            )
        }
    }

    private var diagnosticsSection: some View {
        LedgerDetailSection(title: "Developer Diagnostics") {
            LedgerSummaryMetric(
                label: "Created",
                value: DateFormatting.fullDate.string(from: event.createdAt),
                fixedVerticalSizing: true
            )
            Divider()
            LedgerSummaryMetric(
                label: "Updated",
                value: DateFormatting.fullDate.string(from: event.updatedAt),
                fixedVerticalSizing: true
            )
            Divider()
            SourceDisclosure(
                sourceMessage: event.sourceMessage,
                manualDate: event.createdAt,
                extractedIDs: [event.sourceExtractionRunID].compactMap { $0 }
            )
            if let rawText = event.rawText.nilIfEmpty {
                Divider()
                LedgerSummaryMetric(label: "Raw text", value: rawText, fixedVerticalSizing: true)
            }
            if let sourceClientID = event.sourceClientID?.nilIfEmpty {
                Divider()
                LedgerSummaryMetric(label: "Source client ID", value: sourceClientID, fixedVerticalSizing: true)
            }
            if let extractionRunID = event.sourceExtractionRunID {
                Divider()
                LedgerSummaryMetric(label: "Extraction run ID", value: extractionRunID.uuidString, fixedVerticalSizing: true)
            }
            ForEach(Array(sourceMetadataEntries.enumerated()), id: \.offset) { _, entry in
                Divider()
                LedgerSummaryMetric(
                    label: entry.key.displayName,
                    value: EventMetadataDisplayFormatter.displayValue(for: entry),
                    fixedVerticalSizing: true
                )
            }
        }
    }

    private func unlinkThing() {
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).unlinkEventFromThing(event)
            try modelContext.save()
        } catch {
            errorMessage = "The thing could not be unlinked."
        }
    }

    private func deleteEvent() {
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).deleteEvent(event)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The event could not be deleted."
        }
    }
}

private struct EventRelatedReminderRow: View {
    let reminder: LedgerRule
    let lines: [LedgerRowLine]?
    private let continuityService = ReminderContinuityPresentationService()

    var body: some View {
        let presentation = continuityService.presentation(for: reminder)

        LedgerRow(
            primary: reminder.title,
            secondary: lines ?? Self.lines(for: reminder),
            density: .detail,
            emphasis: presentation.lane.rowEmphasis
        ) {
            ForEach(presentation.badges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
        }
    }

    static func lines(for reminder: LedgerRule) -> [LedgerRowLine] {
        let presentation = ReminderContinuityPresentationService().presentation(for: reminder)
        return LedgerReminderRowLines.lines(for: presentation)
    }
}

private enum EventDetailSheet: Identifiable {
    case edit

    var id: String {
        switch self {
        case .edit:
            "edit"
        }
    }
}

#Preview {
    NavigationStack {
        EventDetailView(
            event: LedgerEvent(
                title: "Changed oil",
                occurredAt: Date(),
                rawText: "Changed oil at 52,000 mi.",
                eventType: .maintenance,
                metadataEntries: [
                    LedgerEventMetadataEntry(
                        key: .mileage,
                        valueKind: .number,
                        numberValue: 52_000,
                        unit: "mi"
                    )
                ]
            )
        )
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
