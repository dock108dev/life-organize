import XCTest
@testable import LifeOrganize

final class SettingsTrustSurfaceTests: XCTestCase {
    func testTrustCopyFramesKeyAsOptionalTimelineConnection() {
        XCTAssertEqual(SettingsTrustCopy.apiKeyTitle, "AI service")
        XCTAssertTrue(SettingsTrustCopy.apiKeyBody.contains("Entries stay local"))
        XCTAssertTrue(SettingsTrustCopy.apiKeyBody.contains("connect new timeline details"))
        XCTAssertTrue(SettingsTrustCopy.noKeyDetail.contains("Local-only mode"))
        XCTAssertTrue(SettingsTrustCopy.savedKeyDetail.contains("Keychain"))
        XCTAssertTrue(SettingsTrustCopy.savedKeyDetail.contains("not included in local data exports"))
    }

    func testExportCopyExplainsLocalDataCopyWithoutDebugLanguage() {
        XCTAssertEqual(SettingsTrustCopy.exportTitle, "Local data copy")
        XCTAssertTrue(SettingsTrustCopy.exportBody.contains("backup or review"))
        XCTAssertTrue(SettingsTrustCopy.exportBody.contains("saved entries, links, and local history"))
    }

    func testClearDataCopyDistinguishesDeletedLedgerDataFromSavedKey() {
        XCTAssertEqual(SettingsTrustCopy.clearTitle, "Reset this device")
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("timeline history"))
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("Things"))
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("review items"))
        XCTAssertTrue(SettingsTrustCopy.clearDeletes.contains("continuity records"))
        XCTAssertTrue(SettingsTrustCopy.clearKeeps.contains("service token"))
        XCTAssertEqual(SettingsTrustCopy.clearPhrase, "DELETE MY LEDGER")
        XCTAssertEqual(SettingsSafetyRowContent.clearsLocalRecords.title, "Clears local records")
        XCTAssertEqual(SettingsSafetyRowContent.clearsLocalRecords.pillText, "Clears")
        XCTAssertEqual(SettingsSafetyRowContent.clearsLocalRecords.tone, .danger)
        XCTAssertEqual(SettingsSafetyRowContent.keepsSavedKey.title, "Keeps service token")
        XCTAssertEqual(SettingsSafetyRowContent.keepsSavedKey.pillText, "Keeps")
        XCTAssertEqual(SettingsSafetyRowContent.keepsSavedKey.tone, .success)
    }

    func testFeedbackMessagesGiveConfirmationAndNextSteps() {
        XCTAssertFalse(SettingsFeedback.apiKeySaved.isError)
        XCTAssertTrue(SettingsFeedback.apiKeySaved.message.contains("connect across your timeline"))
        XCTAssertTrue(SettingsFeedback.apiKeyRemoved.message.contains("Timeline capture still works locally"))
        XCTAssertTrue(SettingsFeedback.exportReady.message.contains("save or share"))
        XCTAssertTrue(SettingsFeedback.localDataCleared.message.contains("service token stayed in place"))

        XCTAssertTrue(SettingsFeedback.exportFailed.isError)
        XCTAssertTrue(SettingsFeedback.exportFailed.message.contains("local data was not changed"))
        XCTAssertTrue(SettingsFeedback.apiKeyReadFailed.message.contains("Reopen Settings"))
        XCTAssertTrue(SettingsFeedback.clearDataFailed.message.contains("Try again"))
    }

    func testPrimarySettingsCopyAvoidsInternalProcessLanguage() {
        let copy = [
            SettingsTrustCopy.apiKeyTitle,
            SettingsTrustCopy.apiKeyBody,
            SettingsTrustCopy.noKeyDetail,
            SettingsTrustCopy.savedKeyDetail,
            SettingsTrustCopy.exportTitle,
            SettingsTrustCopy.exportBody,
            SettingsTrustCopy.clearTitle,
            SettingsTrustCopy.clearBody,
            SettingsTrustCopy.clearDeletes,
            SettingsTrustCopy.clearKeeps,
            SettingsClearDataCopy.exportPrompt,
            SettingsClearDataCopy.exportFailedBody,
            SettingsFeedback.apiKeyReplaced.message,
            SettingsFeedback.exportReady.message,
            SettingsFeedback.localDataCleared.message,
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
            ]
        )
    }

    func testLockedSettingsCopyDoesNotExposeDiagnosticsEntry() {
        let normalSettingsCopy = [
            "Trust & Preferences",
            "Local controls for what carries forward.",
            SettingsTrustCopy.apiKeyTitle,
            SettingsTrustCopy.apiKeyBody,
            SettingsTrustCopy.noKeyDetail,
            SettingsTrustCopy.savedKeyDetail,
            SettingsTrustCopy.exportTitle,
            SettingsTrustCopy.exportBody,
            SettingsTrustCopy.clearTitle,
            SettingsTrustCopy.clearBody,
            SettingsTrustCopy.clearDeletes,
            SettingsTrustCopy.clearKeeps,
            "LifeOrganize 0.1 (1)",
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
            ]
        )
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
