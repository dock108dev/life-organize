import SwiftData
import SwiftUI

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thing.name) private var things: [Thing]
    let event: LedgerEvent?
    let thing: Thing?
    let allowsDelete: Bool

    @State private var title: String
    @State private var occurredAt: Date
    @State private var eventType: LedgerEventType
    @State private var note: String
    @State private var metadataDrafts: [EventMetadataDraft]
    @State private var selectedThingID: UUID?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false

    init(event: LedgerEvent?, thing: Thing?, allowsDelete: Bool = true) {
        self.event = event
        self.thing = thing ?? event?.thing
        self.allowsDelete = allowsDelete
        _title = State(initialValue: event?.title ?? "")
        _occurredAt = State(initialValue: event?.occurredAt ?? DateFormatting.normalizedDateOnly(Date()))
        _eventType = State(initialValue: event?.eventType ?? .generic)
        _note = State(initialValue: event?.note ?? "")
        _metadataDrafts = State(initialValue: event?.metadataEntries.map(EventMetadataDraft.init) ?? [])
        _selectedThingID = State(initialValue: (thing ?? event?.thing)?.id)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty
    }

    private var selectedThing: Thing? {
        things.first { $0.id == selectedThingID }
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                Picker("Type", selection: $eventType) {
                    ForEach(LedgerEventType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
            }

            Section("Linked Thing") {
                ThingSelectionPicker(title: "Thing", things: things, selection: $selectedThingID)
            }

            if !metadataDrafts.isEmpty {
                Section("Metadata") {
                    ForEach($metadataDrafts) { $draft in
                        EventMetadataDraftRow(draft: $draft)
                    }
                    .onDelete { offsets in
                        metadataDrafts.remove(atOffsets: offsets)
                    }
                }
            }

            Section {
                Button {
                    metadataDrafts.append(EventMetadataDraft())
                } label: {
                    Label("Add Metadata", systemImage: "plus")
                }
            }

            Section("Source") {
                SourceDisclosure(sourceMessage: event?.sourceMessage, manualDate: event?.createdAt ?? Date())
            }

            if event != nil && allowsDelete {
                Section {
                    Button("Delete Event", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .ledgerEditFormWidth(.event)
        .navigationTitle(event == nil ? "Add Event" : "Edit Event")
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
        .confirmationDialog("Delete Event?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                deleteEvent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the event. Your timeline entry will remain.")
        }
        .alert(
            "Couldn't Save Event",
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
            let service = DerivedFieldMaintenanceService(modelContext: modelContext)
            let normalizedDate = DateFormatting.normalizedDateOnly(occurredAt)
            if let event {
                let previousThing = event.thing
                event.title = trimmedTitle
                event.occurredAt = normalizedDate
                event.eventType = eventType
                event.metadataEntries = metadataDrafts.compactMap(\.entry)
                event.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                event.thing = selectedThing
                event.updatedAt = Date()
                try service.updateEvent(event, previousThing: previousThing)
            } else {
                let newEvent = LedgerEvent(
                    title: trimmedTitle,
                    occurredAt: normalizedDate,
                    rawText: "",
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    eventType: eventType,
                    metadataEntries: metadataDrafts.compactMap(\.entry),
                    thing: selectedThing
                )
                try service.insertEvent(newEvent)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The event could not be saved."
        }
    }

    private func deleteEvent() {
        guard let event else { return }
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).deleteEvent(event)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The event could not be deleted."
        }
    }
}

private struct EventMetadataDraft: Identifiable {
    let id: UUID
    var key: LedgerEventMetadataKey
    var customKey: String
    var valueKind: LedgerEventMetadataValueKind
    var stringValue: String
    var numberValue: Double?
    var dateValue: Date
    var boolValue: Bool
    var unit: String
    var sourceText: String

    init() {
        id = UUID()
        key = .other
        customKey = ""
        valueKind = .string
        stringValue = ""
        numberValue = nil
        dateValue = DateFormatting.normalizedDateOnly(Date())
        boolValue = false
        unit = ""
        sourceText = ""
    }

    init(entry: LedgerEventMetadataEntry) {
        id = UUID()
        key = entry.key
        customKey = entry.key == .other ? entry.keyRawValue : ""
        valueKind = entry.valueKind
        stringValue = entry.stringValue ?? ""
        numberValue = entry.numberValue
        dateValue = entry.dateValue.flatMap(ExtractionService.parseDate) ?? DateFormatting.normalizedDateOnly(Date())
        boolValue = entry.boolValue ?? false
        unit = entry.unit ?? ""
        sourceText = entry.sourceText ?? ""
    }

    var entry: LedgerEventMetadataEntry? {
        let resolvedKeyRawValue: String
        if key == .other {
            resolvedKeyRawValue = customKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? LedgerEventMetadataKey.other.rawValue
        } else {
            resolvedKeyRawValue = key.rawValue
        }

        let trimmedString = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedDate = DateFormatting.dateOnlyString(
            DateFormatting.normalizedDateOnly(dateValue),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        switch valueKind {
        case .string where trimmedString.isEmpty && trimmedSourceText.isEmpty:
            return nil
        case .number where numberValue == nil:
            return nil
        default:
            return LedgerEventMetadataEntry(
                keyRawValue: resolvedKeyRawValue,
                valueKindRawValue: valueKind.rawValue,
                stringValue: valueKind == .string ? trimmedString.nilIfEmpty : nil,
                numberValue: valueKind == .number ? numberValue : nil,
                dateValue: valueKind == .date ? formattedDate : nil,
                boolValue: valueKind == .boolean ? boolValue : nil,
                unit: trimmedUnit.nilIfEmpty,
                sourceText: trimmedSourceText.nilIfEmpty
            )
        }
    }

}

private struct EventMetadataDraftRow: View {
    @Binding var draft: EventMetadataDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Key", selection: $draft.key) {
                ForEach(LedgerEventMetadataKey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            }

            if draft.key == .other {
                TextField("Custom key", text: $draft.customKey)
                    .textInputAutocapitalization(.never)
            }

            Picker("Value Type", selection: $draft.valueKind) {
                Text("Text").tag(LedgerEventMetadataValueKind.string)
                Text("Number").tag(LedgerEventMetadataValueKind.number)
                Text("Date").tag(LedgerEventMetadataValueKind.date)
                Text("Yes/No").tag(LedgerEventMetadataValueKind.boolean)
            }

            valueEditor

            TextField("Unit", text: $draft.unit)
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch draft.valueKind {
        case .string:
            TextField("Value", text: $draft.stringValue)
        case .number:
            TextField("Value", value: $draft.numberValue, format: .number)
                .keyboardType(.decimalPad)
        case .date:
            DatePicker("Value", selection: $draft.dateValue, displayedComponents: .date)
        case .boolean:
            Toggle("Value", isOn: $draft.boolValue)
        }
    }
}
