import SwiftData
import SwiftUI

struct RuleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \EntityLink.createdAt, order: .reverse) private var entityLinks: [EntityLink]

    let rule: LedgerRule

    @State private var activeSheet: RuleDetailSheet?
    @State private var lifecycleAction: ReminderLifecycleAction?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @State private var isSummaryDetailsExpanded = false
    @State private var isRelatedHistoryExpanded = false
    @State private var isConnectedContextExpanded = false

    private let statusService = RuleStatusService()
    private let continuityService = ReminderContinuityPresentationService()
    private let summaryService = ReminderDetailSummaryService()
    private let relatedEventService = RuleRelatedEventService()
    private let relationshipService = RelationshipTraversalService()

    private var status: RuleStatus {
        statusService.status(for: rule)
    }

    private var continuityPresentation: ReminderContinuityPresentation {
        continuityService.presentation(for: rule)
    }

    private var summaryPresentation: ReminderDetailSummaryPresentation {
        summaryService.presentation(for: rule)
    }

    private var dateAction: ReminderDateAction? {
        ReminderDetailActionPolicy.dateAction(for: rule, status: status)
    }

    private var availableLifecycleAction: ReminderLifecycleAction? {
        ReminderDetailActionPolicy.lifecycleAction(for: rule, status: status)
    }

    private var relatedEvents: [RelatedRuleEvent] {
        relatedEventService.relatedEvents(for: rule, events: events, entityLinks: entityLinks)
    }

    private var traversalRecords: RelationshipTraversalRecords {
        RelationshipTraversalRecords(
            messages: messages,
            things: things,
            events: events,
            rules: [rule],
            notes: notes,
            entityLinks: entityLinks
        )
    }

    private var relatedContextRecords: [RelationshipTraversalResult] {
        relationshipService.relatedRecords(
            for: .rule(rule.id),
            in: traversalRecords,
            allowedTargetTypes: [.chatMessage, .note, .thing],
            includeTextOverlap: true
        )
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                summarySection
                relatedEventsSection
                if !relatedContextRecords.isEmpty {
                    relatedContextSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .background(LedgerScreenBackground().ignoresSafeArea())
        .accessibilityIdentifier("carry-forward-detail")
        .navigationTitle("Carry Forward")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Reminder") {
                        activeSheet = .edit
                    }
                    if let dateAction {
                        Button(dateAction.title) {
                            activeSheet = dateAction.sheet
                        }
                    }
                    if let availableLifecycleAction {
                        Button(availableLifecycleAction.title, role: .destructive) {
                            lifecycleAction = availableLifecycleAction
                        }
                    }
                    Button("Delete Reminder", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Reminder Actions")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .edit:
                    RuleEditView(rule: rule, thing: rule.thing)
                case .reschedule:
                    ReminderRescheduleView(rule: rule)
                case .endDate:
                    ReminderEndDateView(rule: rule)
                }
            }
        }
        .confirmationDialog(lifecycleAction?.dialogTitle ?? "Update Reminder?", isPresented: isConfirmingLifecycleAction, titleVisibility: .visible) {
            if let lifecycleAction {
                Button(lifecycleAction.title, role: .destructive) {
                    applyLifecycleAction(lifecycleAction)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(lifecycleAction?.message ?? "")
        }
        .confirmationDialog("Delete Reminder?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Reminder", role: .destructive) {
                deleteRule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved reminder. Your timeline entry will remain.")
        }
        .alert(
            "Couldn't Update Reminder",
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

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summaryPresentation.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            badgeStack

            Text(summaryPresentation.stateSentence)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summaryPresentation.scheduleSentence)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let actionSentence = summaryPresentation.actionSentence {
                Text(actionSentence)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                summaryActionTray
            }

            LedgerDisclosureSection(title: "Details", isExpanded: $isSummaryDetailsExpanded) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(summaryPresentation.contextSentence)
                    Text(summaryPresentation.reasonSentence)
                    Text(summaryPresentation.sourceSentence)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var badgeStack: some View {
        HStack(spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
            ForEach(continuityPresentation.badges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
        }
    }

    private var summaryActionTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dateAction {
                Button {
                    activeSheet = dateAction.sheet
                } label: {
                    Label(dateAction.title, systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            if let availableLifecycleAction {
                Button(role: .destructive) {
                    lifecycleAction = availableLifecycleAction
                } label: {
                    Label(availableLifecycleAction.title, systemImage: "checkmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.top, 2)
    }

    private var relatedEventsSection: some View {
        LedgerDisclosureSection(
            title: "Related History",
            summary: LedgerDisplayFormatting.count(relatedEvents.count, singular: "event", plural: "events"),
            isExpanded: $isRelatedHistoryExpanded
        ) {
            if relatedEvents.isEmpty {
                Text("No related history yet.")
                    .font(LedgerVisualSystem.Typography.rowSecondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relatedEvents) { relatedEvent in
                    RelatedRuleEventRow(relatedEvent: relatedEvent)
                }
            }
        }
    }

    private var relatedContextSection: some View {
        LedgerDisclosureSection(
            title: "Connected Context",
            summary: LedgerDisplayFormatting.count(relatedContextRecords.count, singular: "record", plural: "records"),
            isExpanded: $isConnectedContextExpanded
        ) {
            RelatedContextRows(
                results: relatedContextRecords,
                records: traversalRecords,
                things: things,
                events: events,
                rules: [rule],
                notes: notes,
                messages: messages
            )
        }
    }

    private var isConfirmingLifecycleAction: Binding<Bool> {
        Binding(
            get: { lifecycleAction != nil },
            set: { isPresented in
                if !isPresented {
                    lifecycleAction = nil
                }
            }
        )
    }

    private func applyLifecycleAction(_ action: ReminderLifecycleAction) {
        do {
            let deactivatedAt = Date()
            ReminderRuleLifecycleMutation.deactivate(
                rule,
                at: deactivatedAt,
                maintenance: DerivedFieldMaintenanceService(modelContext: modelContext, now: { deactivatedAt })
            )
            try modelContext.save()
            lifecycleAction = nil
            dismiss()
        } catch {
            errorMessage = action.errorMessage
        }
    }

    private func deleteRule() {
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).deleteRule(rule)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The reminder could not be deleted."
        }
    }

}

private struct RelatedRuleEventRow: View {
    let relatedEvent: RelatedRuleEvent

    var body: some View {
        LedgerRow(
            primary: relatedEvent.event.title,
            secondary: rowLines,
            density: .detail
        )
    }

    private var rowLines: [LedgerRowLine] {
        var lines = [
            LedgerRowLine(text: DateFormatting.shortDate.string(from: relatedEvent.event.occurredAt)),
            LedgerRowLine(text: relatedEvent.sourceLabel)
        ]
        if let detail = relatedEvent.event.note?.nilIfEmpty {
            lines.append(LedgerRowLine(text: detail, lineLimit: 2))
        }
        return lines
    }
}
