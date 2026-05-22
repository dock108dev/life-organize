import SwiftData
import SwiftUI

struct ThingEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thing.name) private var things: [Thing]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    let existingThing: Thing?
    let onSave: (Thing) throws -> Void

    @State private var name: String
    @State private var details: String
    @State private var aliasesText: String
    @State private var category: ThingCategory?
    @State private var errorMessage: String?

    init(existingThing: Thing?, onSave: @escaping (Thing) throws -> Void) {
        self.existingThing = existingThing
        self.onSave = onSave
        _name = State(initialValue: existingThing?.name ?? "")
        _details = State(initialValue: existingThing?.details ?? "")
        _aliasesText = State(initialValue: existingThing?.aliases.joined(separator: "\n") ?? "")
        _category = State(initialValue: existingThing?.category)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var aliases: [String] {
        aliasesText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var duplicateNameExists: Bool {
        duplicateCandidate != nil
    }

    private var duplicateCandidate: Thing? {
        let draftKeys = Set(([trimmedName] + aliases).map(ThingNormalizer.normalizeKey).filter { !$0.isEmpty })
        guard !draftKeys.isEmpty else { return nil }
        if let exact = things.first(where: { thing in
            thing.id != existingThing?.id && !draftKeys.isDisjoint(with: duplicateKeys(for: thing))
        }) {
            return exact
        }
        let candidates = ThingNormalizer.candidates(
            for: trimmedName,
            aliases: aliases,
            categoryHint: category?.rawValue,
            contextText: [trimmedName, details, aliasesText].joined(separator: " "),
            existingThings: things.filter { $0.id != existingThing?.id }
        )
        guard let candidateID = candidates.first(where: { $0.tier != .low })?.targetThingID else {
            return nil
        }
        return things.first { $0.id == candidateID }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !duplicateNameExists
    }

    private var thingSourceMessage: ChatMessage? {
        guard let existingThing else { return nil }
        return messages.first { existingThing.sourceMessageIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            Section("Thing") {
                TextField("Name", text: $name)
                TextField("Details", text: $details, axis: .vertical)
                TextField("Aliases", text: $aliasesText, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Category", selection: $category) {
                    Text("None").tag(nil as ThingCategory?)
                    ForEach(ThingCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category as ThingCategory?)
                    }
                }

                if duplicateNameExists {
                    Text(duplicateMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if existingThing != nil, let duplicateCandidate {
                        Button("Merge with \(duplicateCandidate.name)") {
                            merge(into: duplicateCandidate)
                        }
                    }
                }
            }

            if let existingThing {
                Section("Record Info") {
                    MetadataRow(label: "Events", value: "\(existingThing.eventCount)")
                    MetadataRow(label: "Active reminders", value: "\(existingThing.activeRules.count)")
                    MetadataRow(label: "Notes", value: "\(existingThing.notes.count)")
                    SourceDisclosure(
                        sourceMessage: thingSourceMessage,
                        manualDate: existingThing.createdAt,
                        extractedIDs: existingThing.sourceMessageIDs + existingThing.sourceExtractionAttemptIDs
                    )
                }
            }
        }
        .navigationTitle(existingThing == nil ? "Add Thing" : "Edit Thing")
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
            "Couldn't Save Thing",
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
            let thing = existingThing ?? Thing(name: trimmedName)
            thing.name = trimmedName
            thing.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            thing.category = category
            DerivedFieldMaintenanceService.updateThingFields(thing, aliases: aliases)
            try onSave(thing)
            dismiss()
        } catch {
            errorMessage = "The thing could not be saved."
        }
    }

    private var duplicateMessage: String {
        guard let duplicateCandidate else {
            return "A thing with this name already exists."
        }
        return "\(duplicateCandidate.name) already matches this name or alias."
    }

    private func merge(into target: Thing) {
        guard let existingThing else { return }
        do {
            existingThing.name = trimmedName
            existingThing.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            existingThing.category = category
            DerivedFieldMaintenanceService.updateThingFields(existingThing, aliases: aliases)
            try DerivedFieldMaintenanceService(modelContext: modelContext).mergeThing(existingThing, into: target)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The things could not be merged."
        }
    }

    private func duplicateKeys(for thing: Thing) -> Set<String> {
        Set(
            ([thing.normalizedKey, ThingNormalizer.normalizeKey(thing.name)] + thing.aliases.map(ThingNormalizer.normalizeKey))
                .filter { !$0.isEmpty }
        )
    }
}
