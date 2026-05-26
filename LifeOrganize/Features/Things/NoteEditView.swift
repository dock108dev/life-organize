import SwiftData
import SwiftUI

struct NoteEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thing.name) private var things: [Thing]
    let note: LedgerNote?
    let thing: Thing?

    @State private var text: String
    @State private var selectedThingID: UUID?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false

    init(note: LedgerNote?, thing: Thing?) {
        self.note = note
        self.thing = thing
        _text = State(initialValue: note?.text ?? "")
        _selectedThingID = State(initialValue: thing?.id ?? note?.linkedThings.first?.id)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedText.isEmpty
    }

    private var selectedThing: Thing? {
        things.first { $0.id == selectedThingID }
    }

    var body: some View {
        Form {
            Section("Note") {
                TextField("Note", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Linked Thing") {
                ThingSelectionPicker(title: "Thing", things: things, selection: $selectedThingID)
            }

            Section("Source") {
                SourceDisclosure(sourceMessage: note?.sourceMessage, manualDate: note?.createdAt ?? Date())
            }

            if note != nil {
                Section {
                    Button("Delete Note", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .ledgerEditFormWidth(.note)
        .navigationTitle(note == nil ? "Add Note" : "Edit Note")
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
        .confirmationDialog("Delete Note?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the note. Your timeline entry will remain.")
        }
        .alert(
            "Couldn't Save Note",
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
            if let note {
                let previousThings = note.linkedThings
                note.text = trimmedText
                note.updatedAt = Date()
                if let selectedThing {
                    note.linkedThings = [selectedThing]
                } else {
                    note.linkedThings = []
                }
                try service.updateNote(note, previousThings: previousThings)
            } else {
                let note = LedgerNote(text: trimmedText, linkedThings: selectedThing.map { [$0] } ?? [])
                try service.insertNote(note)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The note could not be saved."
        }
    }

    private func deleteNote() {
        guard let note else { return }
        do {
            try DerivedFieldMaintenanceService(modelContext: modelContext).deleteNote(note)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The note could not be deleted."
        }
    }
}
