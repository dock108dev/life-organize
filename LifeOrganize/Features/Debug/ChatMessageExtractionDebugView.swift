import SwiftUI

struct ChatMessageExtractionDebugView: View {
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy

    let message: ChatMessage
    let apiKeyStore: any APIKeyStore

    init(message: ChatMessage, apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()) {
        self.message = message
        self.apiKeyStore = apiKeyStore
    }

    var body: some View {
        Group {
            if debugAccessPolicy.allowsExtractionDebugScreens {
                List {
                    Section("Message") {
                        DebugMetadataRow(label: "Message ID", value: message.id.uuidString)
                        DebugMetadataRow(label: "Role", value: message.role.rawValue)
                        DebugMetadataRow(label: "Created", value: ExtractionDebugFormatting.text(for: message.createdAt))
                        DebugMetadataRow(label: "Extraction version", value: "\(message.extractionVersion)")
                        ExtractionStatusChip(status: message.extractionStatus)
                        Text(message.text)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }

                    Section("Retry State") {
                        DebugMetadataRow(label: "Attempt count", value: "\(message.extractionAttemptCount)")
                        DebugMetadataRow(label: "Last attempt", value: ExtractionDebugFormatting.text(for: message.lastExtractionAttemptAt))
                        DebugMetadataRow(label: "Next retry", value: ExtractionDebugFormatting.text(for: message.nextExtractionRetryAt))
                        DebugMetadataRow(label: "Error code", value: message.extractionErrorCode?.rawValue ?? "None")
                        DebugMetadataRow(label: "Error", value: message.extractionError ?? "None")
                    }

                    Section("Message Raw Response") {
                        NavigationLink("View raw response") {
                            DebugTextViewer(title: "Message Raw Response", text: message.rawLLMResponse)
                        }
                    }

                    Section("Retry") {
                        ManualExtractionRetryButton(message: message, apiKeyStore: apiKeyStore)
                    }

                    Section("Attempts") {
                        ForEach(message.extractionAttempts.sorted { $0.startedAt > $1.startedAt }) { attempt in
                            NavigationLink {
                                ExtractionAttemptDebugView(attempt: attempt, apiKeyStore: apiKeyStore)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ExtractionAttemptStatusChip(status: attempt.status)
                                    Text(ExtractionDebugFormatting.dateTime.string(from: attempt.startedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(attempt.id.uuidString)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                DeveloperModeRequiredView(content: .extractionDebug)
            }
        }
        .navigationTitle("Message Extraction")
        .navigationBarTitleDisplayMode(.inline)
    }
}
