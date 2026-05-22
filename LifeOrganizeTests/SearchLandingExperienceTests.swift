import XCTest
@testable import LifeOrganize

final class SearchLandingExperienceTests: XCTestCase {
    func testRootSearchEntryContractIsSharedAcrossPrimaryTabs() {
        XCTAssertEqual(AppToolbarSearchEntry.systemName, "magnifyingglass.circle")
        XCTAssertEqual(AppToolbarSearchEntry.accessibilityLabel, "Search Timeline")
        XCTAssertEqual(AppToolbarSearchEntry.accessibilityIdentifier, "root-search-entry")
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Timeline", "Things", "Carry Forward"])
    }

    func testToolbarStateShowsReviewButtonOnlyForOpenItems() {
        XCTAssertFalse(AppToolbarState(openReviewItemCount: 0).showsReviewQueueButton)
        XCTAssertTrue(AppToolbarState(openReviewItemCount: 1).showsReviewQueueButton)
        XCTAssertTrue(AppToolbarState(openReviewItemCount: 12).showsReviewQueueButton)
    }

    func testThingsLocalSearchScopeStaysDistinctFromUnifiedLedgerSearch() {
        let car = Thing(name: "Honda Civic", aliases: ["daily driver"], createdAt: fixedTestNow, updatedAt: fixedTestNow)
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: fixedTestNow,
            rawText: "Changed oil at Valvoline.",
            thing: car
        )
        let search = SearchService()
        let unifiedRecords = search.records(things: [car], events: [event])
        let thingsOnlyRecords = search.records(things: [car])

        let unified = search.search("Valvoline", in: unifiedRecords)
        let thingsOnly = search.search(
            LocalSearchQuery(rawText: "Valvoline", scopes: ThingsListView.localSearchScopes),
            in: thingsOnlyRecords
        )

        XCTAssertEqual(ThingsListView.localSearchScopes, [.thing])
        XCTAssertTrue(unified.contains { $0.navigationTarget == .eventDetail(event.id) })
        XCTAssertTrue(thingsOnly.isEmpty)
    }

    func testLandingAndNoResultCopyUseLocalRecallPatterns() {
        XCTAssertEqual(UnifiedSearchView.landingExamples.map(\.query), [
            "oil last month",
            "May 2026",
            "HarborMart 40k",
            "upcoming"
        ])
        XCTAssertTrue(UnifiedSearchView.landingExamples.contains { $0.detail.contains("rough timing") })
        XCTAssertNil(LedgerEmptyStateContent.noSearchResults.secondaryBody)
        XCTAssertEqual(LedgerEmptyStateContent.noThingSearchResults.title, "No matching things")

        XCTAssertNoForbiddenSearchCopy(staticSearchCopy())
    }

    func testOrdinaryAndTimelineSliceSearchResultsRemainNavigable() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let car = Thing(name: "Honda Civic", createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: try Self.date(2026, 5, 4, 9, calendar: calendar),
            rawText: "Changed oil.",
            thing: car
        )
        let search = SearchService()
        let records = search.records(things: [car], events: [event])
        let results = search.search(LocalSearchQuery(rawText: "May 2026", now: now, calendar: calendar), in: records)

        XCTAssertTrue(results.contains { $0.navigationTarget == .eventDetail(event.id) })
        let slice = try XCTUnwrap(results.first { $0.sourceKind == .timelineSlice })
        if case .timelineSlice(let descriptor) = slice.navigationTarget {
            XCTAssertEqual(descriptor.title, "May 2026")
            XCTAssertNotNil(descriptor.query.dateRange)
        } else {
            XCTFail("Expected timeline slice navigation")
        }
    }

    func testSearchResultRowsSuppressRepeatedContextLines() {
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let messageRecord = LocalSearchRecord(
            id: messageID,
            kind: .chatMessage,
            title: "You",
            subtitle: DateFormatting.shortDate.string(from: fixedTestNow),
            body: "Filter size is 16x20.",
            searchableFields: [],
            createdAt: fixedTestNow,
            occurredAt: nil,
            updatedAt: nil,
            linkedThingId: nil,
            linkedThingName: nil,
            isActiveRule: nil,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: nil,
            navigationTarget: .chatMessage(messageID)
        )
        let messagePresentation = LocalSearchResultRowPresentation(
            result: LocalSearchResult(record: messageRecord, matchedFields: [.chatText], score: 1)
        )

        XCTAssertEqual(messagePresentation.secondaryLines.map(\.text), [
            DateFormatting.shortDate.string(from: fixedTestNow),
            "Filter size is 16x20."
        ])

        let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        let noteRecord = LocalSearchRecord(
            id: noteID,
            kind: .note,
            title: "Filter size is 16x20...",
            subtitle: nil,
            body: "Filter size is 16x20 and stored near the furnace.",
            searchableFields: [],
            createdAt: fixedTestNow,
            occurredAt: nil,
            updatedAt: nil,
            linkedThingId: nil,
            linkedThingName: nil,
            isActiveRule: nil,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: nil,
            navigationTarget: .noteDetail(noteID)
        )
        let notePresentation = LocalSearchResultRowPresentation(
            result: LocalSearchResult(record: noteRecord, matchedFields: [.body], score: 1)
        )

        XCTAssertEqual(notePresentation.secondaryLines.map(\.text), [
            DateFormatting.shortDate.string(from: fixedTestNow)
        ])
    }

    func testSearchDestinationAvailabilityHandlesStaleTargets() {
        let thing = Thing(name: "Passport", createdAt: fixedTestNow, updatedAt: fixedTestNow)
        let event = LedgerEvent(title: "Renewed passport", occurredAt: fixedTestNow, rawText: "Renewed passport.", thing: thing)
        let rule = LedgerRule(title: "Renew again", ruleType: .reminder, rawText: "Renew again.", createdAt: fixedTestNow, thing: thing)
        let note = LedgerNote(text: "Passport note.", createdAt: fixedTestNow, updatedAt: fixedTestNow, linkedThings: [thing])
        let message = ChatMessage(role: .user, text: "Passport office.", createdAt: fixedTestNow)
        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!

        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .thingDetail(thing.id),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .eventDetail(event.id),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .ruleDetail(rule.id),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .noteDetail(note.id),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .chatMessage(message.id),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertFalse(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .thingDetail(missingID),
                things: [thing],
                events: [],
                rules: [],
                notes: [],
                messages: []
            )
        )
        XCTAssertFalse(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .eventDetail(missingID),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertFalse(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .ruleDetail(missingID),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertFalse(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .noteDetail(missingID),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertFalse(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .chatMessage(missingID),
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .timelineSlice(TimelineSliceReplayDescriptor(title: "May 2026", query: TimelineSliceQuery())),
                things: [],
                events: [],
                rules: [],
                notes: [],
                messages: []
            )
        )
    }

    func testNoteAndMessageSearchDestinationsRemainReachable() {
        let thing = Thing(name: "Water Filter", createdAt: fixedTestNow, updatedAt: fixedTestNow)
        let message = ChatMessage(role: .user, text: "Filter size is 16x20.", createdAt: fixedTestNow)
        let note = LedgerNote(
            text: "Filter size is 16x20 and stored near the furnace.",
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow,
            sourceMessage: message,
            linkedThings: [thing]
        )
        let search = SearchService()
        let records = search.records(things: [thing], notes: [note], messages: [message])

        let noteResults = search.search("furnace", in: records)
        let messageResults = search.search("16x20", in: records)

        XCTAssertTrue(noteResults.contains { $0.navigationTarget == .noteDetail(note.id) })
        XCTAssertTrue(messageResults.contains { $0.navigationTarget == .chatMessage(message.id) })
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .noteDetail(note.id),
                things: [thing],
                events: [],
                rules: [],
                notes: [note],
                messages: [message]
            )
        )
        XCTAssertTrue(
            LocalSearchDestinationView.hasAvailableRecord(
                for: .chatMessage(message.id),
                things: [thing],
                events: [],
                rules: [],
                notes: [note],
                messages: [message]
            )
        )
    }

    func testSecondarySearchDestinationPresentationsLeadWithOriginalContent() {
        let message = ChatMessage(role: .user, text: "Gate code changed to 4821.", createdAt: fixedTestNow)
        let note = LedgerNote(
            text: "Gate code changed to 4821 for the side entrance.",
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow,
            sourceMessage: message
        )
        let notePresentation = NoteDetailPresentation(note: note)
        let messagePresentation = ChatMessageContextPresentation(message: message)

        XCTAssertEqual(notePresentation.text, note.text)
        XCTAssertEqual(notePresentation.metadata.map(\.label), ["Created", "Updated"])
        XCTAssertEqual(notePresentation.sourceTitle, "Added from your timeline")
        XCTAssertEqual(messagePresentation.text, message.text)
        XCTAssertEqual(messagePresentation.metadata.map(\.label), ["Captured", "Context"])
        XCTAssertEqual(messagePresentation.roleText, "Original entry")

        XCTAssertNoForbiddenSearchCopy(
            [
                notePresentation.text,
                notePresentation.updatedLine,
                notePresentation.sourceTitle,
                notePresentation.sourceDetail ?? "",
                messagePresentation.text,
                messagePresentation.capturedLine,
                messagePresentation.roleText
            ].joined(separator: " ")
        )
    }

    func testMissingSearchRecordPresentationOffersWayBack() {
        let presentation = MissingSearchRecordPresentation()

        XCTAssertEqual(presentation.title, "Record unavailable")
        XCTAssertEqual(presentation.description, "This saved result may have changed.")
        XCTAssertEqual(presentation.actionTitle, "Back")
        XCTAssertNoForbiddenSearchCopy(
            [
                presentation.title,
                presentation.description,
                presentation.actionTitle,
                presentation.navigationTitle
            ].joined(separator: " ")
        )
    }

    private func staticSearchCopy() -> String {
        let examples = UnifiedSearchView.landingExamples.flatMap { example in
            [example.query, example.detail, example.pillText]
        }
        let emptyStates = [
            LedgerEmptyStateContent.searchLanding.title,
            LedgerEmptyStateContent.searchLanding.body,
            LedgerEmptyStateContent.noSearchResults.title,
            LedgerEmptyStateContent.noSearchResults.body,
            LedgerEmptyStateContent.noSearchResults.secondaryBody ?? "",
            LedgerEmptyStateContent.noThingSearchResults.title,
            LedgerEmptyStateContent.noThingSearchResults.body
        ]
        return ([
            "Search what you remember",
            "Try a detail"
        ] + examples + emptyStates).joined(separator: " ")
    }

    private func XCTAssertNoForbiddenSearchCopy(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercased = " \(text.lowercased()) "
        let forbiddenTerms = [
            " ai ",
            "ai-powered",
            "assistant",
            "confidence",
            "extraction",
            "extractor",
            "model",
            "vector",
            "generated",
            "classifier",
            "ranking score",
            "llm"
        ]
        let offenders = forbiddenTerms.filter { lowercased.contains($0) }
        XCTAssertEqual(offenders, [], file: file, line: line)
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
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
}
