import SwiftUI

struct ExtractionAttemptDebugView: View {
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case request = "Request"
        case raw = "Raw"
        case parsed = "Parsed"
        case error = "Error"
        case entities = "Entities"

        var id: String { rawValue }
    }

    let attempt: ExtractionAttempt
    let deviceTokenStore: any DeviceTokenStore
    @State private var tab: Tab = .overview

    init(attempt: ExtractionAttempt, deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore()) {
        self.attempt = attempt
        self.deviceTokenStore = deviceTokenStore
    }

    var body: some View {
        Group {
            if debugAccessPolicy.allowsExtractionDebugScreens {
                VStack(spacing: 0) {
                    Picker("Debug Section", selection: $tab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    switch tab {
                    case .overview:
                        ExtractionAttemptOverview(attempt: attempt, deviceTokenStore: deviceTokenStore)
                    case .request:
                        DebugTextViewer(title: "Request JSON", text: attempt.requestJSON)
                    case .raw:
                        DebugTextViewer(
                            title: "Raw Response",
                            text: attempt.rawResponseText?.nilIfEmpty ?? attempt.sourceMessage?.rawLLMResponse
                        )
                    case .parsed:
                        DebugJSONViewer(title: "Normalized JSON", jsonText: attempt.normalizedJSONText)
                    case .error:
                        ExtractionAttemptErrorView(attempt: attempt)
                    case .entities:
                        ExtractionAttemptEntityAuditView(attempt: attempt)
                    }
                }
            } else {
                DeveloperModeRequiredView(content: .extractionDebug)
            }
        }
        .navigationTitle("Extraction Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DeveloperModeRequiredContent: Equatable {
    let title: String
    let systemImage: String
    let description: String

    static let extractionDebug = DeveloperModeRequiredContent(
        title: "Developer Mode Required",
        systemImage: "lock",
        description: "Unlock developer mode from Settings to view diagnostics."
    )

    static let internalQA = DeveloperModeRequiredContent(
        title: "Developer Mode Required",
        systemImage: "lock",
        description: "Unlock developer mode from Settings to use internal QA tools."
    )
}

enum ExtractionDebugAccessPresentation: Equatable {
    case attemptsList
    case requiredGate(DeveloperModeRequiredContent)
}

struct DeveloperModeRequiredView: View {
    let content: DeveloperModeRequiredContent

    var body: some View {
        ContentUnavailableView(
            content.title,
            systemImage: content.systemImage,
            description: Text(content.description)
        )
    }
}

private struct ExtractionAttemptOverview: View {
    let attempt: ExtractionAttempt
    let deviceTokenStore: any DeviceTokenStore

    var body: some View {
        Form {
            Section("Source") {
                DebugMetadataRow(label: "Message ID", value: attempt.sourceMessage?.id.uuidString ?? "None")
                DebugMetadataRow(label: "Role", value: attempt.sourceMessage?.role.rawValue ?? "None")
                if let message = attempt.sourceMessage {
                    ExtractionStatusChip(status: message.extractionStatus)
                    Text(message.text)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            Section("Attempt") {
                ExtractionAttemptStatusChip(status: attempt.status)
                DebugMetadataRow(label: "Attempt ID", value: attempt.id.uuidString)
                DebugMetadataRow(label: "Model", value: attempt.modelName ?? "Unknown")
                DebugMetadataRow(label: "Prompt", value: attempt.promptVersion)
                DebugMetadataRow(label: "Schema", value: "\(attempt.schemaVersion)")
                DebugMetadataRow(label: "Started", value: ExtractionDebugFormatting.text(for: attempt.startedAt))
                DebugMetadataRow(label: "Completed", value: ExtractionDebugFormatting.text(for: attempt.completedAt))
                DebugMetadataRow(label: "Duration", value: ExtractionDebugFormatting.duration(start: attempt.startedAt, end: attempt.completedAt))
            }

            Section("Payloads") {
                DebugMetadataRow(label: "Request JSON", value: payloadState(attempt.requestJSON))
                DebugMetadataRow(label: "Raw response", value: payloadState(attempt.rawResponseText ?? attempt.sourceMessage?.rawLLMResponse))
                DebugMetadataRow(label: "Normalized JSON", value: payloadState(attempt.normalizedJSONText))
                DebugMetadataRow(label: "Error", value: attempt.errorMessage == nil ? "None" : "Stored")
            }

            Section("Created Records") {
                DebugMetadataRow(label: "Things", value: "\(attempt.createdThingIDs.count)")
                DebugMetadataRow(label: "Events", value: "\(attempt.createdEventIDs.count)")
                DebugMetadataRow(label: "Reminders", value: "\(attempt.createdRuleIDs.count)")
                DebugMetadataRow(label: "Notes", value: "\(attempt.createdNoteIDs.count)")
            }

            Section("Retry") {
                ManualExtractionRetryButton(message: attempt.sourceMessage, deviceTokenStore: deviceTokenStore)
            }
        }
    }

    private func payloadState(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "Missing" }
        return "Stored"
    }
}

private struct ExtractionAttemptErrorView: View {
    let attempt: ExtractionAttempt

    var body: some View {
        Form {
            Section("Attempt Error") {
                DebugMetadataRow(label: "Status", value: attempt.status.rawValue)
                DebugMetadataRow(label: "Code", value: attempt.errorCode?.rawValue ?? "None")
                DebugMetadataRow(label: "Message", value: attempt.errorMessage ?? "None")
            }

            Section("Message Error") {
                DebugMetadataRow(label: "Status", value: attempt.sourceMessage?.extractionStatus.rawValue ?? "None")
                DebugMetadataRow(label: "Code", value: attempt.sourceMessage?.extractionErrorCode?.rawValue ?? "None")
                DebugMetadataRow(label: "Message", value: attempt.sourceMessage?.extractionError ?? "None")
                DebugMetadataRow(label: "Attempt count", value: "\(attempt.sourceMessage?.extractionAttemptCount ?? 0)")
                DebugMetadataRow(label: "Last attempt", value: ExtractionDebugFormatting.text(for: attempt.sourceMessage?.lastExtractionAttemptAt))
                DebugMetadataRow(label: "Next retry", value: ExtractionDebugFormatting.text(for: attempt.sourceMessage?.nextExtractionRetryAt))
            }
        }
    }
}

private struct ExtractionAttemptEntityAuditView: View {
    let attempt: ExtractionAttempt

    var body: some View {
        List {
            entitySection("Thing IDs", ids: attempt.createdThingIDs)
            entitySection("Event IDs", ids: attempt.createdEventIDs)
            entitySection("Reminder IDs", ids: attempt.createdRuleIDs)
            entitySection("Note IDs", ids: attempt.createdNoteIDs)
        }
    }

    private func entitySection(_ title: String, ids: [UUID]) -> some View {
        Section(title) {
            if ids.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ids.map(\.uuidString), id: \.self) { id in
                    Text(id)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
