import XCTest
@testable import LifeOrganize

final class TimelineSliceReplayTests: XCTestCase {
    func testMaySliceBuildsReplaySectionsWithExistingNavigationTargets() throws {
        let calendar = Self.newYorkCalendar
        let mayRange = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 5, calendar: calendar))
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: try Self.date(2026, 5, 4, 9, 0, calendar: calendar),
            rawText: "Changed oil"
        )
        let reminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            startsAt: try Self.date(2026, 5, 12, 10, 0, calendar: calendar)
        )
        let note = LedgerNote(
            text: "Insurance card is in the glove box.",
            createdAt: try Self.date(2026, 5, 8, 14, 0, calendar: calendar),
            updatedAt: try Self.date(2026, 5, 8, 14, 0, calendar: calendar)
        )
        let message = ChatMessage(
            role: .user,
            text: "Car note needs review.",
            createdAt: try Self.date(2026, 5, 5, 12, 0, calendar: calendar),
            extractionStatus: .needsReview
        )

        let rows = TimelineSliceProjection(calendar: calendar).rows(
            query: TimelineSliceQuery(dateRange: mayRange),
            messages: [message],
            events: [event],
            reminders: [reminder],
            notes: [note]
        )
        let model = TimelineSliceReplayModel(
            title: "May 2026",
            query: TimelineSliceQuery(dateRange: mayRange),
            rows: rows,
            calendar: calendar,
            now: try Self.date(2026, 5, 20, 12, calendar: calendar)
        )

        XCTAssertEqual(model.title, "May 2026")
        XCTAssertEqual(model.context.itemCountText, "4 items")
        XCTAssertEqual(model.context.typeMixText, "1 event, 1 reminder, 1 note, 1 message")
        XCTAssertEqual(model.sections.flatMap(\.rows).map(\.navigationTarget).asSet, [
            .eventDetail(event.id),
            .ruleDetail(reminder.id),
            .noteDetail(note.id),
            .chatMessage(message.id)
        ])
    }

    func testLinkedThingReplayFiltersRowsAndPreservesThingDestination() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let car = Thing(name: "Car", aliases: ["Honda"], category: .vehicle, createdAt: now, updatedAt: now)
        let house = Thing(name: "House", createdAt: now, updatedAt: now)
        let carEvent = LedgerEvent(title: "Tire rotation", occurredAt: now, rawText: "Rotated tires", thing: car)
        let houseEvent = LedgerEvent(title: "Paint touchup", occurredAt: now, rawText: "Paint", thing: house)
        let descriptor = TimelineSliceReplayDescriptor.linkedThing(car)

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            query: descriptor.query,
            things: [car, house],
            events: [carEvent, houseEvent]
        )

        XCTAssertEqual(descriptor.title, "Car timeline")
        XCTAssertTrue(rows.contains { $0.sourceKind == .thing && $0.navigationTarget == .thingDetail(car.id) })
        XCTAssertTrue(rows.contains { $0.sourceID == carEvent.id && $0.navigationTarget == .eventDetail(carEvent.id) })
        XCTAssertFalse(rows.contains { $0.sourceID == houseEvent.id })
    }

    func testCarTimelineRecordMixIncludesOperationalHistoryRows() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let car = Thing(name: "Car", category: .vehicle, createdAt: try Self.date(2026, 1, 2, 8, calendar: calendar), updatedAt: now)
        let oilChange = LedgerEvent(
            title: "Oil change",
            occurredAt: try Self.date(2026, 5, 1, 9, calendar: calendar),
            rawText: "Oil change",
            eventType: .maintenance,
            thing: car
        )
        let tireRotation = LedgerEvent(
            title: "Tire rotation",
            occurredAt: try Self.date(2026, 5, 3, 11, calendar: calendar),
            rawText: "Tire rotation",
            eventType: .maintenance,
            thing: car
        )
        let registrationRenewal = LedgerEvent(
            title: "Registration renewal",
            occurredAt: try Self.date(2026, 5, 8, 15, calendar: calendar),
            rawText: "Renewed registration",
            eventType: .renewal,
            thing: car
        )
        let insuranceNote = LedgerNote(
            text: "Insurance note: new ID card is saved.",
            createdAt: try Self.date(2026, 5, 9, 10, calendar: calendar),
            linkedThings: [car]
        )
        let reminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            startsAt: try Self.date(2026, 5, 15, 9, calendar: calendar),
            createdAt: try Self.date(2026, 5, 9, 9, calendar: calendar),
            thing: car
        )

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            query: TimelineSliceReplayDescriptor.linkedThing(car).query,
            things: [car],
            events: [oilChange, tireRotation, registrationRenewal],
            reminders: [reminder],
            notes: [insuranceNote]
        )

        XCTAssertTrue(rows.contains { $0.displayLabel == "Oil change" && $0.sourceKind == .event })
        XCTAssertTrue(rows.contains { $0.displayLabel == "Tire rotation" && $0.sourceKind == .event })
        XCTAssertTrue(rows.contains { $0.displayLabel == "Registration renewal" && $0.sourceKind == .event })
        XCTAssertTrue(rows.contains { $0.summaryText.contains("Insurance note") && $0.sourceKind == .note })
        XCTAssertTrue(rows.contains { $0.displayLabel == "Renew registration" && $0.sourceKind == .reminder })
    }

    func testEmptySliceKeepsSecondaryContextWithoutSections() throws {
        let calendar = Self.newYorkCalendar
        let range = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 5, calendar: calendar))
        let model = TimelineSliceReplayModel(
            title: "May 2026",
            query: TimelineSliceQuery(dateRange: range),
            rows: [],
            calendar: calendar,
            now: try Self.date(2026, 5, 20, 12, calendar: calendar)
        )

        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.context.itemCountText, "0 items")
        XCTAssertEqual(model.context.typeMixText, "")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testSectionSummaryDisplayModesKeepFullDataAndCompactText() throws {
        let calendar = Self.newYorkCalendar
        let morning = try Self.date(2026, 5, 8, 9, calendar: calendar)
        let afternoon = try Self.date(2026, 5, 8, 14, calendar: calendar)
        let rows = [
            Self.row(kind: .event, date: morning, label: "Oil change"),
            Self.row(kind: .reminder, date: afternoon, label: "Renew registration"),
            Self.row(kind: .note, date: afternoon, label: "Insurance card")
        ]
        let summary = TimelineSliceReplaySectionSummary(rows: rows, calendar: calendar)

        XCTAssertEqual(summary.itemCountText, "3 items")
        XCTAssertEqual(summary.timeRangeText, "9:00 AM-2:00 PM")
        XCTAssertEqual(summary.typeMixText, "1 event, 1 reminder, 1 note")
        XCTAssertEqual(summary.text, "3 items · 9:00 AM-2:00 PM · 1 event, 1 reminder, 1 note")
        XCTAssertEqual(summary.displayText(mode: .compact), "3 items · 9:00 AM-2:00 PM")
        XCTAssertEqual(summary.displayText(mode: .full), summary.text)
    }

    func testMissingTargetResolutionFallsBackByRecordType() throws {
        let existingThing = Thing(id: UUID(), name: "Car")
        let missingID = UUID()
        let store = LocalSearchNavigationRecordStore(
            things: [existingThing],
            events: [],
            rules: [],
            notes: [],
            messages: []
        )

        XCTAssertEqual(store.resolvedKind(for: .thingDetail(existingThing.id)), .thing)
        XCTAssertEqual(store.resolvedKind(for: .thingDetail(missingID)), .missing)
        XCTAssertEqual(store.resolvedKind(for: .eventDetail(missingID)), .missing)
        XCTAssertEqual(store.resolvedKind(for: .ruleDetail(missingID)), .missing)
        XCTAssertEqual(store.resolvedKind(for: .noteDetail(missingID)), .missing)
        XCTAssertEqual(store.resolvedKind(for: .chatMessage(missingID)), .missing)
    }

    func testMixedRecordOrderingAndFutureOnlySectionsUseLedgerRhythm() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let futureEvent = LedgerEvent(
            title: "Future service",
            occurredAt: try Self.date(2026, 6, 1, 9, calendar: calendar),
            rawText: "Future service"
        )
        let olderNote = LedgerNote(
            text: "Older note",
            createdAt: try Self.date(2026, 5, 1, 9, calendar: calendar),
            updatedAt: try Self.date(2026, 5, 1, 9, calendar: calendar)
        )
        let sameMomentReminder = LedgerRule(
            title: "Same moment reminder",
            startsAt: try Self.date(2026, 5, 1, 9, calendar: calendar),
            createdAt: try Self.date(2026, 5, 1, 8, calendar: calendar)
        )
        let completedReminder = LedgerRule(
            title: "Completed reminder",
            startsAt: try Self.date(2026, 4, 1, 9, calendar: calendar),
            createdAt: try Self.date(2026, 4, 1, 8, calendar: calendar),
            manuallyDeactivatedAt: try Self.date(2026, 5, 2, 10, calendar: calendar)
        )

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            events: [futureEvent],
            reminders: [sameMomentReminder, completedReminder],
            notes: [olderNote]
        )
        let model = TimelineSliceReplayModel(title: "Mixed", query: TimelineSliceQuery(), rows: rows, calendar: calendar, now: now)

        XCTAssertEqual(model.sections.first?.title, "Jun 1")
        XCTAssertEqual(model.sections.first?.subtitle, "Upcoming · Monday")
        XCTAssertTrue(model.sections.flatMap(\.rows).contains { $0.displayLabel == "Completed reminder" && $0.dateKind == .completedDeactivated })
        XCTAssertEqual(model.sections.flatMap(\.rows).map(\.displayLabel), [
            "Future service",
            "Completed reminder",
            "Older note",
            "Same moment reminder",
            "Completed reminder"
        ])
    }

    func testReplayRowContentUsesCompactTimestampSourceAndTypePills() throws {
        let calendar = Self.newYorkCalendar
        let timeFormatter = Self.timeFormatter(calendar: calendar)
        let date = try Self.date(2026, 5, 1, 9, 30, calendar: calendar)
        let car = Thing(name: "Car")
        let event = LedgerEvent(title: "Oil change", occurredAt: date, rawText: "Oil change", thing: car)
        let row = try XCTUnwrap(TimelineSliceProjection(calendar: calendar).rows(events: [event]).first)
        let content = TimelineSliceReplayRowContent(row: row, timeFormatter: timeFormatter)

        XCTAssertEqual(TestTextNormalization.normalizedTimeText(content.timestampText), "9:30 AM")
        XCTAssertEqual(content.sourceLabel, "Event")
        XCTAssertEqual(content.sourceTone, .muted)
        XCTAssertEqual(content.sourceBadge.semantic, .categoryEvent)
        XCTAssertEqual(content.dateKindLabel, "Occurred")
        XCTAssertEqual(content.primaryText, "Oil change")
        XCTAssertEqual(content.linkedThingText, "Car")
        XCTAssertEqual(TimelineSliceReplayLayout.rowChrome.rowVerticalPadding, LedgerVisualSystem.Padding.rowCompactVertical)
        XCTAssertEqual(TimelineSliceReplayLayout.rowChrome.markerSize, TimelineSliceReplayLayout.markerSize)
        XCTAssertEqual(LedgerRowDensity.compact.verticalSpacing, 2)
        XCTAssertEqual(LedgerRowDensity.compact.verticalPadding, 6)
    }

    private static var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private static func timeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func row(kind: TimelineSliceRecordKind, date: Date, label: String) -> TimelineSliceRow {
        let id = UUID()
        return TimelineSliceRow(
            sourceID: id,
            sourceKind: kind,
            dateKind: .created,
            timelineDate: date,
            createdAt: date,
            updatedAt: nil,
            navigationTarget: navigationTarget(for: kind, id: id),
            displayLabel: label,
            summaryText: label,
            hasDisplayTime: true,
            linkedThings: [],
            relationshipContext: nil,
            searchableText: label
        )
    }

    private static func navigationTarget(for kind: TimelineSliceRecordKind, id: UUID) -> LocalSearchNavigationTarget {
        switch kind {
        case .message:
            return .chatMessage(id)
        case .event:
            return .eventDetail(id)
        case .reminder:
            return .ruleDetail(id)
        case .note:
            return .noteDetail(id)
        case .thing:
            return .thingDetail(id)
        }
    }
}

private extension Array where Element == LocalSearchNavigationTarget {
    var asSet: Set<LocalSearchNavigationTarget> {
        Set(self)
    }
}
