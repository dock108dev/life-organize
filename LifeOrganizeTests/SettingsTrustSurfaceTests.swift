import XCTest
@testable import LifeOrganize

final class SettingsTrustSurfaceTests: XCTestCase {
    func testTrustCopyFramesServiceTokenAsOptionalTimelineConnection() {
        XCTAssertEqual(SettingsTrustCopy.deviceTokenTitle, "AI service")
        XCTAssertTrue(SettingsTrustCopy.deviceTokenBody.contains("Entries stay local"))
        XCTAssertTrue(SettingsTrustCopy.deviceTokenBody.contains("connect new timeline details"))
        XCTAssertTrue(SettingsTrustCopy.noTokenDetail.contains("provisioned service token"))
        XCTAssertTrue(SettingsTrustCopy.savedTokenDetail.contains("Keychain"))
        XCTAssertTrue(SettingsTrustCopy.savedTokenDetail.contains("not included in local data exports"))
    }

    func testExportCopyExplainsLocalDataCopyWithoutDebugLanguage() {
        XCTAssertEqual(SettingsTrustCopy.exportTitle, "Local data copy")
        XCTAssertTrue(SettingsTrustCopy.exportBody.contains("backup or review"))
        XCTAssertTrue(SettingsTrustCopy.exportBody.contains("saved entries, links, and local history"))
    }

    func testClearDataCopyDistinguishesDeletedLedgerDataFromSavedToken() {
        XCTAssertEqual(SettingsTrustCopy.clearTitle, "Clear local data")
        XCTAssertTrue(SettingsTrustCopy.clearBody.contains("saved entries"))
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("Things"))
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("review tasks"))
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("timeline history"))
        XCTAssertTrue(SettingsTrustCopy.clearKeeps.contains("service token"))
        XCTAssertEqual(SettingsTrustCopy.clearPhrase, "CLEAR MY DATA")
        XCTAssertEqual(SettingsSafetyRowContent.clearsLocalRecords.title, "Clears local entries")
        XCTAssertEqual(SettingsSafetyRowContent.clearsLocalRecords.pillText, "Clears")
        XCTAssertEqual(SettingsSafetyRowContent.clearsLocalRecords.tone, .danger)
        XCTAssertEqual(SettingsSafetyRowContent.keepsSavedToken.title, "Keeps service token")
        XCTAssertEqual(SettingsSafetyRowContent.keepsSavedToken.pillText, "Keeps")
        XCTAssertEqual(SettingsSafetyRowContent.keepsSavedToken.tone, .success)
    }

    func testFeedbackMessagesGiveConfirmationAndNextSteps() {
        XCTAssertFalse(SettingsFeedback.deviceTokenSaved.isError)
        XCTAssertTrue(SettingsFeedback.deviceTokenSaved.message.contains("connect across your timeline"))
        XCTAssertTrue(SettingsFeedback.deviceTokenRemoved.message.contains("Timeline capture still works locally"))
        XCTAssertTrue(SettingsFeedback.exportReady.message.contains("save or share"))
        XCTAssertTrue(SettingsFeedback.localDataCleared.message.contains("service token stayed in place"))

        XCTAssertTrue(SettingsFeedback.exportFailed.isError)
        XCTAssertTrue(SettingsFeedback.exportFailed.message.contains("local data was not changed"))
        XCTAssertTrue(SettingsFeedback.deviceTokenReadFailed.message.contains("Reopen Settings"))
        XCTAssertTrue(SettingsFeedback.clearDataFailed.message.contains("Try again"))
    }

    func testPrimarySettingsCopyAvoidsInternalProcessLanguage() {
        let copy = [
            SettingsTrustCopy.deviceTokenTitle,
            SettingsTrustCopy.deviceTokenBody,
            SettingsTrustCopy.noTokenDetail,
            SettingsTrustCopy.savedTokenDetail,
            SettingsTrustCopy.exportTitle,
            SettingsTrustCopy.exportBody,
            SettingsTrustCopy.clearTitle,
            SettingsTrustCopy.clearBody,
            SettingsTrustCopy.clearDeletes,
            SettingsTrustCopy.clearKeeps,
            SettingsClearDataCopy.exportPrompt,
            SettingsClearDataCopy.exportFailedBody,
            SettingsFeedback.deviceTokenReplaced.message,
            SettingsFeedback.exportReady.message,
            SettingsFeedback.localDataCleared.message
        ].joined(separator: " ")

        XCTAssertNoPrimaryCopyTerms(
            copy,
            bannedTerms: [
                "OpenAI",
                "JSON",
                "provenance",
                "organization",
                "extraction",
                "prompt",
                "raw response",
                "normalized",
                "model metadata",
                "error code",
                "API key",
                "authorization",
                "bearer token"
            ]
        )
    }

    func testLockedSettingsCopyDoesNotExposeDiagnosticsEntry() {
        let normalSettingsCopy = [
            "Trust & Preferences",
            "Local controls for what carries forward.",
            SettingsTrustCopy.deviceTokenTitle,
            SettingsTrustCopy.deviceTokenBody,
            SettingsTrustCopy.noTokenDetail,
            SettingsTrustCopy.savedTokenDetail,
            SettingsTrustCopy.exportTitle,
            SettingsTrustCopy.exportBody,
            SettingsTrustCopy.clearTitle,
            SettingsTrustCopy.clearBody,
            SettingsTrustCopy.clearDeletes,
            SettingsTrustCopy.clearKeeps,
            "LifeOrganize 0.1 (1)"
        ].joined(separator: " ")

        XCTAssertNoPrimaryCopyTerms(
            normalSettingsCopy,
            bannedTerms: [
                "Developer Diagnostics",
                "Extraction Attempts",
                "Failed Extractions",
                "Developer mode unlocked",
                "raw response",
                "normalized JSON",
                "model metadata",
                "error code",
                "API key",
                "Authorization",
                "Bearer"
            ]
        )
    }

    func testSettingsViewOnlyKeepsDisplaySafeTokenState() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var savedTokenDescription: String?"))
        XCTAssertTrue(source.contains("@State private var serviceTokenDraft"))
        XCTAssertTrue(source.contains("map(maskedTokenDescription)"))
        XCTAssertFalse(source.contains("@State private var savedToken: String"))
        XCTAssertFalse(source.contains("Text(token)"))
        XCTAssertFalse(source.contains("LedgerPill(text: token"))
    }

    func testSettingsViewExposesStableProductionAnchors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(#""device-token-status""#))
        XCTAssertTrue(source.contains(#""device-token-save-button""#))
        XCTAssertTrue(source.contains(#""settings-export-button""#))
        XCTAssertTrue(source.contains(#""settings-clear-data-button""#))
        XCTAssertTrue(source.contains(#""settings-version-footer""#))
    }

    func testDeveloperDestinationsAreGuardedWhenPolicyHidesDiagnostics() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("if Self.showsDeveloperDiagnostics(for: developerModeState.policy)"))
        XCTAssertTrue(source.contains("activeDeveloperDestination = nil"))
        XCTAssertTrue(source.contains("EmptyView()"))
    }

    func testSettingsShareSurfacesHaveSeparateOwners() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let settingsSource = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        let clearDataSource = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Settings/SettingsClearDataFlow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("@State private var settingsExportShareItem: ExportShareItem?"))
        XCTAssertTrue(settingsSource.contains("@State private var clearDataExportShareItem: ExportShareItem?"))
        XCTAssertTrue(settingsSource.contains("exportShareItem: $clearDataExportShareItem"))
        XCTAssertTrue(settingsSource.contains(".sheet(item: $settingsExportShareItem)"))
        XCTAssertTrue(clearDataSource.contains(".sheet(item: $exportShareItem)"))
    }

    func testClearDataSheetUsesAdaptiveSheetWidth() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Settings/SettingsClearDataFlow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".ledgerAdaptiveWidth(.sheet)"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
    }

    func testClearDataFlowOffersExportBeforeTypedConfirmation() {
        var flow = SettingsClearDataFlow()

        XCTAssertTrue(flow.offersExportBeforeClear)
        XCTAssertFalse(flow.showsFinalConfirmation)
        XCTAssertTrue(SettingsClearDataCopy.exportPrompt.contains("local data copy"))
        XCTAssertTrue(SettingsClearDataCopy.exportPrompt.contains("does not create a cloud backup"))

        flow.continueToConfirmation()

        XCTAssertFalse(flow.offersExportBeforeClear)
        XCTAssertTrue(flow.showsFinalConfirmation)
    }

    func testClearDataFlowHandlesExportFailureRetryAndCancel() {
        var flow = SettingsClearDataFlow()

        flow.exportFailed()

        XCTAssertEqual(flow.step, .exportFailed)
        XCTAssertTrue(flow.offersExportBeforeClear)
        XCTAssertTrue(SettingsClearDataCopy.exportFailedBody.contains("local data is unchanged"))
        XCTAssertTrue(SettingsClearDataCopy.exportFailedBody.contains("retry"))
        XCTAssertTrue(SettingsClearDataCopy.exportFailedBody.contains("cancel"))
        XCTAssertTrue(SettingsClearDataCopy.exportFailedBody.contains("final confirmation"))

        flow.retryExport()
        XCTAssertEqual(flow.step, .exportPrompt)

        flow.exportFailed()
        flow.cancel()
        XCTAssertEqual(flow.step, .exportPrompt)
    }

    private func XCTAssertNoPrimaryCopyTerms(
        _ text: String,
        bannedTerms: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercased = text.lowercased()
        let offenders = bannedTerms.filter { lowercased.contains($0.lowercased()) }
        XCTAssertEqual(offenders, [], file: file, line: line)
    }
}
