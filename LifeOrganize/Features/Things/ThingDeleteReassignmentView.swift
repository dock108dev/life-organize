import SwiftUI

struct ThingDeleteReassignmentView: View {
    let source: Thing
    let targets: [Thing]
    let onCancel: () -> Void
    let onDelete: (Thing) -> Void

    @State private var selectedThingID: UUID?

    init(source: Thing, targets: [Thing], onCancel: @escaping () -> Void, onDelete: @escaping (Thing) -> Void) {
        self.source = source
        self.targets = targets
        self.onCancel = onCancel
        self.onDelete = onDelete
        _selectedThingID = State(initialValue: targets.first?.id)
    }

    private var selectedThing: Thing? {
        targets.first { $0.id == selectedThingID }
    }

    var body: some View {
        Form {
            Section("Move Records") {
                Text("Events, reminders, and notes linked to \(source.name) will move to the selected Thing before \(source.name) is removed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ThingSelectionPicker(title: "Destination", things: targets, selection: $selectedThingID, includesNone: false)
            }
        }
        .ledgerEditFormWidth(.deleteReassignment)
        .navigationTitle("Move & Delete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Delete") {
                    if let selectedThing {
                        onDelete(selectedThing)
                    }
                }
                .disabled(selectedThing == nil)
            }
        }
    }
}
