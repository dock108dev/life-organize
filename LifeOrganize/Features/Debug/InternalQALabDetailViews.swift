import SwiftData
import SwiftUI

struct QAReprocessEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]

    let apiKeyStore: any APIKeyStore
    @State private var statusText: String?
    @State private var reprocessingID: UUID?

    private var retryableMessages: [ChatMessage] {
        let service = QAReprocessService(modelContext: modelContext, apiKeyStore: apiKeyStore)
        return (try? service.retryableMessages()) ?? []
    }

    var body: some View {
        List {
            if let statusText {
                Section("Last Result") {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Retryable Entries") {
                if retryableMessages.isEmpty {
                    ContentUnavailableView("No Retryable Entries", systemImage: "checkmark.circle")
                } else {
                    ForEach(retryableMessages) { message in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.text)
                                .lineLimit(3)
                            Text(message.extractionStatus.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(reprocessingID == message.id ? "Reprocessing..." : "Reprocess") {
                                reprocess(message)
                            }
                            .buttonStyle(.bordered)
                            .disabled(reprocessingID != nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("All Source Entries") {
                Text("\(messages.count) source entries in the local store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Reprocess Entry")
    }

    private func reprocess(_ message: ChatMessage) {
        let messageID = message.id
        reprocessingID = messageID
        Task {
            do {
                try await QAReprocessService(modelContext: modelContext, apiKeyStore: apiKeyStore).reprocess(messageID: messageID)
                statusText = "Entry reprocessed."
            } catch {
                statusText = error.localizedDescription
            }
            reprocessingID = nil
        }
    }
}

struct QAGraphInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var result: QAGraphInspectionResult?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                Button("Run Graph Inspection") {
                    inspect()
                }
            }

            if let errorText {
                Section("Error") {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let result {
                Section("Integrity Findings") {
                    if result.integrity.failures.isEmpty {
                        Label("No relationship integrity findings", systemImage: "checkmark.circle")
                    } else {
                        ForEach(result.integrity.failures, id: \.description) { failure in
                            findingRow(failure)
                        }
                    }
                }

                Section("Orphaned Links") {
                    if result.orphanedLinks.isEmpty {
                        Text("No orphaned links found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(result.orphanedLinks, id: \.description) { failure in
                            findingRow(failure)
                        }
                    }
                }

                Section("Extraction Provenance") {
                    if result.provenanceRows.isEmpty {
                        Text("No extracted records found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(result.provenanceRows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                Text("\(row.recordType) \(row.recordID.uuidString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let sourceMessageID = row.sourceMessageID {
                                    Text("Source \(sourceMessageID.uuidString)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let extractionAttemptID = row.extractionAttemptID {
                                    Text("Attempt \(extractionAttemptID.uuidString)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Affected Source Records") {
                    if result.affectedSourceRecords.isEmpty {
                        Text("No affected source records.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(result.affectedSourceRecords) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title)
                                Text(source.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Graph Inspector")
        .task {
            if result == nil {
                inspect()
            }
        }
    }

    private func findingRow(_ failure: RelationshipIntegrityFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.code)
                .font(.subheadline.weight(.semibold))
            Text(failure.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func inspect() {
        do {
            result = try QAGraphInspectionService(modelContext: modelContext, now: QAFakeDateStore().effectiveNow()).inspect()
            errorText = nil
        } catch {
            result = nil
            errorText = error.localizedDescription
        }
    }
}
