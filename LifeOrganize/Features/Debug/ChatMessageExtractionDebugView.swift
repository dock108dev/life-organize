import SwiftUI

struct ChatMessageExtractionDebugView: View {
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy

    let message: ChatMessage
    let deviceTokenStore: any DeviceTokenStore

    init(message: ChatMessage, deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore()) {
        self.message = message
        self.deviceTokenStore = deviceTokenStore
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
                            .frame(maxWidth: LedgerAdaptiveLayout.Width.debugDetailMax, alignment: .leading)
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
                        ManualExtractionRetryButton(message: message, deviceTokenStore: deviceTokenStore)
                    }

                    Section("Attempts") {
                        ForEach(message.extractionAttempts.sorted { $0.startedAt > $1.startedAt }) { attempt in
                            NavigationLink {
                                ExtractionAttemptDebugView(attempt: attempt, deviceTokenStore: deviceTokenStore)
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
                                .frame(maxWidth: LedgerAdaptiveLayout.Width.debugListMax, alignment: .leading)
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
