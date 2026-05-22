import SwiftUI
import UIKit

enum SettingsClearDataStep: Equatable {
    case exportPrompt
    case exportFailed
    case finalConfirmation
}

struct SettingsClearDataFlow: Equatable {
    var step: SettingsClearDataStep = .exportPrompt

    var offersExportBeforeClear: Bool {
        step == .exportPrompt || step == .exportFailed
    }

    var showsFinalConfirmation: Bool {
        step == .finalConfirmation
    }

    mutating func exportSucceeded() {
        step = .finalConfirmation
    }

    mutating func exportFailed() {
        step = .exportFailed
    }

    mutating func retryExport() {
        step = .exportPrompt
    }

    mutating func continueToConfirmation() {
        step = .finalConfirmation
    }

    mutating func cancel() {
        step = .exportPrompt
    }
}

enum SettingsClearDataCopy {
    static let exportPrompt = "Before clearing, make a local data copy you can save or share yourself. This does not create a cloud backup, sync, or account recovery path."
    static let exportFailedTitle = "Export could not be created"
    static let exportFailedBody = "Your local data is unchanged. You can retry the export, cancel, or continue to the final confirmation without a copy."
    static let finalWarning = "This permanently clears the local record from this device. It cannot be undone."
    static let confirmationInstruction = "Type \(SettingsTrustCopy.clearPhrase) to confirm."
}

struct SettingsClearDataSheet: View {
    @Binding var flow: SettingsClearDataFlow
    @Binding var confirmationText: String
    @Binding var exportShareItem: ExportShareItem?

    let onCancel: () -> Void
    let onExport: () -> Void
    let onClear: () -> Void

    private var isConfirmationValid: Bool {
        confirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(SettingsTrustCopy.clearPhrase) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LedgerNoticeBanner(
                        icon: "exclamationmark.triangle",
                        message: SettingsClearDataCopy.finalWarning,
                        tone: .danger
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        SettingsSafetyRow(content: .clearsLocalRecords)
                        SettingsSafetyRow(content: .keepsSavedToken)
                    }

                    if flow.offersExportBeforeClear {
                        exportPromptSection
                    }

                    if flow.showsFinalConfirmation {
                        finalConfirmationSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Clear local data?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        flow.cancel()
                        onCancel()
                    }
                }

                if flow.showsFinalConfirmation {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear Local Data", role: .destructive) {
                            onClear()
                        }
                        .disabled(!isConfirmationValid)
                    }
                }
            }
            .sheet(item: $exportShareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }

    private var exportPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if flow.step == .exportFailed {
                LedgerNoticeBanner(
                    icon: "exclamationmark.triangle",
                    message: "\(SettingsClearDataCopy.exportFailedTitle). \(SettingsClearDataCopy.exportFailedBody)",
                    tone: .danger
                )
            } else {
                Text(SettingsClearDataCopy.exportPrompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(flow.step == .exportFailed ? "Retry Export" : "Export Local Copy") {
                    flow.retryExport()
                    onExport()
                }
                .buttonStyle(.borderedProminent)

                Button("Continue to Confirmation", role: .destructive) {
                    flow.continueToConfirmation()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var finalConfirmationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SettingsClearDataCopy.confirmationInstruction)
                .font(.subheadline.weight(.semibold))

            TextField(SettingsTrustCopy.clearPhrase, text: $confirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsSafetyRow: View {
    let content: SettingsSafetyRowContent

    var body: some View {
        LedgerRow(
            primary: content.title,
            secondary: [LedgerRowLine(text: content.detail, lineLimit: 2)],
            density: .compact
        ) {
            LedgerPill(text: content.pillText, tone: content.tone, size: .small)
        } accessory: {
            Image(systemName: content.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(content.tone.foreground)
                .accessibilityHidden(true)
        }
    }
}

struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
