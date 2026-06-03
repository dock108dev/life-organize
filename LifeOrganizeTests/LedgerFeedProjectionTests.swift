import SwiftData
import XCTest
@testable import LifeOrganize

final class LedgerFeedProjectionTests: XCTestCase {
    func testProjectionDisplaysLocalNoonDateOnlyRecordsOnIntendedLocalDay() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 26, 21, calendar: calendar)
        let hotKnife = LedgerRule(
            title: "Get hot knife",
            ruleType: .reminder,
            rawText: "Get hot knife",
            startsAt: DateFormatting.normalizedDateOnly(try Self.date(2026, 5, 26, 8, calendar: calendar), calendar: calendar),
            createdAt: now
        )
        let monaco = LedgerEvent(
            title: "Monaco next weekend",
            occurredAt: DateFormatting.normalizedDateOnly(try Self.date(2026, 5, 30, 8, calendar: calendar), calendar: calendar),
            rawText: "Monaco next weekend",
            createdAt: now
        )

        let sections = LedgerFeedProjection(calendar: calendar, now: now).sections(
            messages: [],
            events: [monaco],
            reminders: [hotKnife],
            notes: []
        )

        XCTAssertEqual(sections.map(\.title), ["May 30", "Today"])
        XCTAssertEqual(sections.map(\.subtitle), ["Upcoming · Saturday", "Tue, May 26"])
        XCTAssertEqual(sections.map(\.summary.timeRangeText), ["", ""])
        XCTAssertEqual(sections[0].items.map(\.id), ["event-\(monaco.id.uuidString)"])
        XCTAssertEqual(sections[1].items.map(\.id), ["reminder-\(hotKnife.id.uuidString)"])
    }

    func testProjectionDisplaysUndatedLegacyReminderOnSourceMessageDay() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 26, 21, calendar: calendar)
        let sourceMessage = ChatMessage(role: .user, text: "Need to get hot knife", createdAt: now)
        let staleReminder = LedgerRule(
            title: "Get hot knife",
            ruleType: .reminder,
            rawText: sourceMessage.text,
            startsAt: try Self.date(2026, 5, 25, 12, calendar: calendar),
            createdAt: now,
            sourceMessage: sourceMessage
        )

        let section = try XCTUnwrap(
            LedgerFeedProjection(calendar: calendar, now: now).sections(
                messages: [],
                events: [],
                reminders: [staleReminder],
                notes: []
            ).first
        )

        XCTAssertEqual(section.title, "Today")
        XCTAssertEqual(section.subtitle, "Tue, May 26")
        XCTAssertEqual(section.summary.timeRangeText, "")
    }

    func testProjectionGroupsLedgerRecordsWithTodayBetweenPastAndFuture() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 10, calendar: calendar)
        let createdEarly = try Self.date(2026, 5, 21, 8, calendar: calendar)
        let createdMorning = try Self.date(2026, 5, 21, 9, calendar: calendar)
        let createdLate = try Self.date(2026, 5, 21, 11, calendar: calendar)
        let today = try Self.date(2026, 5, 21, 12, calendar: calendar)
        let yesterday = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let earlierThisWeek = try Self.date(2026, 5, 18, 12, calendar: calendar)
        let older = try Self.date(2026, 5, 10, 12, calendar: calendar)

        let olderMessage = ChatMessage(role: .user, text: "Older note", createdAt: createdEarly, extractionStatus: .pendingToken)
        let newerMessage = ChatMessage(role: .user, text: "Changed oil today", createdAt: createdLate, extractionStatus: .pending)
        let assistantMessage = ChatMessage(role: .assistant, text: "Event saved", createdAt: createdMorning)
        let todayEvent = LedgerEvent(
            title: "Changed oil",
            occurredAt: today,
            rawText: "Changed oil today",
            createdAt: createdMorning
        )
        let yesterdayEvent = LedgerEvent(
            title: "Bought dog food",
            occurredAt: yesterday,
            rawText: "Bought dog food",
            createdAt: createdLate
        )
        let thisWeekEvent = LedgerEvent(
            title: "Washed car",
            occurredAt: earlierThisWeek,
            rawText: "Washed car Monday",
            createdAt: createdLate
        )
        let reminder = LedgerRule(
            title: "Replace filter",
            ruleType: .reminder,
            rawText: "Replace filter next month",
            startsAt: try Self.date(2026, 6, 15, 12, calendar: calendar),
            createdAt: earlierThisWeek
        )
        let note = LedgerNote(text: "Sparse note", createdAt: older)

        let sections = LedgerFeedProjection(calendar: calendar, now: now).sections(
            messages: [olderMessage, newerMessage, assistantMessage],
            events: [yesterdayEvent, todayEvent, thisWeekEvent],
            reminders: [reminder],
            notes: [note]
        )

        XCTAssertEqual(sections.map(\.group), [.upcoming, .today, .yesterday, .thisWeek, .earlier])
        XCTAssertEqual(sections.map(\.title), ["Jun 15", "Today", "Yesterday", "Monday", "May 10"])
        XCTAssertEqual(sections.map(\.subtitle), [
            "Upcoming · Monday",
            "Thu, May 21",
            "Wed, May 20",
            "May 18",
            "Sunday"
        ])
        XCTAssertEqual(sections[0].items.map(\.id), [
            "reminder-\(reminder.id.uuidString)"
        ])
        XCTAssertEqual(sections[1].items.map(\.id), [
            "event-\(todayEvent.id.uuidString)",
            LedgerFeedItem.messageID(for: newerMessage.id),
            LedgerFeedItem.messageID(for: olderMessage.id)
        ])
        XCTAssertEqual(sections[2].items.map(\.id), ["event-\(yesterdayEvent.id.uuidString)"])
        XCTAssertEqual(sections[3].items.map(\.id), ["event-\(thisWeekEvent.id.uuidString)"])
        XCTAssertEqual(sections[4].items.map(\.id), [
            "note-\(note.id.uuidString)"
        ])
    }

    func testFutureEventsAndRemindersUseUpcomingSection() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 10, calendar: calendar)
        let createdAt = try Self.date(2026, 5, 21, 9, calendar: calendar)
        let futureEvent = LedgerEvent(
            title: "Dentist appointment",
            occurredAt: try Self.date(2026, 6, 1, 15, calendar: calendar),
            rawText: "Dentist appointment June 1",
            createdAt: createdAt
        )
        let futureReminder = LedgerRule(
            title: "Replace filter",
            ruleType: .reminder,
            rawText: "Replace filter next month",
            startsAt: try Self.date(2026, 6, 20, 12, calendar: calendar),
            createdAt: createdAt
        )
        let distantReminder = LedgerRule(
            title: "No bowling",
            ruleType: .reminder,
            rawText: "No bowling next year.",
            startsAt: try Self.date(2026, 12, 31, 19, calendar: calendar),
            createdAt: createdAt
        )

        let sections = LedgerFeedProjection(calendar: calendar, now: now).sections(
            messages: [],
            events: [futureEvent],
            reminders: [futureReminder, distantReminder],
            notes: []
        )

        XCTAssertEqual(sections.map(\.group), [.upcoming, .upcoming])
        XCTAssertEqual(sections.map(\.title), ["Jun 20", "Jun 1"])
        XCTAssertEqual(sections[0].items.map(\.id), [
            "reminder-\(futureReminder.id.uuidString)"
        ])
        XCTAssertEqual(sections[1].items.map(\.id), [
            "event-\(futureEvent.id.uuidString)"
        ])
        XCTAssertEqual(sections[0].summary.itemCountText, "1 item")
        XCTAssertEqual(sections[0].summary.typeMixText, "1 reminder")
        XCTAssertEqual(sections[1].summary.typeMixText, "1 event")
        XCTAssertFalse(sections.flatMap(\.items).containsReminder(distantReminder))
    }

    func testBackfilledSameDayEventsSortNewestFirstByLedgerTimeBeforeCreationTime() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 22, calendar: calendar)
        let morningEvent = LedgerEvent(
            title: "Morning run",
            occurredAt: try Self.date(2026, 5, 21, 7, calendar: calendar),
            rawText: "Morning run",
            createdAt: try Self.date(2026, 5, 21, 21, calendar: calendar)
        )
        let eveningEvent = LedgerEvent(
            title: "Picked up dry cleaning",
            occurredAt: try Self.date(2026, 5, 21, 18, calendar: calendar),
            rawText: "Picked up dry cleaning",
            createdAt: try Self.date(2026, 5, 21, 20, calendar: calendar)
        )

        let items = LedgerFeedProjection(calendar: calendar, now: now).items(
            messages: [],
            events: [morningEvent, eveningEvent],
            reminders: [],
            notes: []
        )

        XCTAssertEqual(items.map(\.id), [
            "event-\(eveningEvent.id.uuidString)",
            "event-\(morningEvent.id.uuidString)"
        ])
    }

    func testSectionsExposeTemporalSummaryFromFeedItems() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, calendar: calendar)
        let message = ChatMessage(
            role: .user,
            text: "Needs review",
            createdAt: try Self.date(2026, 5, 21, 11, calendar: calendar),
            extractionStatus: .failedNeedsReview
        )
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: try Self.date(2026, 5, 21, 8, calendar: calendar),
            rawText: "Changed oil",
            createdAt: try Self.date(2026, 5, 21, 10, calendar: calendar)
        )
        let reminder = LedgerRule(
            title: "Call dentist",
            ruleType: .reminder,
            rawText: "Call dentist today",
            startsAt: try Self.date(2026, 5, 21, 9, calendar: calendar),
            createdAt: try Self.date(2026, 5, 21, 7, calendar: calendar)
        )
        let note = LedgerNote(text: "Gate code changed.", createdAt: try Self.date(2026, 5, 21, 10, calendar: calendar))

        let section = try XCTUnwrap(
            LedgerFeedProjection(calendar: calendar, now: now).sections(
                messages: [message],
                events: [event],
                reminders: [reminder],
                notes: [note]
            ).first
        )

        XCTAssertEqual(section.group, .today)
        XCTAssertEqual(section.title, "Today")
        XCTAssertEqual(section.subtitle, "Thu, May 21")
        XCTAssertEqual(section.summary.itemCountText, "4 items")
        XCTAssertEqual(section.summary.timeRangeText, "8:00 AM-11:00 AM")
        XCTAssertEqual(section.summary.typeMixText, "1 event, 1 reminder, 1 note, 1 timeline entry")
        XCTAssertEqual(section.summary.text, "4 items · 8:00 AM-11:00 AM · 1 event, 1 reminder, 1 note, 1 timeline entry")
        XCTAssertEqual(section.summary.displayText(mode: .compact), "4 items · 8:00 AM-11:00 AM")
        XCTAssertEqual(section.summary.displayText(mode: .full), section.summary.text)
    }

    func testDateOnlyItemsRenderAnytimeWithoutPollutingSectionSummary() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, calendar: calendar)
        let event = LedgerEvent(
            title: "Finished testing and deploying auto detect",
            occurredAt: DateFormatting.normalizedDateOnly(now, calendar: calendar),
            rawText: "Finished testing and deploying auto detect",
            createdAt: now
        )
        let content = LedgerFeedRowContent(
            item: .event(event),
            timeFormatter: Self.timeFormatter(calendar: calendar)
        )
        let section = try XCTUnwrap(
            LedgerFeedProjection(calendar: calendar, now: now).sections(
                messages: [],
                events: [event],
                reminders: [],
                notes: []
            ).first
        )

        XCTAssertEqual(content.timestampText, "Anytime")
        XCTAssertEqual(section.summary.timeRangeText, "")
        XCTAssertEqual(section.summary.displayText(mode: .compact), "1 item")
    }

    func testOlderMultiDayHistoryUsesSeparateCalendarSections() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, calendar: calendar)
        let olderEvent = LedgerEvent(
            title: "Renewed passport",
            occurredAt: try Self.date(2026, 5, 1, 9, calendar: calendar),
            rawText: "Renewed passport",
            createdAt: try Self.date(2026, 5, 10, 12, calendar: calendar)
        )
        let olderNote = LedgerNote(text: "Storage unit code.", createdAt: try Self.date(2026, 5, 10, 17, calendar: calendar))

        let sections = LedgerFeedProjection(calendar: calendar, now: now).sections(
            messages: [],
            events: [olderEvent],
            reminders: [],
            notes: [olderNote]
        )
        let section = try XCTUnwrap(sections.first)

        XCTAssertEqual(section.group, .earlier)
        XCTAssertEqual(section.title, "May 10")
        XCTAssertEqual(section.summary.timeRangeText, "5:00 PM")
        XCTAssertEqual(section.summary.typeMixText, "1 note")

        XCTAssertEqual(sections.map(\.title), ["May 10", "May 1"])
        XCTAssertEqual(sections.map(\.summary.typeMixText), ["1 note", "1 event"])
    }

    func testProjectionUsesStructuredRecordsAsPrimaryRowsForSucceededMessages() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 10, calendar: calendar)
        let createdAt = try Self.date(2026, 5, 21, 9, calendar: calendar)
        let eventOnlyMessage = ChatMessage(
            role: .user,
            text: "Changed hallway air filter today.",
            createdAt: createdAt,
            extractionStatus: .succeeded
        )
        let eventAndReminderMessage = ChatMessage(
            role: .user,
            text: "Changed water filter today. Remind me in 3 months.",
            createdAt: createdAt,
            extractionStatus: .succeeded
        )
        let noteOnlyMessage = ChatMessage(
            role: .user,
            text: "Gate code changed to 4821.",
            createdAt: createdAt,
            extractionStatus: .succeeded
        )
        let airFilterEvent = LedgerEvent(
            title: "Changed hallway air filter",
            occurredAt: createdAt,
            rawText: eventOnlyMessage.text,
            createdAt: createdAt,
            sourceMessage: eventOnlyMessage
        )
        let waterFilterEvent = LedgerEvent(
            title: "Changed water filter",
            occurredAt: createdAt,
            rawText: eventAndReminderMessage.text,
            createdAt: createdAt,
            sourceMessage: eventAndReminderMessage
        )
        let reminder = LedgerRule(
            title: "Replace water filter",
            ruleType: .reminder,
            rawText: eventAndReminderMessage.text,
            startsAt: try Self.date(2026, 6, 21, 9, calendar: calendar),
            createdAt: createdAt,
            sourceMessage: eventAndReminderMessage
        )
        let note = LedgerNote(text: "Gate code changed to 4821.", createdAt: createdAt, sourceMessage: noteOnlyMessage)

        let items = LedgerFeedProjection(calendar: calendar, now: now).items(
            messages: [eventOnlyMessage, eventAndReminderMessage, noteOnlyMessage],
            events: [airFilterEvent, waterFilterEvent],
            reminders: [reminder],
            notes: [note]
        )

        XCTAssertFalse(items.containsMessage(eventOnlyMessage))
        XCTAssertFalse(items.containsMessage(eventAndReminderMessage))
        XCTAssertFalse(items.containsMessage(noteOnlyMessage))
        XCTAssertTrue(items.containsEvent(airFilterEvent))
        XCTAssertTrue(items.containsEvent(waterFilterEvent))
        XCTAssertTrue(items.containsReminder(reminder))
        XCTAssertTrue(items.containsNote(note))
        XCTAssertEqual(items.count, 4)
    }

    func testProjectionKeepsOnlyPrimaryMessagesRequiringAttention() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 10, calendar: calendar)
        let attentionStatuses: [ExtractionStatus] = [
            .pending,
            .extracting,
            .pendingToken,
            .pendingRetry,
            .partiallySucceeded,
            .failed,
            .failedNeedsReview,
            .needsReview
        ]
        let visibleMessages = attentionStatuses.map {
            ChatMessage(role: .user, text: "Attention \($0.rawValue)", createdAt: now, extractionStatus: $0)
        }
        let visibleRecallMessage = ChatMessage(role: .assistant, text: "Local results:\n- Changed oil.", createdAt: now, extractionStatus: .notRequired)
        let hiddenSaveConfirmation = ChatMessage(role: .assistant, text: "Event saved:\nChanged oil.", createdAt: now, extractionStatus: .notRequired)
        let hiddenMessages = [
            ChatMessage(role: .user, text: "Handled", createdAt: now, extractionStatus: .succeeded),
            ChatMessage(role: .user, text: "Local question", createdAt: now, extractionStatus: .notRequired),
            ChatMessage(role: .system, text: "Ready.", createdAt: now, extractionStatus: .pending)
        ]

        let items = LedgerFeedProjection(calendar: calendar, now: now).items(
            messages: visibleMessages + [visibleRecallMessage, hiddenSaveConfirmation] + hiddenMessages,
            events: [],
            reminders: [],
            notes: []
        )

        XCTAssertEqual(
            items.compactMap(\.messageText).sorted(),
            (visibleMessages + [visibleRecallMessage]).map(\.text).sorted()
        )
    }

    func testProjectionTransitionsFromAttentionMessageToRecordsAfterRetrySuccess() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 10, calendar: calendar)
        let createdAt = try Self.date(2026, 5, 21, 9, calendar: calendar)
        let message = ChatMessage(
            role: .user,
            text: "Changed oil at 40k miles.",
            createdAt: createdAt,
            extractionStatus: .pendingRetry
        )
        let projection = LedgerFeedProjection(calendar: calendar, now: now)

        XCTAssertEqual(
            projection.items(messages: [message], events: [], reminders: [], notes: []).map(\.id),
            [LedgerFeedItem.messageID(for: message.id)]
        )

        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: createdAt,
            rawText: message.text,
            createdAt: createdAt,
            sourceMessage: message
        )
        message.extractionStatus = .succeeded

        let retriedItems = projection.items(messages: [message], events: [event], reminders: [], notes: [])
        XCTAssertFalse(retriedItems.containsMessage(message))
        XCTAssertEqual(retriedItems.map(\.id), ["event-\(event.id.uuidString)"])
    }

    @MainActor
    func testProjectionUsesFreshFetchesAfterDeleteAndClear() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, calendar: calendar)
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Home Air Filters", createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Replaced filter",
            occurredAt: try Self.date(2026, 5, 21, 8, calendar: calendar),
            rawText: "Replaced filter.",
            createdAt: try Self.date(2026, 5, 21, 9, calendar: calendar),
            thing: thing
        )
        let note = LedgerNote(
            text: "Filter size is 20x25x1.",
            createdAt: try Self.date(2026, 5, 21, 10, calendar: calendar),
            updatedAt: try Self.date(2026, 5, 21, 10, calendar: calendar),
            linkedThings: [thing]
        )
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })
        context.insert(thing)
        try service.insertEvent(event)
        try service.insertNote(note)
        try context.save()

        let projection = LedgerFeedProjection(calendar: calendar, now: now)
        var sections = try projection.sections(
            messages: context.fetch(FetchDescriptor<ChatMessage>()),
            events: context.fetch(FetchDescriptor<LedgerEvent>()),
            reminders: context.fetch(FetchDescriptor<LedgerRule>()),
            notes: context.fetch(FetchDescriptor<LedgerNote>())
        )
        XCTAssertEqual(sections.first?.summary.typeMixText, "1 event, 1 note")

        try service.deleteEvent(event)
        try context.save()
        sections = try projection.sections(
            messages: context.fetch(FetchDescriptor<ChatMessage>()),
            events: context.fetch(FetchDescriptor<LedgerEvent>()),
            reminders: context.fetch(FetchDescriptor<LedgerRule>()),
            notes: context.fetch(FetchDescriptor<LedgerNote>())
        )

        XCTAssertEqual(sections.first?.items.map(\.id), ["note-\(note.id.uuidString)"])
        XCTAssertEqual(sections.first?.summary.typeMixText, "1 note")
        XCTAssertFalse(sections.flatMap(\.items).containsEvent(event))

        try LocalDataClearService(modelContext: context).clearLedgerData()
        XCTAssertTrue(
            projection.sections(
                messages: try context.fetch(FetchDescriptor<ChatMessage>()),
                events: try context.fetch(FetchDescriptor<LedgerEvent>()),
                reminders: try context.fetch(FetchDescriptor<LedgerRule>()),
                notes: try context.fetch(FetchDescriptor<LedgerNote>())
            ).isEmpty
        )
    }
}
