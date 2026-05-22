import SwiftData
import SwiftUI

enum RuleDetailSheet: Identifiable, Equatable {
    case edit
    case reschedule
    case endDate

    var id: String {
        switch self {
        case .edit:
            "edit"
        case .reschedule:
            "reschedule"
        case .endDate:
            "end-date"
        }
    }
}

struct ReminderDateAction: Equatable {
    let title: String
    let sheet: RuleDetailSheet
}

struct ReminderLifecycleAction: Identifiable, Equatable {
    let id: String
    let title: String
    let dialogTitle: String
    let message: String
    let errorMessage: String
}

enum ReminderDetailActionPolicy {
    static func dateAction(for rule: LedgerRule, status: RuleStatus) -> ReminderDateAction? {
        switch rule.continuityBehavior {
        case .dateBasedReminder:
            return ReminderDateAction(title: "Move Due Date", sheet: .reschedule)
        case .timeLimitedWindow:
            guard status != .inactive else { return nil }
            return ReminderDateAction(title: "Extend Window", sheet: .endDate)
        case .ongoing:
            guard rule.expiresAt != nil, status != .inactive else { return nil }
            return ReminderDateAction(title: "Set End Date", sheet: .endDate)
        case .recurringText:
            return nil
        }
    }

    static func lifecycleAction(for rule: LedgerRule, status: RuleStatus) -> ReminderLifecycleAction? {
        guard status != .inactive else { return nil }

        switch status {
        case .scheduled:
            let title = scheduledLifecycleTitle(for: rule)
            return ReminderLifecycleAction(
                id: "stop-scheduled",
                title: title,
                dialogTitle: "\(title)?",
                message: "This removes the item from your future flow. The original message and saved reminder remain.",
                errorMessage: "The reminder could not be updated."
            )
        case .active:
            if rule.continuityBehavior == .dateBasedReminder {
                return ReminderLifecycleAction(
                    id: "mark-done",
                    title: "Mark Done",
                    dialogTitle: "Mark Done?",
                    message: "This moves the reminder out of Now. The original message and saved reminder remain in history.",
                    errorMessage: "The reminder could not be completed."
                )
            }
            if rule.continuityBehavior == .ongoing {
                return ReminderLifecycleAction(
                    id: "stop-carrying",
                    title: "Stop Carrying",
                    dialogTitle: "Stop Carrying This?",
                    message: "This removes the item from Now. The original message and saved reminder remain.",
                    errorMessage: "The reminder could not be updated."
                )
            }
            if rule.continuityBehavior == .timeLimitedWindow {
                return ReminderLifecycleAction(
                    id: "close-window",
                    title: "Close Window",
                    dialogTitle: "Close Window?",
                    message: "This stops carrying the window forward. The saved reminder and original message remain.",
                    errorMessage: "The reminder could not be updated."
                )
            }
            if rule.continuityBehavior == .recurringText {
                return ReminderLifecycleAction(
                    id: "pause-pattern",
                    title: "Pause Pattern",
                    dialogTitle: "Pause Pattern?",
                    message: "This stops carrying the recurring wording forward. The original message and saved reminder remain.",
                    errorMessage: "The reminder could not be updated."
                )
            }
            return ReminderLifecycleAction(
                id: "stop-carrying",
                title: "Stop Carrying",
                dialogTitle: "Stop Carrying This?",
                message: "This removes the item from Now. The original message and saved reminder remain.",
                errorMessage: "The reminder could not be updated."
            )
        case .expired:
            let title = reviewLifecycleTitle(for: rule)
            return ReminderLifecycleAction(
                id: "let-rest",
                title: title,
                dialogTitle: "\(title)?",
                message: "This moves the item out of Review. The saved reminder remains available in history.",
                errorMessage: "The reminder could not be updated."
            )
        case .inactive:
            return nil
        }
    }

    private static func scheduledLifecycleTitle(for rule: LedgerRule) -> String {
        switch rule.continuityBehavior {
        case .timeLimitedWindow:
            "Cancel Window"
        case .recurringText:
            "Pause Pattern"
        case .dateBasedReminder, .ongoing:
            "Stop Carrying"
        }
    }

    private static func reviewLifecycleTitle(for rule: LedgerRule) -> String {
        switch rule.continuityBehavior {
        case .timeLimitedWindow:
            "Let Window Rest"
        case .recurringText:
            "Let Pattern Rest"
        case .dateBasedReminder, .ongoing:
            "Let It Rest"
        }
    }
}

struct ReminderRescheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let rule: LedgerRule

    @State private var startsAt: Date
    @State private var errorMessage: String?

    init(rule: LedgerRule) {
        self.rule = rule
        _startsAt = State(initialValue: rule.startsAt)
    }

    private var normalizedStart: Date {
        DateFormatting.normalizedDateOnly(startsAt)
    }

    private var canSave: Bool {
        normalizedStart != DateFormatting.normalizedDateOnly(rule.startsAt)
    }

    private var context: ReminderRescheduleSheetContext {
        ReminderRescheduleSheetContext(
            currentDate: rule.startsAt,
            selectedDate: normalizedStart,
            canSave: canSave
        )
    }

    var body: some View {
        ReminderEditSheetSurface {
            LedgerSummaryMetric(
                label: context.currentLabel,
                value: context.currentValue,
                detail: context.currentDetail,
                fixedVerticalSizing: true
            )

            ReminderDateEditBlock(title: context.editorTitle, statusMessage: context.statusMessage) {
                DatePicker(context.pickerLabel, selection: $startsAt, displayedComponents: .date)
            }
        }
        .navigationTitle("Move Due Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .alert(
            "Couldn't Reschedule Reminder",
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

    private func save() {
        do {
            let updatedAt = Date()
            try ReminderRuleLifecycleMutation.moveDueDate(
                rule,
                to: startsAt,
                at: updatedAt,
                maintenance: DerivedFieldMaintenanceService(modelContext: modelContext, now: { updatedAt })
            )
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The reminder could not be rescheduled."
        }
    }
}

struct ReminderEndDateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let rule: LedgerRule

    @State private var expiresAt: Date
    @State private var errorMessage: String?

    init(rule: LedgerRule) {
        self.rule = rule
        let baseline = max(rule.expiresAt ?? Date(), Date())
        _expiresAt = State(initialValue: DateFormatting.normalizedDateOnly(baseline.addingTimeInterval(7 * 24 * 60 * 60)))
    }

    private var normalizedExpiration: Date {
        DateFormatting.normalizedDateOnly(expiresAt)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var context: ReminderEndDateSheetContext {
        ReminderEndDateSheetContext(
            rule: rule,
            normalizedExpiration: normalizedExpiration,
            validationMessage: validationMessage
        )
    }

    var body: some View {
        ReminderEditSheetSurface {
            LedgerSummaryMetric(
                label: context.currentLabel,
                value: context.currentValue,
                detail: context.currentDetail,
                fixedVerticalSizing: true
            )

            ReminderDateEditBlock(
                title: context.editorTitle,
                statusMessage: context.statusMessage,
                statusTone: context.statusTone
            ) {
                DatePicker(context.pickerLabel, selection: $expiresAt, displayedComponents: .date)
            }
        }
        .navigationTitle(rule.continuityBehavior == .timeLimitedWindow ? "Extend Window" : "Set End Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .alert(
            "Couldn't Change End Date",
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

    private var validationMessage: String? {
        if normalizedExpiration <= rule.startsAt {
            return "End date must be after the start date."
        }
        if normalizedExpiration <= DateFormatting.normalizedDateOnly(Date()) {
            return "End date must be in the future."
        }
        if let currentExpiration = rule.expiresAt, normalizedExpiration <= currentExpiration {
            return "Choose a date after the current end date."
        }
        return nil
    }

    private func save() {
        do {
            let updatedAt = Date()
            try ReminderRuleLifecycleMutation.setEndDate(
                rule,
                to: expiresAt,
                at: updatedAt,
                maintenance: DerivedFieldMaintenanceService(modelContext: modelContext, now: { updatedAt })
            )
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The reminder end date could not be changed."
        }
    }
}

struct ReminderRescheduleSheetContext: Equatable {
    let currentDate: Date
    let selectedDate: Date
    let canSave: Bool

    var currentLabel: String {
        "Current due"
    }

    var currentValue: String {
        DateFormatting.fullDate.string(from: currentDate)
    }

    var currentDetail: String {
        "Saved reminder date"
    }

    var editorTitle: String {
        "Move to"
    }

    var pickerLabel: String {
        "Due date"
    }

    var statusMessage: String {
        if canSave {
            return "Will move to \(DateFormatting.fullDate.string(from: selectedDate))."
        }
        return "Choose a different date to save."
    }
}

struct ReminderEndDateSheetContext: Equatable {
    let currentLabel: String
    let currentValue: String
    let currentDetail: String
    let editorTitle: String
    let pickerLabel = "End date"
    let statusMessage: String?
    let statusTone: LedgerTone

    init(rule: LedgerRule, normalizedExpiration: Date, validationMessage: String?) {
        let isWindow = rule.continuityBehavior == .timeLimitedWindow
        currentLabel = isWindow ? "Planned end" : "Current end"
        currentValue = rule.expiresAt.map { DateFormatting.fullDate.string(from: $0) } ?? "No planned end"
        currentDetail = isWindow ? "Window stays open until this date" : "Saved reminder end"
        editorTitle = isWindow ? "Extend to" : "Set end date"
        if let validationMessage {
            statusMessage = validationMessage
            statusTone = .danger
        } else {
            statusMessage = "Will end \(DateFormatting.fullDate.string(from: normalizedExpiration))."
            statusTone = .neutral
        }
    }
}

private struct ReminderEditSheetSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 18)
        }
        .background(Color(.systemBackground))
    }
}

private struct ReminderDateEditBlock<Content: View>: View {
    let title: String
    let statusMessage: String?
    var statusTone: LedgerTone = .neutral
    let content: Content

    init(
        title: String,
        statusMessage: String?,
        statusTone: LedgerTone = .neutral,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.statusMessage = statusMessage
        self.statusTone = statusTone
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionHeader(title: title)

            content
                .datePickerStyle(.compact)

            if let statusMessage {
                Text(statusMessage)
                    .font(LedgerVisualSystem.Typography.metadataDetail)
                    .foregroundStyle(statusTone.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
