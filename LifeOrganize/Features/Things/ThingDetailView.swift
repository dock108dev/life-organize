import SwiftData
import SwiftUI

struct ThingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \EntityLink.createdAt, order: .reverse) private var entityLinks: [EntityLink]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var allEvents: [LedgerEvent]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var allNotes: [LedgerNote]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var allRules: [LedgerRule]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @Query(sort: \Thing.name) private var things: [Thing]
    let thing: Thing

    @State private var activeSheet: ThingDetailSheet?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private let relationshipService = RelationshipTraversalService()

    private var snapshot: ThingDetailSnapshot {
        ThingDetailSnapshot(thing: thing)
    }

    private var relatedRecords: [RelationshipTraversalResult] {
        relationshipService.relatedRecords(
            for: .thing(thing.id),
            in: relationshipRecords,
            allowedTargetTypes: [.chatMessage, .event, .note, .rule]
        )
    }

    private var relationshipRecords: RelationshipTraversalRecords {
        RelationshipTraversalRecords(
            messages: messages,
            things: things,
            events: allEvents,
            rules: allRules,
            notes: allNotes,
            entityLinks: entityLinks
        )
    }

    private var relatedContextRecords: [RelationshipTraversalResult] {
        let directKeys = Set(
            snapshot.events.map { RelationshipNode.event($0.id).stableKey }
                + snapshot.notes.map { RelationshipNode.note($0.id).stableKey }
                + thing.rules.map { RelationshipNode.rule($0.id).stableKey }
        )
        return relatedRecords
            .filter { !directKeys.contains($0.target.stableKey) }
            .prefix(8)
            .map { $0 }
    }

    private var thingSourceMessage: ChatMessage? {
        if let result = relatedRecords.first(where: { $0.target.type == .chatMessage }),
           let message = messages.first(where: { $0.id == result.target.id }) {
            return message
        }
        return messages.first { thing.sourceMessageIDs.contains($0.id) }
    }

    private var deleteReassignmentTargets: [Thing] {
        things.filter { $0.id != thing.id }
    }

    private var reviewPresentation: LedgerReviewItemPresentation? {
        LedgerReviewItemPresentationService().primaryPresentation(
            for: .thing,
            targetID: thing.id,
            in: reviewItems
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                operationalSummarySection

                if !snapshot.upcomingReminders.isEmpty {
                    rulesSection(title: "Now & Coming Up", rules: snapshot.upcomingReminders)
                }

                if snapshot.latestEventSummary != nil || snapshot.latestNoteSummary != nil {
                    recentActivitySection
                }

                if snapshot.hasHistory {
                    timelineReplaySection
                }

                if !snapshot.events.isEmpty {
                    eventsSection
                }

                if !snapshot.notes.isEmpty {
                    notesSection
                }

                if !snapshot.inactiveReminders.isEmpty {
                    rulesSection(title: "Review & Paused", rules: snapshot.inactiveReminders)
                }

                if !relatedContextRecords.isEmpty {
                    relatedContextSection
                }

                if !snapshot.identityRows.isEmpty {
                    aboutSection
                }

                if debugAccessPolicy.allowsExtractionDebugScreens {
                    sourceMetadataSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("thing-detail")
        .navigationTitle(thing.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    activeSheet = .editThing
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Event") { activeSheet = .addEvent }
                    Button("Add Reminder") { activeSheet = .addRule }
                    Button("Add Note") { activeSheet = .addNote }
                    Button("Delete Thing", role: .destructive) {
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
                sheetView(for: sheet)
            }
        }
        .confirmationDialog("Delete \"\(thing.name)\"?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            if !deleteReassignmentTargets.isEmpty {
                Button("Move Records, Then Delete", role: .destructive) {
                    activeSheet = .deleteWithReassign
                }
            }
            Button("Delete and Unlink Records", role: .destructive) {
                deleteThing(reassigningRecordsTo: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the thing. Your timeline entries will remain.")
        }
        .alert(
            "Couldn't Update Thing",
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

    private var operationalSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Summary")
                    .font(.title3.weight(.semibold))
                Spacer()
                LedgerPill(text: snapshot.status.rawValue, tone: statusTone)
            }

            LedgerOperationalMetric(snapshot.statusSummary, prominence: .primary)

            if let primaryOperationalSummary = snapshot.primaryOperationalSummary {
                LedgerOperationalMetric(primaryOperationalSummary)
            }

            if let continuitySummary = snapshot.continuitySummary {
                LedgerOperationalMetric(continuitySummary)
            }

            LedgerOperationalMetric(snapshot.reminderSummary)

            if let recentActivitySummary = snapshot.recentActivitySummary {
                LedgerOperationalMetric(recentActivitySummary)
            }

            if !snapshot.hasHistory {
                LedgerOperationalMetric(
                    label: "Last activity",
                    value: "No history yet",
                    detail: "Add an event, reminder, or note to start the record."
                )
            }

            if let reviewPresentation {
                if reviewPresentation.isHighPriority {
                    LedgerNoticeBanner(
                        icon: "text.badge.checkmark",
                        message: reviewPresentation.bannerMessage,
                        tone: reviewPresentation.tone,
                        actionTitle: detailActionTitle(for: reviewPresentation.item.kind),
                        action: { performDetailAction(for: reviewPresentation.item.kind) }
                    )
                }

                LedgerOperationalMetric(
                    label: "Review item",
                    value: reviewPresentation.title,
                    detail: reviewPresentation.detail
                )
            }

            if let reminderHistorySummary = snapshot.reminderHistorySummary {
                LedgerOperationalMetric(reminderHistorySummary)
            }

            Text(snapshot.countSummary)
                .font(LedgerVisualSystem.Typography.rowSecondary)
                .foregroundStyle(.secondary)

            LedgerInlineActionTray(actions: [
                LedgerInlineAction(title: "Event", systemImage: "calendar.badge.plus") { activeSheet = .addEvent },
                LedgerInlineAction(title: "Reminder", systemImage: "bell.badge") { activeSheet = .addRule },
                LedgerInlineAction(title: "Note", systemImage: "note.text.badge.plus") { activeSheet = .addNote }
            ])
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("thing-detail-title")
    }

    private var statusTone: LedgerTone {
        switch snapshot.status {
        case .active:
            return .attention
        case .quiet:
            return .info
        case .historical:
            return .muted
        }
    }

    private func summaryMetric(_ metric: ThingDetailSnapshot.SummaryMetric) -> some View {
        LedgerSummaryMetric(label: metric.label, value: metric.value, detail: metric.detail)
    }

    private var recentActivitySection: some View {
        LedgerDetailSection(title: "Recent Activity") {
            if let latestEventSummary = snapshot.latestEventSummary { LedgerOperationalMetric(latestEventSummary) }
            if let latestNoteSummary = snapshot.latestNoteSummary { LedgerOperationalMetric(latestNoteSummary) }
        }
    }

    private var timelineReplaySection: some View {
        LedgerDetailSection(title: "Timeline Replay") {
            NavigationLink {
                TimelineSliceReplayView(descriptor: .linkedThing(thing))
            } label: {
                LedgerRow(
                    primary: "Open \(thing.name) timeline",
                    secondary: [LedgerRowLine(text: "Replay events, reminders, notes, and linked activity together.")],
                    density: .detail
                ) {
                    LedgerPill(text: "History", tone: .info, size: .small)
                }
            }
            .buttonStyle(.plain)

            if !snapshot.timelineEntryPoints.isEmpty { Divider() }

            ForEach(Array(snapshot.timelineEntryPoints.enumerated()), id: \.element.id) { index, entry in
                timelineEntryRow(entry)

                if index < snapshot.timelineEntryPoints.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func timelineEntryRow(_ entry: ThingDetailSnapshot.TimelineEntryPoint) -> some View {
        switch entry.navigationTarget {
        case .eventDetail(let id):
            if let event = snapshot.events.first(where: { $0.id == id }) {
                NavigationLink { EventDetailView(event: event) } label: { timelineLedgerRow(entry) }
                    .buttonStyle(.plain)
            } else {
                timelineLedgerRow(entry)
            }
        case .ruleDetail(let id):
            if let rule = thing.rules.first(where: { $0.id == id }) {
                Button { activeSheet = .editRule(rule) } label: { timelineLedgerRow(entry) }
                    .buttonStyle(.plain)
            } else {
                timelineLedgerRow(entry)
            }
        case .noteDetail(let id):
            if let note = snapshot.notes.first(where: { $0.id == id }) {
                Button { activeSheet = .editNote(note) } label: { timelineLedgerRow(entry) }
                    .buttonStyle(.plain)
            } else {
                timelineLedgerRow(entry)
            }
        default:
            timelineLedgerRow(entry)
        }
    }

    private func timelineLedgerRow(_ entry: ThingDetailSnapshot.TimelineEntryPoint) -> some View {
        LedgerRow(
            primary: entry.value,
            secondary: [LedgerRowLine(text: [entry.label, entry.detail].compactMap { $0 }.joined(separator: " · "))],
            density: .detail
        )
    }

    private var eventsSection: some View {
        LedgerDetailSection(title: "Event Chronology") {
            ForEach(Array(snapshot.events.enumerated()), id: \.element.id) { index, event in
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    LedgerEventRow(event: event)
                }
                .buttonStyle(.plain)

                if index < snapshot.events.count - 1 {
                    Divider()
                }
            }
        }
        .accessibilityIdentifier("thing-detail-events-section")
    }

    private var notesSection: some View {
        LedgerDetailSection(title: "Notes") {
            ForEach(Array(snapshot.notes.enumerated()), id: \.element.id) { index, note in
                Button {
                    activeSheet = .editNote(note)
                } label: {
                    LedgerNoteRow(note: note)
                }
                .buttonStyle(.plain)

                if index < snapshot.notes.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var aboutSection: some View {
        LedgerDetailSection(title: "Identity Details") {
            ForEach(Array(snapshot.identityRows.enumerated()), id: \.offset) { index, row in
                summaryMetric(row)

                if index < snapshot.identityRows.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var sourceMetadataSection: some View {
        LedgerDetailSection(title: "Developer Diagnostics") {
            ForEach(Array(snapshot.diagnosticRows.enumerated()), id: \.offset) { index, row in
                summaryMetric(row)

                if index < snapshot.diagnosticRows.count - 1 {
                    Divider()
                }
            }

            SourceDisclosure(
                sourceMessage: thingSourceMessage,
                manualDate: thing.createdAt,
                extractedIDs: thing.sourceMessageIDs + thing.sourceExtractionAttemptIDs
            )
        }
    }

    private var relatedContextSection: some View {
        LedgerDetailSection(title: "Related Context") {
            RelatedContextRows(
                results: relatedContextRecords,
                records: relationshipRecords,
                things: things,
                events: allEvents,
                rules: allRules,
                notes: allNotes,
                messages: messages
            )
        }
    }

    private func rulesSection(title: String, rules: [LedgerRule]) -> some View {
        LedgerDetailSection(title: title) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                let reviewPresentation = ruleReviewPresentation(for: rule)
                Button {
                    activeSheet = .editRule(rule)
                } label: {
                    LedgerRuleRow(rule: rule, reviewPresentation: reviewPresentation)
                }
                .buttonStyle(.plain)
                .ledgerReviewItemContextMenu(reviewPresentation?.item, onError: { errorMessage = $0 })

                if index < rules.count - 1 { Divider() }
            }
        }
        .accessibilityIdentifier("thing-detail-rules-section")
    }

    @ViewBuilder
    private func sheetView(for sheet: ThingDetailSheet) -> some View {
        switch sheet {
        case .addEvent:
            EventEditView(event: nil, thing: thing)
        case .addRule:
            RuleEditView(rule: nil, thing: thing)
        case .editRule(let rule):
            RuleEditView(rule: rule, thing: thing)
        case .addNote:
            NoteEditView(note: nil, thing: thing)
        case .editNote(let note):
            NoteEditView(note: note, thing: thing)
        case .editThing:
            ThingEditView(existingThing: thing) { _ in
                try modelContext.save()
            }
        case .deleteWithReassign:
            ThingDeleteReassignmentView(
                source: thing,
                targets: deleteReassignmentTargets,
                onCancel: { activeSheet = nil },
                onDelete: { target in deleteThing(reassigningRecordsTo: target) }
            )
        }
    }

    private func deleteThing(reassigningRecordsTo target: Thing?) {
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).deleteThing(thing, reassigningRecordsTo: target)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The thing could not be deleted."
        }
    }

    private func ruleReviewPresentation(for rule: LedgerRule) -> LedgerReviewItemPresentation? {
        LedgerReviewItemPresentationService().primaryPresentation(
            for: .rule,
            targetID: rule.id,
            in: reviewItems
        )
    }

    private func detailActionTitle(for kind: LedgerReviewItemKind) -> String? {
        switch kind {
        case .intervalReminder:
            return "Add Reminder"
        case .duplicateThing, .normalizationCandidate:
            return "Edit Thing"
        case .overdueReminderReview, .localRecovery, .extractionReview, .conflictingDate:
            return nil
        }
    }

    private func performDetailAction(for kind: LedgerReviewItemKind) {
        switch kind {
        case .intervalReminder:
            activeSheet = .addRule
        case .duplicateThing, .normalizationCandidate:
            activeSheet = .editThing
        case .overdueReminderReview, .localRecovery, .extractionReview, .conflictingDate:
            break
        }
    }
}
