import SwiftData
import XCTest
@testable import LifeOrganize

final class HeavyHistoryScenarioTests: XCTestCase {
    func testGeneratedHeavyHistoryFixtureMeetsDensityAndContentContract() throws {
        let fixture = try ScenarioFixture.load("heavy_history")
        let records = fixture.records
        let firstEncodedFixture = try HeavyHistorySeedScenarioGenerator.jsonData()
        let secondEncodedFixture = try HeavyHistorySeedScenarioGenerator.jsonData()

        XCTAssertEqual(firstEncodedFixture, secondEncodedFixture)
        XCTAssertEqual(fixture.clock.now, "2026-05-21T12:00:00-04:00")
        XCTAssertEqual(fixture.clock.timeZone, "America/New_York")
        XCTAssertEqual(records.things.count, 48)
        XCTAssertEqual(records.events.count, 312)
        XCTAssertEqual(records.notes.count, 128)
        XCTAssertEqual(records.rules.count, 96)
        XCTAssertEqual(records.chatMessages.count, 208)
        XCTAssertEqual(records.entityLinks.count, 120)

        let attentionStatuses = Set([
            ExtractionStatus.pending.rawValue,
            ExtractionStatus.extracting.rawValue,
            ExtractionStatus.pendingToken.rawValue,
            ExtractionStatus.pendingRetry.rawValue,
            ExtractionStatus.partiallySucceeded.rawValue,
            ExtractionStatus.failed.rawValue,
            ExtractionStatus.failedNeedsReview.rawValue,
            ExtractionStatus.needsReview.rawValue
        ])
        let reviewMessages = records.chatMessages.filter { message in
            guard message.role == ChatRole.user.rawValue else { return false }
            return message.extractionState.map { attentionStatuses.contains($0.status) } ?? false
        }
        let succeededMessages = records.chatMessages.filter { $0.extractionState?.status == ExtractionStatus.succeeded.rawValue }
        let backgroundMessages = records.chatMessages.filter { $0.role == ChatRole.assistant.rawValue || $0.role == ChatRole.system.rawValue }

        XCTAssertEqual(reviewMessages.count, 72)
        XCTAssertEqual(succeededMessages.count, 96)
        XCTAssertEqual(backgroundMessages.count, 40)
        XCTAssertTrue(succeededMessages.allSatisfy { message in
            message.extractionState?.status == ExtractionStatus.succeeded.rawValue
        })
        XCTAssertTrue(backgroundMessages.allSatisfy { message in
            message.extractionState?.status == ExtractionStatus.notRequired.rawValue
        })
        XCTAssertTrue(records.notes.contains { $0.text.contains("receipt") && $0.text.contains("HH note") })
        XCTAssertTrue(records.rules.contains { $0.startsAt > "2026-05-21" })
        XCTAssertTrue(records.rules.contains { $0.startsAt > "2026-07-04" })
        XCTAssertTrue(records.events.contains { $0.rawText.contains("filter") })
        XCTAssertTrue(records.entityLinks.contains { $0.fromEntityType == "event" && $0.toEntityType == "thing" })
    }

    func testHeavyHistoryProjectionReplayAndSearchStayDeterministicWithinTimeouts() throws {
        let loaded = try loadHeavyHistory()
        let calendar = loaded.calendar
        let now = loaded.now
        let records = loaded.records

        let projectionStart = CFAbsoluteTimeGetCurrent()
        let projection = LedgerFeedProjection(calendar: calendar, now: now)
        let items = projection.items(
            messages: records.messages,
            events: records.events,
            reminders: records.rules,
            notes: records.notes
        )
        let sections = projection.sections(
            messages: records.messages,
            events: records.events,
            reminders: records.rules,
            notes: records.notes
        )
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - projectionStart, 1.5)

        XCTAssertGreaterThanOrEqual(items.count, 500)
        XCTAssertEqual(items.count, 596)
        XCTAssertEqual(sections.first?.group, .upcoming)
        XCTAssertEqual(sections.first?.title, "Jul 4")
        XCTAssertEqual(sections.last?.title, "Nov 23, 2025")
        XCTAssertGreaterThanOrEqual(monthCount(in: sections, calendar: calendar), 7)
        XCTAssertTrue(sections.adjacentPairs().allSatisfy { $0.0.day > $0.1.day })
        XCTAssertTrue(items.adjacentPairs().allSatisfy { LedgerFeedItem.newestFirst($0.0, $0.1, calendar: calendar) })
        XCTAssertTrue(items.adjacentPairs().contains { lhs, rhs in
            lhs.timelineDate == rhs.timelineDate && lhs.createdAt != rhs.createdAt
        })
        XCTAssertFalse(items.contains { item in
            if case .message(let message) = item {
                return message.extractionStatus == .succeeded || message.role != .user
            }
            return false
        })

        let replayStart = CFAbsoluteTimeGetCurrent()
        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            messages: records.messages,
            things: records.things,
            events: records.events,
            reminders: records.rules,
            notes: records.notes,
            entityLinks: records.links
        )
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - replayStart, 1.5)
        XCTAssertGreaterThan(rows.count, items.count)
        XCTAssertTrue(rows.adjacentPairs().allSatisfy(timelineRowsAreNewestFirst))
        XCTAssertTrue(rows.contains { $0.sourceKind == .reminder && $0.dateKind == .attention })
        XCTAssertTrue(rows.contains { $0.sourceKind == .note && $0.dateKind == .updated })

        let search = SearchService()
        let searchRecords = search.records(
            things: records.things,
            events: records.events,
            rules: records.rules,
            notes: records.notes,
            messages: records.messages
        )
        let searchStart = CFAbsoluteTimeGetCurrent()
        let firstRun = search.search(LocalSearchQuery(rawText: "filter", limit: 25, now: now, calendar: calendar), in: searchRecords)
        let secondRun = search.search(LocalSearchQuery(rawText: "filter", limit: 25, now: now, calendar: calendar), in: searchRecords)
        let reversedRun = search.search(
            LocalSearchQuery(rawText: "filter", limit: 25, now: now, calendar: calendar),
            in: Array(searchRecords.reversed())
        )
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - searchStart, 1.5)
        XCTAssertEqual(firstRun.map(\.id), secondRun.map(\.id))
        XCTAssertEqual(firstRun.map(\.id), reversedRun.map(\.id))
        XCTAssertTrue(firstRun.contains { $0.sourceKind == .event })
        XCTAssertTrue(firstRun.contains { $0.sourceKind == .note || $0.sourceKind == .rule })

        let januaryRange = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 1, calendar: calendar))
        let januaryRows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            query: TimelineSliceQuery(dateRange: januaryRange, textFilter: "filter"),
            messages: records.messages,
            things: records.things,
            events: records.events,
            reminders: records.rules,
            notes: records.notes,
            entityLinks: records.links
        )
        XCTAssertFalse(januaryRows.isEmpty)
        XCTAssertTrue(januaryRows.allSatisfy { januaryRange.contains($0.timelineDate) })
        XCTAssertTrue(januaryRows.adjacentPairs().allSatisfy(timelineRowsAreNewestFirst))
    }

    private func loadHeavyHistory() throws -> LoadedHeavyHistory {
        let container = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.loadFixtureData(HeavyHistorySeedScenarioGenerator.jsonData(), into: container)
        let context = ModelContext(container)
        let fixture = HeavyHistorySeedScenarioGenerator.fixture()
        let now = try SeedScenarioDateParser.timestamp(fixture.clock.now, field: "clock.now")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: fixture.clock.timeZone)!

        return try LoadedHeavyHistory(
            now: now,
            calendar: calendar,
            records: HeavyHistoryRecords(
                messages: context.fetch(FetchDescriptor<ChatMessage>()),
                things: context.fetch(FetchDescriptor<Thing>()),
                events: context.fetch(FetchDescriptor<LedgerEvent>()),
                rules: context.fetch(FetchDescriptor<LedgerRule>()),
                notes: context.fetch(FetchDescriptor<LedgerNote>()),
                links: context.fetch(FetchDescriptor<EntityLink>())
            )
        )
    }

    private func timelineRowsAreNewestFirst(_ lhs: TimelineSliceRow, _ rhs: TimelineSliceRow) -> Bool {
        if lhs.timelineDate != rhs.timelineDate {
            return lhs.timelineDate > rhs.timelineDate
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        if lhs.sourceKind.sortRank != rhs.sourceKind.sortRank {
            return lhs.sourceKind.sortRank < rhs.sourceKind.sortRank
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID.uuidString < rhs.sourceID.uuidString
        }
        return lhs.dateKind.sortRank < rhs.dateKind.sortRank
    }

    private func monthCount(in sections: [LedgerFeedSection], calendar: Calendar) -> Int {
        Set(sections.map { section in
            let components = calendar.dateComponents([.year, .month], from: section.day)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }).count
    }
}

private struct LoadedHeavyHistory {
    let now: Date
    let calendar: Calendar
    let records: HeavyHistoryRecords
}

private struct HeavyHistoryRecords {
    let messages: [ChatMessage]
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let links: [EntityLink]
}

private extension Array {
    func adjacentPairs() -> [(Element, Element)] {
        guard count > 1 else { return [] }
        return zip(self, dropFirst()).map { ($0, $1) }
    }
}
