import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState
    @EnvironmentObject private var developerModeState: DeveloperModeState

    let deviceTokenStore: any DeviceTokenStore
    let onLocalDataCleared: () -> Void

    @State private var savedTokenDescription: String?
    @State private var feedback: SettingsFeedback?
    @State private var isShowingResetTokenConfirmation = false
    @State private var isShowingClearDataConfirmation = false
    @State private var isShowingClearDataSheet = false
    @State private var clearDataFlow = SettingsClearDataFlow()
    @State private var clearDataConfirmationText = ""
    @State private var exportShareItem: ExportShareItem?
    @State private var isShowingExportFailure = false

    init(
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore(),
        onLocalDataCleared: @escaping () -> Void = {}
    ) {
        self.deviceTokenStore = deviceTokenStore
        self.onLocalDataCleared = onLocalDataCleared
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    feedbackNotice
                    missingTokenNotice

                    settingsDivider
                    deviceTokenSection
                    settingsDivider
                    exportSection
                    settingsDivider
                    clearDataSection

                    if Self.showsDeveloperDiagnostics(for: developerModeState.policy) {
                        settingsDivider
                        developerDiagnosticsSection
                    }

                    settingsDivider
                    versionFooter
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LedgerScreenBackground().ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings-done-button")
                }
            }
            .task {
                reloadSavedTokenState()
            }
            .confirmationDialog(
                "Reset service token?",
                isPresented: $isShowingResetTokenConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset service token", role: .destructive) {
                    deleteDeviceToken()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("New entries will still be saved locally. The app will create a new token next time.")
            }
            .confirmationDialog(
                "Clear local data?",
                isPresented: $isShowingClearDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Continue", role: .destructive) {
                    clearDataConfirmationText = ""
                    clearDataFlow = SettingsClearDataFlow()
                    isShowingClearDataSheet = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(SettingsTrustCopy.clearDeletes) \(SettingsTrustCopy.clearKeeps) This cannot be undone.")
            }
            .sheet(isPresented: $isShowingClearDataSheet) {
                SettingsClearDataSheet(
                    flow: $clearDataFlow,
                    confirmationText: $clearDataConfirmationText,
                    exportShareItem: $exportShareItem,
                    onCancel: {
                        clearDataConfirmationText = ""
                        isShowingClearDataSheet = false
                    },
                    onExport: exportLocalJSONFromClearFlow,
                    onClear: clearLocalData
                )
            }
            .sheet(item: $exportShareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            .alert("Export failed.", isPresented: $isShowingExportFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(SettingsFeedback.exportFailed.message)
            }
        }
    }

    @ViewBuilder private var feedbackNotice: some View {
        if let feedback {
            LedgerNoticeBanner(
                icon: feedback.icon,
                message: feedback.message,
                tone: feedback.isError ? .danger : .success,
                accessibilityIdentifier: "settings-feedback"
            )
        }
    }

    @ViewBuilder private var missingTokenNotice: some View {
        if savedTokenDescription == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(LedgerEmptyStateContent.settingsNoDeviceToken.title)
                    .font(.subheadline.weight(.semibold))

                LedgerNoticeBanner(
                    icon: "wifi.exclamationmark",
                    message: LedgerEmptyStateContent.settingsNoDeviceToken.body,
                    actionTitle: "Prepare Service",
                    accessibilityIdentifier: "settings-no-device-token",
                    action: prepareServiceToken
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trust & Preferences")
                .font(.title3.weight(.semibold))
            Text("Local controls for what carries forward.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(Color(.separator).opacity(0.35))
    }

    private var deviceTokenSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            sectionHeader(
                title: SettingsTrustCopy.deviceTokenTitle,
                icon: "server.rack",
                tone: savedTokenDescription == nil ? .neutral : .success
            ) {
                if let savedTokenDescription {
                    LedgerPill(text: savedTokenDescription, tone: .success, size: .small)
                } else {
                    LedgerPill(text: "Local only", tone: .muted, size: .small)
                }
            }

            Text(SettingsTrustCopy.deviceTokenBody)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(savedTokenDescription == nil
                ? SettingsTrustCopy.noTokenDetail
                : SettingsTrustCopy.savedTokenDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("device-token-status")

            HStack(spacing: 10) {
                Button(savedTokenDescription == nil ? "Prepare Service" : "Refresh Token") {
                    savedTokenDescription == nil ? prepareServiceToken() : (isShowingResetTokenConfirmation = true)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("device-token-save-button")
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            sectionHeader(title: SettingsTrustCopy.exportTitle, icon: "square.and.arrow.up", tone: .info) {
                LedgerPill(text: "Portable copy", tone: .info, size: .small)
            }

            Text(SettingsTrustCopy.exportBody)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(V1ScopeContract.SettingsRow.exportLocalJSON.title) {
                exportLocalJSON()
            }
            .buttonStyle(.bordered)
        }
    }

    private var clearDataSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            sectionHeader(title: SettingsTrustCopy.clearTitle, icon: "trash", tone: .danger) {
                LedgerPill(text: "Strong confirmation", tone: .danger, size: .small)
            }

            Text(SettingsTrustCopy.clearBody)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                SettingsSafetyRow(content: .clearsLocalRecords)
                SettingsSafetyRow(content: .keepsSavedToken)
            }

            Button(V1ScopeContract.SettingsRow.clearLocalData.title, role: .destructive) {
                isShowingClearDataConfirmation = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var developerDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            sectionHeader(title: "Developer Diagnostics", icon: "wrench.and.screwdriver", tone: .attention) {
                LedgerPill(text: "Unlocked", tone: .attention, size: .small)
            }

            Text("Local troubleshooting and QA tools.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Developer mode unlocked")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    ExtractionDebugListView(deviceTokenStore: deviceTokenStore)
                } label: {
                    Label("Extraction Attempts", systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    ExtractionDebugListView(deviceTokenStore: deviceTokenStore, initialFilter: .failed)
                } label: {
                    Label("Failed Extractions", systemImage: "exclamationmark.triangle")
                }

                NavigationLink {
                    InternalQALabView(deviceTokenStore: deviceTokenStore)
                } label: {
                    Label("Internal QA Lab", systemImage: "testtube.2")
                }
            }

            Button("Lock Developer Mode") {
                developerModeState.lock()
            }
            .font(.footnote.weight(.medium))
        }
    }

    private func sectionHeader<Accessory: View>(
        title: String,
        icon: String,
        tone: LedgerTone,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)

            Spacer(minLength: 8)

            accessory()
        }
        .accessibilityElement(children: .combine)
    }

    private var versionFooter: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("LifeOrganize \(appVersionDescription)")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .onLongPressGesture {
                developerModeState.unlock()
            }
        }
    }

    private var appVersionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

}

extension SettingsView {
    private func reloadSavedTokenState() {
        do {
            savedTokenDescription = try deviceTokenStore.loadDeviceToken().map(maskedTokenDescription)
        } catch {
            savedTokenDescription = nil
            feedback = .deviceTokenReadFailed
        }
    }

    private func deleteDeviceToken() {
        do {
            try deviceTokenStore.deleteDeviceToken()
            _ = try deviceTokenStore.ensureDeviceToken()
            reloadSavedTokenState()
            feedback = .deviceTokenReplaced
        } catch {
            feedback = .deviceTokenRemoveFailed
        }
    }

    private func prepareServiceToken() {
        do {
            _ = try deviceTokenStore.ensureDeviceToken()
            reloadSavedTokenState()
            feedback = .deviceTokenSaved

            let retryService = PendingExtractionRetryService(
                modelContext: modelContext,
                deviceTokenStore: deviceTokenStore,
                dataGeneration: sessionState.dataGeneration,
                isDataGenerationCurrent: sessionState.isCurrentDataGeneration
            )
            try retryService.markPendingTokenMessagesRetryable()
            Task {
                try? await retryService.retryRecentPendingMessages()
            }
        } catch {
            feedback = .deviceTokenSaveFailed
        }
    }

    private func clearLocalData() {
        do {
            sessionState.invalidateInFlightDataWork()
            try LocalDataClearService(modelContext: modelContext).clearLedgerData()
            sessionState.reloadAfterLocalDataClear()
            clearDataConfirmationText = ""
            clearDataFlow = SettingsClearDataFlow()
            isShowingClearDataSheet = false
            feedback = .localDataCleared
            onLocalDataCleared()
        } catch {
            feedback = .clearDataFailed
        }
    }

    private func exportLocalJSON() {
        do {
            let url = try LocalJSONExportService(modelContext: modelContext).writeExportFile()
            exportShareItem = ExportShareItem(url: url)
            feedback = .exportReady
        } catch {
            feedback = .exportFailed
            isShowingExportFailure = true
        }
    }

    private func exportLocalJSONFromClearFlow() {
        do {
            let url = try LocalJSONExportService(modelContext: modelContext).writeExportFile()
            exportShareItem = ExportShareItem(url: url)
            clearDataFlow.exportSucceeded()
            feedback = .exportReady
        } catch {
            clearDataFlow.exportFailed()
        }
    }

    private func maskedTokenDescription(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else {
            return "Saved on this device"
        }
        return "Saved on this device, ends in \(trimmed.suffix(4))"
    }

    static func showsDeveloperDiagnostics(for policy: DebugAccessPolicy) -> Bool {
        policy.allowsExtractionDebugScreens
    }
}
