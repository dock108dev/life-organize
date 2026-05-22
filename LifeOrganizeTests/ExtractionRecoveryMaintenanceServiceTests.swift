import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class ExtractionRecoveryMaintenanceServiceTests: XCTestCase {
    func testRelaunchRepairMakesStuckExtractingEntryRetryable() throws {
        let context = makeInMemoryModelContext()
        let staleAttemptAt = fixedTestNow.addingTimeInterval(-600)
        let message = ChatMessage(
            role: .user,
            text: "Changed filter.",
            createdAt: staleAttemptAt,
            extractionStatus: .extracting,
            extractionAttemptCount: 1,
            lastExtractionAttemptAt: staleAttemptAt
        )
        let attempt = ExtractionAttempt(status: .pending, startedAt: staleAttemptAt, sourceMessage: message)
        context.insert(message)
        context.insert(attempt)
        try context.save()

        let repairedCount = try ExtractionRecoveryMaintenanceService(
            modelContext: context,
            now: { fixedTestNow },
            staleAfter: 300
        )
        .repairInterruptedEntries()

        XCTAssertEqual(repairedCount, 1)
        XCTAssertEqual(message.extractionStatus, .pendingRetry)
        XCTAssertEqual(message.extractionErrorCode, .unknown)
        XCTAssertEqual(message.nextExtractionRetryAt, fixedTestNow)
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.completedAt, fixedTestNow)
        XCTAssertEqual(attempt.errorCode, .unknown)
        XCTAssertTrue(attempt.normalizedJSONText.contains("interrupted"))
    }

    func testRelaunchRepairLeavesFreshAndTerminalEntriesAlone() throws {
        let context = makeInMemoryModelContext()
        let fresh = ChatMessage(
            role: .user,
            text: "Fresh.",
            createdAt: fixedTestNow,
            extractionStatus: .extracting,
            lastExtractionAttemptAt: fixedTestNow
        )
        let succeeded = ChatMessage(role: .user, text: "Done.", extractionStatus: .succeeded)
        context.insert(fresh)
        context.insert(succeeded)
        try context.save()

        let repairedCount = try ExtractionRecoveryMaintenanceService(
            modelContext: context,
            now: { fixedTestNow },
            staleAfter: 300
        )
        .repairInterruptedEntries()

        XCTAssertEqual(repairedCount, 0)
        XCTAssertEqual(fresh.extractionStatus, .extracting)
        XCTAssertEqual(succeeded.extractionStatus, .succeeded)
    }
}
