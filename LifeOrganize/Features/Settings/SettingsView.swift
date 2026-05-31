import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState
    @EnvironmentObject private var developerModeState: DeveloperModeState

    let deviceTokenStore: any DeviceTokenStore
    let showsDoneButton: Bool
    let embedsNavigationStack: Bool
    let onLocalDataCleared: () -> Void

    @State private var feedback: SettingsFeedback?
    @State private var isShowingClearDataConfirmation = false
    @State private var isShowingClearDataSheet = false
    @State private var clearDataFlow = SettingsClearDataFlow()
    @State private var clearDataConfirmationText = ""
    @State private var settingsExportShareItem: ExportShareItem?
    @State private var clearDataExportShareItem: ExportShareItem?
    @State private var isShowingExportFailure = false
    @State private var activeDeveloperDestination: SettingsDeveloperDestination?

    init(
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore(),
        showsDoneButton: Bool = true,
        embedsNavigationStack: Bool = true,
        onLocalDataCleared: @escaping () -> Void = {}
    ) {
        self.deviceTokenStore = deviceTokenStore
        self.showsDoneButton = showsDoneButton
        self.embedsNavigationStack = embedsNavigationStack
        self.onLocalDataCleared = onLocalDataCleared
    }

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                settingsContent
            }
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.surfaceStack) {
                feedbackNotice
                exportSection
                clearDataSection

                if Self.showsDeveloperDiagnostics(for: developerModeState.policy) {
                    developerDiagnosticsSection
                }

                versionFooter
            }
            .frame(maxWidth: LedgerAdaptiveLayout.Workspace.settingsContentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, LedgerAdaptiveLayout.Gutter.regular)
            .padding(.vertical, LedgerAdaptiveLayout.Workspace.contentVerticalPadding)
        }
        .background(LedgerScreenBackground().ignoresSafeArea())
        .accessibilityIdentifier("settings-workspace")
        .navigationTitle("Settings")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings-done-button")
                }
            }
        }
        .navigationDestination(item: $activeDeveloperDestination) { destination in
            if Self.showsDeveloperDiagnostics(for: developerModeState.policy) {
                developerDestinationView(for: destination)
            } else {
                EmptyView()
            }
        }
        .onChange(of: developerModeState.policy) { _, policy in
            if !Self.showsDeveloperDiagnostics(for: policy) {
                activeDeveloperDestination = nil
            }
        }
        .confirmationDialog(
            "Clear local data?",
            isPresented: $isShowingClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                clearDataConfirmationText = ""
                clearDataFlow = SettingsClearDataFlow()
                clearDataExportShareItem = nil
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
                exportShareItem: $clearDataExportShareItem,
                onCancel: {
                    clearDataConfirmationText = ""
                    clearDataExportShareItem = nil
                    isShowingClearDataSheet = false
                },
                onExport: exportLocalJSONFromClearFlow,
                onClear: clearLocalData
            )
        }
        .sheet(item: $settingsExportShareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("Export failed.", isPresented: $isShowingExportFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(SettingsFeedback.exportFailed.message)
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

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            LedgerSectionTitle(title: SettingsTrustCopy.exportTitle, icon: "square.and.arrow.up", tone: .info) {
                LedgerPill(text: "Portable copy", tone: .info, size: .small)
            }

            Text(SettingsTrustCopy.exportBody)
                .font(LedgerVisualSystem.Typography.sectionBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(V1ScopeContract.SettingsRow.exportLocalJSON.title) {
                exportLocalJSON()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings-export-button")
        }
        .settingsSurface(tint: .info)
    }

    private var clearDataSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            LedgerSectionTitle(title: SettingsTrustCopy.clearTitle, icon: "trash", tone: .danger)

            Text(SettingsTrustCopy.clearBody)
                .font(LedgerVisualSystem.Typography.sectionBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(V1ScopeContract.SettingsRow.clearLocalData.title, role: .destructive) {
                isShowingClearDataConfirmation = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings-clear-data-button")
        }
        .settingsSurface(tint: .danger)
    }

    private var developerDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            LedgerSectionTitle(title: "Developer Diagnostics", icon: "wrench.and.screwdriver", tone: .attention) {
                LedgerPill(text: "Unlocked", tone: .attention, size: .small)
            }

            Text("Local troubleshooting and QA tools.")
                .font(LedgerVisualSystem.Typography.sectionBody)
                .foregroundStyle(.secondary)

            Text("Developer mode unlocked")
                .font(LedgerVisualSystem.Typography.sectionFooter)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsDeveloperDestination.allCases) { destination in
                    Button {
                        activeDeveloperDestination = destination
                    } label: {
                        LedgerRow(
                            primary: destination.title,
                            secondary: [
                                LedgerRowLine(
                                    text: destination.detail,
                                    tone: .muted,
                                    role: .contentPreview,
                                    lineLimit: 1
                                )
                            ],
                            surfaceDensity: .searchResultRow,
                            badges: {
                                EmptyView()
                            },
                            accessory: {
                                LedgerIcon(systemName: destination.systemImage, context: .cardList, tone: destination.tone)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(destination.title)
                }
            }

            Button("Lock Developer Mode") {
                developerModeState.lock()
            }
            .font(LedgerVisualSystem.Typography.sectionBody.weight(.medium))
        }
        .settingsSurface(tint: .attention)
    }

    private var versionFooter: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("LifeOrganize \(appVersionDescription)")
                    .font(LedgerVisualSystem.Typography.sectionBody)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("settings-version-footer")
                    .onTapGesture {
                        if AppRuntimeConfiguration.current.isAutomationRuntime {
                            developerModeState.unlock()
                        }
                    }
                    .onLongPressGesture {
                        developerModeState.unlock()
                    }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
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
    private func clearLocalData() {
        do {
            sessionState.invalidateInFlightDataWork()
            try LocalDataClearService(modelContext: modelContext).clearLedgerData()
            sessionState.reloadAfterLocalDataClear()
            clearDataConfirmationText = ""
            clearDataFlow = SettingsClearDataFlow()
            clearDataExportShareItem = nil
            isShowingClearDataSheet = false
            feedback = .localDataCleared
            onLocalDataCleared()
        } catch {
            LocalDiagnosticEventStore().record(
                severity: .error,
                category: "settings",
                operation: "clear_local_data",
                error: error
            )
            feedback = .clearDataFailed
        }
    }

    private func exportLocalJSON() {
        do {
            let url = try LocalJSONExportService(modelContext: modelContext).writeExportFile()
            settingsExportShareItem = ExportShareItem(url: url)
            feedback = .exportReady
        } catch {
            LocalDiagnosticEventStore().record(
                severity: .error,
                category: "settings",
                operation: "export_local_json",
                error: error
            )
            feedback = .exportFailed
            isShowingExportFailure = true
        }
    }

    private func exportLocalJSONFromClearFlow() {
        do {
            let url = try LocalJSONExportService(modelContext: modelContext).writeExportFile()
            clearDataExportShareItem = ExportShareItem(url: url)
            clearDataFlow.exportSucceeded()
            feedback = .exportReady
        } catch {
            LocalDiagnosticEventStore().record(
                severity: .error,
                category: "settings",
                operation: "export_local_json_clear_flow",
                error: error
            )
            clearDataFlow.exportFailed()
        }
    }

    static func showsDeveloperDiagnostics(for policy: DebugAccessPolicy) -> Bool {
        policy.allowsExtractionDebugScreens
    }
}

private extension View {
    func settingsSurface(tint: LedgerTone? = nil) -> some View {
        padding(LedgerSurfaceContract.contentPadding)
            .ledgerSurface(tint: tint)
    }
}
