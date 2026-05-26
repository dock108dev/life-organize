import SwiftData
import SwiftUI

struct LedgerReviewQueueDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState

    let item: LedgerReviewItem
    let entry: LedgerReviewQueueEntry
    let messages: [ChatMessage]
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let deviceTokenStore: any DeviceTokenStore
    let onAddKey: () -> Void

    @State private var reminderDate = DateFormatting.normalizedDateOnly(Date())
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var savedNoteID: UUID?
    @State private var pendingAction: LedgerReviewPendingAction?

    private var presentation: LedgerReviewReconciliationPresentation {
        LedgerReviewReconciliationPresentationBuilder().presentation(
            for: item,
            entry: entry,
            messages: messages,
            things: things,
            events: events,
            rules: rules,
            notes: notes
        )
    }

    private var service: LedgerReviewQueueService {
        LedgerReviewQueueService(
            modelContext: modelContext,
            deviceTokenStore: deviceTokenStore,
            dataGeneration: sessionState.dataGeneration,
            isDataGenerationCurrent: sessionState.isCurrentDataGeneration
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                adaptiveReviewLayout(width: proxy.size.width)
                    .padding(ReviewQueueDetailLayout.outerPadding)
            }
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("review-queue-detail")
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let startsAt = targetRule?.startsAt {
                reminderDate = startsAt
            } else if let draft = try? service.reminderDraft(for: item) {
                reminderDate = draft.startsAt
            }
        }
        .confirmationDialog(
            pendingAction?.dialogTitle ?? "Update Review?",
            isPresented: pendingActionBinding,
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.confirmTitle, role: pendingAction.role) {
                    performPendingAction(pendingAction)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pendingAction?.message ?? "")
        }
        .alert(
            "Couldn't Update Review",
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

    @ViewBuilder
    private func adaptiveReviewLayout(width: CGFloat) -> some View {
        let availableWidth = max(0, width - ReviewQueueDetailLayout.outerPadding * 2)
        let mode = ReviewQueueDetailLayout.mode(
            for: availableWidth,
            horizontalSizeClass: horizontalSizeClass,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )

        switch mode {
        case .twoColumn:
            let actionWidth = ReviewQueueDetailLayout.actionColumnWidth(for: availableWidth)
            HStack(alignment: .top, spacing: ReviewQueueDetailLayout.columnSpacing) {
                reviewContentColumn
                    .frame(maxWidth: ReviewQueueDetailLayout.contentMaxWidth, alignment: .leading)
                    .layoutPriority(1)

                reviewActionsColumn
                    .frame(width: actionWidth, alignment: .topLeading)
            }
            .frame(
                maxWidth: ReviewQueueDetailLayout.contentMaxWidth + actionWidth + ReviewQueueDetailLayout.columnSpacing,
                alignment: .center
            )
            .frame(maxWidth: .infinity, alignment: .center)
        case .singleColumn:
            VStack(alignment: .leading, spacing: 16) {
                reviewContentColumn
                reviewActionsColumn
            }
            .frame(maxWidth: ReviewQueueDetailLayout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var reviewContentColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let successMessage {
                updatedPanel(successMessage)
            }

            ReconciliationPanelView(panel: presentation.source, prominence: .source) { row in
                destination(for: row)
            }
            ReconciliationPanelView(panel: presentation.suggestion, prominence: .suggestion) { row in
                destination(for: row)
            }
            if let evidence = presentation.evidence {
                ReconciliationPanelView(panel: evidence, prominence: .evidence) { row in
                    destination(for: row)
                }
            }
        }
    }

    private var reviewActionsColumn: some View {
        actionsPanel
    }

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            LedgerSectionHeader(title: "Actions")
            VStack(alignment: .leading, spacing: 12) {
                if let primary = presentation.actions.primary {
                    actionControl(primary)
                        .accessibilityIdentifier(primary.accessibilityIdentifier)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if entry.correctionClass == .adjustReminderTiming, let rule = targetRule {
                    Divider()
                    reminderTimingControls(for: rule)
                }

                if !presentation.actions.contextual.isEmpty {
                    Divider()
                    ForEach(presentation.actions.contextual) { action in
                        actionControl(action)
                            .accessibilityIdentifier(action.accessibilityIdentifier)
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !presentation.actions.reviewState.isEmpty {
                    Divider()
                    ForEach(presentation.actions.reviewState) { action in
                        actionControl(action)
                            .accessibilityIdentifier(action.accessibilityIdentifier)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !presentation.actions.destructive.isEmpty {
                    Divider()
                    ForEach(presentation.actions.destructive) { action in
                        actionControl(action)
                            .accessibilityIdentifier(action.accessibilityIdentifier)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func updatedPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LedgerSectionHeader(title: "Updated")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let savedNoteID, let note = notes.first(where: { $0.id == savedNoteID }) {
                NavigationLink("Open Saved Note") {
                    NoteDetailView(note: note)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func actionControl(_ action: LedgerReviewReconciliationAction) -> some View {
        switch action.kind {
        case .connectService:
            Button(action.title, action: onAddKey)
        case .retry:
            Button(action.title) {
                pendingAction = .retry
            }
        case .confirm:
            Button(action.title) {
                pendingAction = .markReviewed
            }
        case .openRecord(let type, let id):
            NavigationLink(action.title) {
                destination(for: type, id: id)
            }
        case .mergeThing(let id):
            Button(action.title) {
                pendingAction = .mergeThings(id, thingName(id))
            }
        case .reassignRecords(let id):
            Button(action.title) {
                pendingAction = .reassignRecords(id, thingName(id))
            }
        case .adjustReminderTiming:
            Button(action.title) {
                pendingAction = .adjustReminderTiming(reminderDate, reminderDateActionTitle)
            }
            .disabled(!action.isEnabled)
        case .buildReminderDraft:
            if let draft = try? service.reminderDraft(for: item) {
                NavigationLink(action.title) {
                    RuleEditView(rule: nil, thing: targetThing, draft: draft) { _ in
                        successMessage = "Reminder saved. Mark reviewed when this review can close."
                    }
                }
            }
        case .saveAsNote:
            Button(action.title) {
                pendingAction = .saveAsNote
            }
        case .snooze:
            Button(action.title) {
                pendingAction = .snooze(tomorrow)
            }
        case .dismiss:
            Button(action.title, role: .destructive) {
                pendingAction = .dismiss
            }
        case .blocked:
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.subheadline.weight(.medium))
                if let detail = action.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func reminderTimingControls(for rule: LedgerRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current: \(DateFormatting.fullDate.string(from: rule.startsAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(reminderDateLabel(for: rule), selection: $reminderDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            Button(reminderDateActionTitle(for: rule)) {
                pendingAction = .adjustReminderTiming(reminderDate, reminderDateActionTitle(for: rule))
            }
            .buttonStyle(.borderedProminent)
            if let lifecycleAction = reminderLifecycleAction(for: rule) {
                Button(lifecycleAction.title, role: .destructive) {
                    pendingAction = .applyReminderLifecycle(lifecycleAction.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var targetRule: LedgerRule? {
        if item.targetType == .rule, let targetID = item.targetID {
            return rules.first { $0.id == targetID }
        }
        guard let ruleEvidence = item.evidence.first(where: { $0.sourceType == .rule }) else {
            return nil
        }
        return rules.first { $0.id == ruleEvidence.sourceID }
    }

    private var targetThing: Thing? {
        guard let targetID = item.targetID else { return nil }
        return things.first { $0.id == targetID }
    }

    private var reminderDateActionTitle: String {
        targetRule.map(reminderDateActionTitle(for:)) ?? "Adjust Timing"
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private var pendingActionBinding: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAction = nil
                }
            }
        )
    }

    private func thingName(_ id: UUID) -> String {
        things.first { $0.id == id }?.name ?? "Thing"
    }

    private func reminderDateLabel(for rule: LedgerRule) -> String {
        guard let dateAction = ReminderDetailActionPolicy.dateAction(
            for: rule,
            status: RuleStatusService().status(for: rule)
        ) else {
            return "Date"
        }
        switch dateAction.sheet {
        case .reschedule:
            return "Due date"
        case .endDate:
            return "End date"
        case .edit:
            return "Date"
        }
    }

    private func reminderDateActionTitle(for rule: LedgerRule) -> String {
        ReminderDetailActionPolicy.dateAction(
            for: rule,
            status: RuleStatusService().status(for: rule)
        )?.title ?? "Adjust Timing"
    }

    private func reminderLifecycleAction(for rule: LedgerRule) -> ReminderLifecycleAction? {
        ReminderDetailActionPolicy.lifecycleAction(
            for: rule,
            status: RuleStatusService().status(for: rule)
        )
    }

    private func retry() async {
        do {
            try await service.retryEntry(item)
            successMessage = "Entry retry finished. Review item updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateItem(_ action: () throws -> Void) {
        do {
            let previousSuccessMessage = successMessage
            try action()
            if successMessage == previousSuccessMessage {
                successMessage = "Review item updated. No automatic change has been made."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performPendingAction(_ action: LedgerReviewPendingAction) {
        pendingAction = nil
        switch action {
        case .retry:
            Task {
                await retry()
            }
        case .markReviewed:
            updateItem {
                try service.markReviewed(item)
            }
        case .dismiss:
            updateItem {
                try service.dismiss(item)
            }
        case .snooze(let date):
            updateItem {
                try service.snooze(item, until: date)
            }
        case .mergeThings(let targetID, let targetName):
            updateItem {
                try service.mergeDuplicateThings(for: item, into: targetID)
                successMessage = "Merged into \(targetName)."
            }
        case .reassignRecords(let targetID, let targetName):
            updateItem {
                try service.reassignRecords(from: item, to: targetID)
                successMessage = "Reassigned records to \(targetName)."
            }
        case .adjustReminderTiming(let date, let title):
            updateItem {
                try service.applyReminderDateAction(for: item, date: date)
                successMessage = "\(title) saved."
            }
        case .applyReminderLifecycle(let title):
            updateItem {
                try service.applyReminderLifecycleAction(for: item)
                successMessage = "\(title) saved."
            }
        case .saveAsNote:
            updateItem {
                let note = try service.saveAsNote(item, body: presentation.saveAsNoteBody ?? "")
                savedNoteID = note.id
                successMessage = "Saved as note."
            }
        }
    }

    @ViewBuilder
    private func destination(for row: LedgerReviewReconciliationRow) -> some View {
        if let targetType = row.targetType, let targetID = row.targetID {
            destination(for: targetType, id: targetID)
        } else {
            MissingSearchRecordView()
        }
    }

    @ViewBuilder
    private func destination(for targetType: LedgerReviewItemTargetType, id: UUID) -> some View {
        switch targetType {
        case .thing:
            if let thing = things.first(where: { $0.id == id }) {
                ThingDetailView(thing: thing)
            } else {
                MissingSearchRecordView()
            }
        case .event:
            if let event = events.first(where: { $0.id == id }) {
                EventDetailView(event: event)
            } else {
                MissingSearchRecordView()
            }
        case .rule:
            if let rule = rules.first(where: { $0.id == id }) {
                RuleDetailView(rule: rule)
            } else {
                MissingSearchRecordView()
            }
        case .chatMessage:
            if let message = messages.first(where: { $0.id == id }) {
                ChatMessageContextView(message: message)
            } else {
                MissingSearchRecordView()
            }
        case .none:
            if let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note)
            } else {
                MissingSearchRecordView()
            }
        }
    }
}
