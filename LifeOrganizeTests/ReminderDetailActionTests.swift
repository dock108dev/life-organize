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
}
