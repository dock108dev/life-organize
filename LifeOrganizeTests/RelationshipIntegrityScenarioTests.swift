import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class RelationshipIntegrityScenarioTests: XCTestCase {
    func testBundledSeedScenariosPassRelationshipIntegrityAfterLoadAndFreshContext() throws {
        for group in try scenarioGroupsByClock() {
            let container = ModelContainerFactory.make(configuration: .inMemory)
            try SeedScenarioLoader.load(group.fixtureIDs, into: container, isAutomationRuntime: true)

            let firstContext = ModelContext(container)
            try ScenarioRelationshipIntegrityValidator(modelContext: firstContext).validateScenario(
                name: group.name,
                now: group.now,
                calendar: group.calendar
            )

            try firstContext.save()
            let reloadedContext = ModelContext(container)
            try ScenarioRelationshipIntegrityValidator(modelContext: reloadedContext).validateScenario(
                name: "\(group.name)-reloaded",
                now: group.now,
                calendar: group.calendar
            )
        }
    }

    func testReviewQueueReassignmentAndThingMergeKeepRelationshipIntegrity() throws {
        let container = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.load(["work_continuity"], into: container, isAutomationRuntime: true)
        let context = ModelContext(container)
        let timing = try scenarioTiming("work_continuity")
        let validator = ScenarioRelationshipIntegrityValidator(modelContext: context)

        try validator.validateScenario(
            name: "work_continuity-before-review-action",
            now: timing.now,
            calendar: timing.calendar
        )

        let reviewItem = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerReviewItem>()).first)
        let target = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Thing>()).first { $0.name == "Nimbus Web Services" }
        )
        let queue = LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"),
            dateProvider: TestDateProvider(now: timing.now)
        )
        try queue.reassignRecords(from: reviewItem, to: target.id)

        try validator.validateScenario(
            name: "work_continuity-after-review-action",
            now: timing.now,
            calendar: timing.calendar
        )
    }

    func testManualRetryMutationKeepsRelationshipIntegrity() async throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today.",
            createdAt: fixedTestNow,
            extractionStatus: .failedNeedsReview,
            extractionErrorCode: .invalidJSON,
            extractionAttemptCount: 1,
            lastExtractionAttemptAt: fixedTestNow.addingTimeInterval(-60)
        )
        let failedAttempt = ExtractionAttempt(
            status: .failed,
            errorCode: .invalidJSON,
            errorMessage: "Invalid JSON.",
            startedAt: fixedTestNow.addingTimeInterval(-60),
            completedAt: fixedTestNow.addingTimeInterval(-30),
            sourceMessage: message
        )
        context.insert(message)
        context.insert(failedAttempt)
        try context.save()

        var retry = ManualExtractionRetryService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        retry.extractorFactory = { _ in DeterministicMessageExtractionClient() }
        try await retry.retry(message)

        try ScenarioRelationshipIntegrityValidator(modelContext: context).validateScenario(
            name: "manual-retry-mutation",
            now: fixedTestNow,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    func testValidatorReportsAllDetectedRelationshipFailures() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(role: .user, text: "Changed oil.", createdAt: now)
        let thing = Thing(name: "Car", eventCount: 2)
        let event = LedgerEvent(title: "Oil", occurredAt: now, rawText: "Oil", thing: thing, sourceMessage: message)
        let badTarget = UUID()
        let invalidRaw = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .mentionsThing,
            confidence: 2,
            createdBy: .system,
            sourceMessageID: UUID()
        )
        invalidRaw.sourceTypeRawValue = "invalid"
        let missingTarget = EntityLink(
            sourceType: .event,
            sourceID: event.id,
            targetType: .thing,
            targetID: badTarget,
            relation: .primaryThing,
            createdBy: .system
        )

        context.insert(message)
        context.insert(thing)
        context.insert(event)
        context.insert(invalidRaw)
        context.insert(missingTarget)

        do {
            try ScenarioRelationshipIntegrityValidator(modelContext: context).validateScenario(
                name: "broken-store",
                now: now,
                calendar: Calendar(identifier: .gregorian)
            )
            XCTFail("Expected relationship integrity validation to fail.")
        } catch let error as RelationshipIntegrityValidationError {
            let codes = Set(error.result.failures.map(\.code))
            XCTAssertTrue(codes.contains("invalid_raw_type"))
            XCTAssertTrue(codes.contains("entity_link_missing_target"))
            XCTAssertTrue(codes.contains("entity_link_bad_confidence"))
            XCTAssertTrue(codes.contains("entity_link_missing_source_message"))
            XCTAssertTrue(codes.contains("thing_event_count_mismatch"))
            XCTAssertGreaterThanOrEqual(error.result.failures.count, 5)
        }
    }

    private func scenarioTiming(_ id: String) throws -> (now: Date, calendar: Calendar) {
        let fixture = try ScenarioFixture.load(id)
        let now = try SeedScenarioDateParser.timestamp(fixture.clock.now, field: "clock.now")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: fixture.clock.timeZone)!
        return (now, calendar)
    }

    private func scenarioGroupsByClock() throws -> [ScenarioTimingGroup] {
        let grouped = try Dictionary(grouping: SeedScenario.allCases.map(\.fixtureID)) { id in
            let fixture = try ScenarioFixture.load(id)
            return "\(fixture.clock.now)|\(fixture.clock.timeZone)"
        }

        return try grouped
            .values
            .map { fixtureIDs in
                let sortedIDs = fixtureIDs.sorted()
                let timing = try scenarioTiming(sortedIDs[0])
                return ScenarioTimingGroup(
                    name: sortedIDs.joined(separator: "+"),
                    fixtureIDs: sortedIDs,
                    now: timing.now,
                    calendar: timing.calendar
                )
            }
            .sorted { $0.name < $1.name }
    }
}

private struct ScenarioTimingGroup {
    let name: String
    let fixtureIDs: [String]
    let now: Date
    let calendar: Calendar
}
