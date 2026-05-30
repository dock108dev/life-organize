import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class ProductCoherenceScenarioTests: XCTestCase {
    func testValidationLoopRendersTimelineThingsAndCarryForwardFromSharedRecords() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let service = ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("Finances Wednesday afternoon")
        _ = try await service.send("I think Bogey needs a haircut in a week or two")
        _ = try await service.send("Intent to play golf Thursday unless raining")
        let workMessage = try await service.send("Work on Sonar, AWS, Vulns, and monorepo tomorrow at 8pm")

        let workSourceID = try XCTUnwrap(workMessage?.id)
        var things = try fetchThings(context)
        var rules = try context.fetch(FetchDescriptor<LedgerRule>())
        var messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let sourceLinkedThingNames = ["Sonar", "AWS", "Vulnerabilities", "Monorepo"]

        XCTAssertNotNil(thing(named: "Finance", in: things))
        XCTAssertNotNil(thing(named: "Bogey", in: things))
        XCTAssertNotNil(thing(named: "Golf", in: things))
        XCTAssertNotNil(thing(named: "AWS", in: things))
        XCTAssertNotNil(thing(named: "Vulnerabilities", in: things))
        XCTAssertNil(thing(named: "Finances", in: things))
        XCTAssertNil(thing(named: "Aws", in: things))
        XCTAssertNil(thing(named: "Vuln", in: things))

        for name in sourceLinkedThingNames {
            let thing = try XCTUnwrap(thing(named: name, in: things))
            XCTAssertTrue(thing.sourceMessageIDs.contains(workSourceID), "\(name) lost the source capture link")
            let snapshot = snapshot(for: thing, rules: rules, messages: messages, now: now)
            XCTAssertGreaterThan(snapshot.recordCount, 0)
            XCTAssertFalse(snapshot.listSummaryLine.text.contains("No entries yet"))
            XCTAssertTrue(snapshot.listSummaryLine.text.contains("Reminder tomorrow"))
        }

        let finance = try XCTUnwrap(thing(named: "Finance", in: things))
        let financeSnapshot = snapshot(for: finance, rules: rules, messages: messages, now: now)
        XCTAssertGreaterThan(financeSnapshot.recordCount, 0)
        XCTAssertFalse(financeSnapshot.listSummaryLine.text.contains("No entries yet"))

        let bogey = try XCTUnwrap(thing(named: "Bogey", in: things))
        let bogeySnapshot = snapshot(for: bogey, rules: rules, messages: messages, now: now)
        XCTAssertGreaterThan(bogeySnapshot.recordCount, 0)
        XCTAssertFalse(bogeySnapshot.listSummaryLine.text.contains("No entries yet"))
        XCTAssertTrue(messages.contains { $0.text.contains("Bogey") && $0.extractionStatus == .partiallySucceeded })

        _ = try await service.send("Pause work on Sonar, AWS, Vulns, and monorepo")

        things = try fetchThings(context)
        rules = try context.fetch(FetchDescriptor<LedgerRule>())
        messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let workRule = try XCTUnwrap(rules.first { $0.title.contains("Sonar") })
        let pausedAt = try XCTUnwrap(workRule.manuallyDeactivatedAt)
        let carryForward = ReminderContinuityPresentationService()
        let pausedPresentation = carryForward.presentation(for: workRule, at: now)

        XCTAssertEqual(pausedPresentation.badges.map(\.label), ["Paused"])
        XCTAssertEqual(pausedPresentation.primaryLine, "Paused")
        XCTAssertEqual(pausedPresentation.dateLine, "Paused \(DateFormatting.shortDate.string(from: pausedAt)) · Hidden from active carry forward")
        XCTAssertFalse(pausedPresentation.badges.map(\.label).contains("Ongoing"))
        XCTAssertFalse([pausedPresentation.primaryLine, pausedPresentation.dateLine ?? ""].joined(separator: " ").contains("Completed or stopped"))
        XCTAssertFalse(carryForward.rules(rules, in: .now, at: now).contains { $0.id == workRule.id })
        XCTAssertFalse(carryForward.rules(rules, in: .comingUp, at: now).contains { $0.id == workRule.id })
        XCTAssertTrue(carryForward.rules(rules, in: .paused, at: now).contains { $0.id == workRule.id })

        let feedItems = LedgerFeedProjection(calendar: testCalendar, now: now).items(
            messages: messages,
            events: [],
            reminders: rules,
            notes: notes
        )
        let timelineRule = try XCTUnwrap(feedItems.compactMap { item -> LedgerRule? in
            if case .reminder(let rule) = item, rule.id == workRule.id { return rule }
            return nil
        }.first)
        let timelineItem = LedgerFeedItem.reminder(timelineRule)
        XCTAssertEqual(timelineItem.timelineDate, pausedAt)
        XCTAssertNotEqual(timelineItem.timelineDate, workRule.startsAt)

        for name in sourceLinkedThingNames {
            let thing = try XCTUnwrap(thing(named: name, in: things))
            let snapshot = snapshot(for: thing, rules: rules, messages: messages, now: now)
            XCTAssertGreaterThan(snapshot.recordCount, 0)
            XCTAssertFalse(snapshot.listSummaryLine.text.contains("No entries yet"))
            XCTAssertFalse(snapshot.listSummaryLine.text.contains("Reminder tomorrow"))
        }
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func fetchThings(_ context: ModelContext) throws -> [Thing] {
        try context.fetch(FetchDescriptor<Thing>()).sorted { $0.name < $1.name }
    }

    private func thing(named name: String, in things: [Thing]) -> Thing? {
        things.first { $0.name == name }
    }

    private func snapshot(
        for thing: Thing,
        rules: [LedgerRule],
        messages: [ChatMessage],
        now: Date
    ) -> ThingPreviewSnapshot {
        let sourceIDs = Set(thing.sourceMessageIDs)
        let relatedRules = rules.filter { rule in
            guard let sourceMessageID = rule.sourceMessageID else { return false }
            return sourceIDs.contains(sourceMessageID)
        }
        let sourceMessages = messages.filter { sourceIDs.contains($0.id) }
        return ThingPreviewSnapshot(
            thing: thing,
            relatedRules: relatedRules,
            sourceMessages: sourceMessages,
            now: now,
            calendar: testCalendar
        )
    }
}
