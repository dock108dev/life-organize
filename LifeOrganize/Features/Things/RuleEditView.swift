import SwiftData
import SwiftUI

struct RuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thing.name) private var things: [Thing]
    let rule: LedgerRule?
    let thing: Thing?
    let draft: LedgerReviewReminderDraft?
    let onSave: ((LedgerRule) -> Void)?

    @State private var title: String
    @State private var reason: String
    @State private var startsAt: Date
    @State private var hasExpiration: Bool
    @State private var expiresAt: Date
    @State private var selectedThingID: UUID?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false

    init(
        rule: LedgerRule?,
        thing: Thing?,
        draft: LedgerReviewReminderDraft? = nil,
        onSave: ((LedgerRule) -> Void)? = nil
    ) {
        self.rule = rule
        self.thing = thing ?? rule?.thing
        self.draft = draft
        self.onSave = onSave
        let initialThing = thing ?? rule?.thing
        _title = State(initialValue: rule?.title ?? draft?.title ?? "")
        _reason = State(initialValue: rule?.reason ?? draft?.reason ?? "")
        _startsAt = State(initialValue: rule?.startsAt ?? draft?.startsAt ?? DateFormatting.normalizedDateOnly(Date()))
        _hasExpiration = State(initialValue: rule?.expiresAt != nil || draft?.expiresAt != nil)
        _expiresAt = State(initialValue: rule?.expiresAt ?? draft?.expiresAt ?? DateFormatting.normalizedDateOnly(Date()))
        _selectedThingID = State(initialValue: initialThing?.id ?? draft?.thingID)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && dateValidationMessage == nil
    }

    private var dateValidationMessage: String? {
        ReminderDateValidation.endDateError(
            startsAt: startsAt,
            hasExpiration: hasExpiration,
            expiresAt: expiresAt
        )
    }

    private var selectedContinuityBehavior: LedgerContinuityBehavior {
        ReminderEditContract.continuityBehavior(hasExpiration: hasExpiration)
    }

    private var selectedThing: Thing? {
        things.first { $0.id == selectedThingID }
    }

    var body: some View {
        Form {
            Section("Reminder") {
                TextField("Reminder", text: $title)
                TextField("Reason", text: $reason, axis: .vertical)
                DatePicker("Starts", selection: $startsAt, displayedComponents: .date)
                Toggle("Ends", isOn: $hasExpiration)
                if hasExpiration {
                    DatePicker("End date", selection: $expiresAt, displayedComponents: .date)
                    if let dateValidationMessage {
                        Text(dateValidationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                if rule?.continuityBehavior == .recurringText {
                    Text("Recurring text is preserved as written. Automated repeat controls are not available yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Linked Thing") {
                ThingSelectionPicker(title: "Thing", things: things, selection: $selectedThingID)
            }

            Section("Source") {
                if let draft, !draft.sourceContext.isEmpty {
                    MetadataRow(label: "Review context", value: draft.sourceContext)
                    Text("No automatic change has been made.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SourceDisclosure(sourceMessage: rule?.sourceMessage, manualDate: rule?.createdAt ?? Date())
                }
            }

            if rule != nil {
                Section {
                    Button("Delete Reminder", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .ledgerEditFormWidth(.rule)
        .navigationTitle(rule == nil ? "Add Reminder" : "Edit Reminder")
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
        .confirmationDialog("Delete Reminder?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Reminder", role: .destructive) {
                deleteRule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved reminder. Your timeline entry will remain.")
        }
        .alert(
            "Couldn't Save Reminder",
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
        let normalizedStart = DateFormatting.normalizedDateOnly(startsAt)
        let normalizedExpiration = hasExpiration ? DateFormatting.normalizedDateOnly(expiresAt) : nil
        do {
            let service = DerivedFieldMaintenanceService(modelContext: modelContext)
            if let rule {
                let previousThing = rule.thing
                rule.title = trimmedTitle
                rule.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                rule.startsAt = normalizedStart
                rule.expiresAt = normalizedExpiration
                rule.thing = selectedThing
                if rule.sourceMessage == nil {
                    rule.ruleType = .reminder
                    if rule.continuityBehavior != .recurringText {
                        rule.continuityBehavior = selectedContinuityBehavior
                    }
                }
                rule.updatedAt = Date()
                try service.updateRule(rule, previousThing: previousThing)
                onSave?(rule)
            } else {
                let newRule = LedgerRule(
                    title: trimmedTitle,
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    ruleType: .reminder,
                    continuityBehavior: selectedContinuityBehavior,
                    rawText: "",
                    startsAt: normalizedStart,
                    expiresAt: normalizedExpiration,
                    thing: selectedThing
                )
                try service.insertRule(newRule)
                onSave?(newRule)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The reminder could not be saved."
        }
    }

    private func deleteRule() {
        guard let rule else { return }
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).deleteRule(rule)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The reminder could not be deleted."
        }
    }
}

enum ReminderDateValidation {
    static func endDateError(startsAt: Date, hasExpiration: Bool, expiresAt: Date) -> String? {
        guard hasExpiration else { return nil }
        let normalizedStart = DateFormatting.normalizedDateOnly(startsAt)
        let normalizedEnd = DateFormatting.normalizedDateOnly(expiresAt)
        if normalizedEnd <= normalizedStart {
            return "End date must be after the start date."
        }
        return nil
    }
}

enum ReminderEditContract {
    static func continuityBehavior(hasExpiration: Bool) -> LedgerContinuityBehavior {
        hasExpiration ? .timeLimitedWindow : .dateBasedReminder
    }
}
