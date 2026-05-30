import XCTest
@testable import LifeOrganize

final class ReminderDetailActionTests: XCTestCase {
    func testReminderDetailActionsMatchReminderBehavior() throws {
        let dueDate = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let dateReminder = LedgerRule(
            title: "Replace air filters",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: dueDate,
            createdAt: fixedTestNow
        )
        let windowReminder = LedgerRule(
            title: "Submit rebate",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: fixedTestNow,
            expiresAt: dueDate,
            createdAt: fixedTestNow
        )
        let recurringReminder = LedgerRule(
            title: "Check filters monthly",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            rawText: "Check filters every month",
            startsAt: fixedTestNow,
            createdAt: fixedTestNow
        )

        XCTAssertEqual(
            ReminderDetailActionPolicy.dateAction(for: dateReminder, status: .scheduled)?.title,
            "Move Due Date"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .scheduled)?.title,
            "Stop Carrying"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .active)?.title,
            "Mark Done"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.dateAction(for: windowReminder, status: .active)?.title,
            "Extend Window"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.lifecycleAction(for: windowReminder, status: .active)?.title,
            "Close Window"
        )
        XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: recurringReminder, status: .active))
        XCTAssertEqual(
            RuleStatusService().expirationDisplay(for: recurringReminder, at: fixedTestNow),
            "Recurring text saved; no automated repeat"
        )
    }

    func testRulesUIContractExposesStableIdentifiersAndActionStateMatrix() throws {
        let ruleID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let dueDate = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let dateReminder = LedgerRule(
            id: ruleID,
            title: "Replace air filters",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: dueDate,
            createdAt: fixedTestNow
        )
        let windowReminder = LedgerRule(
            title: "Submit rebate",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: fixedTestNow,
            expiresAt: dueDate,
            createdAt: fixedTestNow
        )
        let inactiveReminder = LedgerRule(
            title: "Renew license",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: dueDate,
            createdAt: fixedTestNow,
            manuallyDeactivatedAt: fixedTestNow
        )

        XCTAssertEqual(RulesUIContract.listAccessibilityIdentifier, "carry-forward-list")
        XCTAssertEqual(RulesUIContract.detailAccessibilityIdentifier, "carry-forward-detail")
        XCTAssertEqual(RulesUIContract.detailPaneAccessibilityIdentifier, "carry-forward-detail-pane")
        XCTAssertEqual(
            RulesUIContract.rowAccessibilityIdentifier(for: ruleID),
            "carry-forward-row-11111111-1111-1111-1111-111111111111"
        )
        XCTAssertEqual(RuleDetailSheet.edit.id, "edit")
        XCTAssertEqual(RuleDetailSheet.reschedule.id, "reschedule")
        XCTAssertEqual(RuleDetailSheet.endDate.id, "end-date")
        XCTAssertEqual(
            ReminderDetailActionPolicy.dateAction(for: dateReminder, status: .scheduled)?.systemImage,
            "calendar.badge.clock"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.dateAction(for: windowReminder, status: .active)?.systemImage,
            "calendar.badge.plus"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .active)?.systemImage,
            "checkmark.circle"
        )
        XCTAssertEqual(
            ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .scheduled)?.id,
            "stop-scheduled"
        )
        XCTAssertEqual(ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .active)?.id, "mark-done")
        XCTAssertEqual(ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .expired)?.id, "let-rest")
        XCTAssertNil(ReminderDetailActionPolicy.lifecycleAction(for: inactiveReminder, status: .inactive))
        XCTAssertEqual(
            ReminderDetailActionPolicy.dateAction(for: inactiveReminder, status: .inactive)?.sheet,
            .reschedule
        )
        XCTAssertEqual(ReminderDetailActionPolicy.dateAction(for: windowReminder, status: .active)?.sheet, .endDate)
        XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: windowReminder, status: .inactive))
    }

    func testReminderDetailActionPolicyPreservesAvailabilityMatrices() throws {
        let start = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let end = try XCTUnwrap(ExtractionService.parseDate("2027-03-22"))
        let dateReminder = LedgerRule(
            title: "Replace air filters",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: start,
            createdAt: fixedTestNow
        )
        let windowReminder = LedgerRule(
            title: "Submit rebate",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: start,
            expiresAt: end,
            createdAt: fixedTestNow
        )
        let ongoingWithEnd = LedgerRule(
            title: "Carry gym bag",
            ruleType: .reminder,
            continuityBehavior: .ongoing,
            startsAt: start,
            expiresAt: end,
            createdAt: fixedTestNow
        )
        let ongoingWithoutEnd = LedgerRule(
            title: "Carry gym bag",
            ruleType: .reminder,
            continuityBehavior: .ongoing,
            startsAt: start,
            createdAt: fixedTestNow
        )
        let recurringReminder = LedgerRule(
            title: "Check filters monthly",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            rawText: "Check filters every month",
            startsAt: start,
            createdAt: fixedTestNow
        )

        for status in RuleStatus.allCases {
            XCTAssertEqual(ReminderDetailActionPolicy.dateAction(for: dateReminder, status: status)?.sheet, .reschedule)
            XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: ongoingWithoutEnd, status: status))
            XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: recurringReminder, status: status))
        }
        for status in [RuleStatus.scheduled, .active, .expired] {
            XCTAssertEqual(ReminderDetailActionPolicy.dateAction(for: windowReminder, status: status)?.sheet, .endDate)
            XCTAssertEqual(ReminderDetailActionPolicy.dateAction(for: ongoingWithEnd, status: status)?.sheet, .endDate)
        }
        XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: windowReminder, status: .inactive))
        XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: ongoingWithEnd, status: .inactive))

        assertLifecycleAction(dateReminder, status: .scheduled, title: "Stop Carrying")
        assertLifecycleAction(dateReminder, status: .active, title: "Mark Done")
        assertLifecycleAction(dateReminder, status: .expired, title: "Let It Rest")
        assertLifecycleAction(windowReminder, status: .scheduled, title: "Cancel Window")
        assertLifecycleAction(windowReminder, status: .active, title: "Close Window")
        assertLifecycleAction(windowReminder, status: .expired, title: "Let Window Rest")
        assertLifecycleAction(ongoingWithEnd, status: .scheduled, title: "Stop Carrying")
        assertLifecycleAction(ongoingWithEnd, status: .active, title: "Stop Carrying")
        assertLifecycleAction(ongoingWithEnd, status: .expired, title: "Let It Rest")
        assertLifecycleAction(recurringReminder, status: .scheduled, title: "Pause Pattern")
        assertLifecycleAction(recurringReminder, status: .active, title: "Pause Pattern")
        assertLifecycleAction(recurringReminder, status: .expired, title: "Let Pattern Rest")
        for rule in [dateReminder, windowReminder, ongoingWithEnd, recurringReminder] {
            XCTAssertNil(ReminderDetailActionPolicy.lifecycleAction(for: rule, status: .inactive))
        }
    }

    func testReminderDetailRegularActionsUseAvailabilityAndConstrainedSheets() throws {
        let detailSource = try sourceFile("LifeOrganize/Features/Rules/RuleDetailView.swift")
        XCTAssertTrue(detailSource.contains("horizontalSizeClass == .regular && hasSummaryActions"))
        XCTAssertTrue(detailSource.contains("summaryPresentation.actionSentence != nil && hasSummaryActions"))
        XCTAssertTrue(detailSource.contains("private var regularSummaryActionBar"))
        XCTAssertTrue(detailSource.contains("lifecycleAction = availableLifecycleAction"))

        let actionSource = try sourceFile("LifeOrganize/Features/Rules/ReminderDetailActions.swift")
        XCTAssertTrue(actionSource.contains(".ledgerAdaptiveWidth(.sheet)"))
    }

    func testReminderEditValidationBlocksContradictoryDateRanges() throws {
        let start = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let sameDayEnd = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let nextDayEnd = try XCTUnwrap(ExtractionService.parseDate("2027-03-16"))

        XCTAssertEqual(
            ReminderDateValidation.endDateError(
                startsAt: start,
                hasExpiration: true,
                expiresAt: sameDayEnd
            ),
            "End date must be after the start date."
        )
        XCTAssertNil(
            ReminderDateValidation.endDateError(
                startsAt: start,
                hasExpiration: true,
                expiresAt: nextDayEnd
            )
        )
        XCTAssertNil(
            ReminderDateValidation.endDateError(
                startsAt: start,
                hasExpiration: false,
                expiresAt: sameDayEnd
            )
        )
    }

    func testManualReminderEditContractChoosesReminderContinuityBehavior() {
        XCTAssertEqual(ReminderEditContract.continuityBehavior(hasExpiration: false), .dateBasedReminder)
        XCTAssertEqual(ReminderEditContract.continuityBehavior(hasExpiration: true), .timeLimitedWindow)
    }

    func testRescheduleSheetContextKeepsCurrentDateSecondaryAndActionSpecific() throws {
        let current = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let selected = try XCTUnwrap(ExtractionService.parseDate("2027-03-22"))
        let unchanged = ReminderRescheduleSheetContext(
            currentDate: current,
            selectedDate: current,
            canSave: false
        )
        let changed = ReminderRescheduleSheetContext(
            currentDate: current,
            selectedDate: selected,
            canSave: true
        )

        XCTAssertEqual(unchanged.currentLabel, "Current due")
        XCTAssertEqual(unchanged.currentDetail, "Saved reminder date")
        XCTAssertEqual(unchanged.editorTitle, "Move to")
        XCTAssertEqual(unchanged.pickerLabel, "Due date")
        XCTAssertEqual(unchanged.statusMessage, "Choose a different date to save.")
        XCTAssertEqual(changed.statusMessage, "Will move to \(DateFormatting.fullDate.string(from: selected)).")
    }

    func testEndDateSheetContextUsesWindowCopyAndValidationTone() throws {
        let start = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let currentEnd = try XCTUnwrap(ExtractionService.parseDate("2027-03-22"))
        let selectedEnd = try XCTUnwrap(ExtractionService.parseDate("2027-03-29"))
        let rule = LedgerRule(
            title: "Submit rebate",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: start,
            expiresAt: currentEnd,
            createdAt: fixedTestNow
        )

        let valid = ReminderEndDateSheetContext(
            rule: rule,
            normalizedExpiration: selectedEnd,
            validationMessage: nil
        )
        let invalid = ReminderEndDateSheetContext(
            rule: rule,
            normalizedExpiration: currentEnd,
            validationMessage: "Choose a date after the current end date."
        )

        XCTAssertEqual(valid.currentLabel, "Planned end")
        XCTAssertEqual(valid.currentValue, DateFormatting.fullDate.string(from: currentEnd))
        XCTAssertEqual(valid.currentDetail, "Window stays open until this date")
        XCTAssertEqual(valid.editorTitle, "Extend to")
        XCTAssertEqual(valid.pickerLabel, "End date")
        XCTAssertEqual(valid.statusMessage, "Will end \(DateFormatting.fullDate.string(from: selectedEnd)).")
        XCTAssertEqual(valid.statusTone, .neutral)
        XCTAssertEqual(invalid.statusMessage, "Choose a date after the current end date.")
        XCTAssertEqual(invalid.statusTone, .danger)
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func assertLifecycleAction(
        _ rule: LedgerRule,
        status: RuleStatus,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            ReminderDetailActionPolicy.lifecycleAction(for: rule, status: status)?.title,
            title,
            file: file,
            line: line
        )
    }
}
