import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewItemGenerationServiceTests: XCTestCase {
    func testLifecycleTransitionsPersistReviewState() throws {
        let item = LedgerReviewItem(
            dedupeKey: "local_recovery|entry",
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: "The original entry is saved locally.",
            targetType: .chatMessage,
            targetID: UUID(),
            evidence: []
        )

        item.markReady(at: date(day: 1))
        item.markPresented(at: date(day: 2))
        item.snooze(until: date(day: 10), at: date(day: 3))
        item.accept(at: date(day: 4))
        item.dismiss(at: date(day: 5))
        item.fail(reason: "Unable to build review record.", at: date(day: 6))
        item.expire(at: date(day: 7))
        item.supersede(at: date(day: 8))

        XCTAssertEqual(item.state, .superseded)
        XCTAssertEqual(item.presentedAt, date(day: 2))
        XCTAssertEqual(item.snoozedUntil, date(day: 10))
        XCTAssertEqual(item.resolvedAt, date(day: 8))
        XCTAssertEqual(item.failureReason, "Unable to build review record.")
    }

    func testGeneratesRequiredOperationalCandidateKindsWithEvidence() throws {
        let context = makeInMemoryModelContext()
        let now = date(day: 200)
        let airFilters = thing("HVAC air filter", category: .homeMaintenance)
        let dogFood = thing("Dog food", category: .food)
        let vehicle = thing("Blue sedan", category: .vehicle)
        airFilters.events = [
            event("Replaced HVAC air filter", day: 1, type: .replacement, thing: airFilters),
            event("Replaced HVAC air filter", day: 91, type: .replacement, thing: airFilters),
            event("Replaced HVAC air filter", day: 181, type: .replacement, thing: airFilters)
        ]
        dogFood.events = [
            event("Bought dog food", day: 1, type: .purchase, thing: dogFood),
            event("Bought dog food", day: 25, type: .purchase, thing: dogFood),
            event("Bought dog food", day: 51, type: .purchase, thing: dogFood)
        ]
        vehicle.events = [
            event("Oil change", day: 1, type: .maintenance, thing: vehicle, mileage: 30_000, subtype: "oil_change"),
            event("Oil change", day: 91, type: .maintenance, thing: vehicle, mileage: 35_000, subtype: "oil_change"),
            event("Oil change", day: 181, type: .maintenance, thing: vehicle, mileage: 40_000, subtype: "oil_change")
        ]
        let overdue = LedgerRule(
            title: "Replace smoke alarm battery",
            ruleType: .reminder,
            startsAt: date(day: 150),
            expiresAt: date(day: 150)
        )
        let retryMessage = ChatMessage(
            role: .user,
            text: "Changed oil but the network failed.",
            extractionStatus: .pendingRetry,
            extractionErrorCode: .networkUnavailable
        )
        let partialMessage = ChatMessage(
            role: .user,
            text: "Partial records need checking.",
            extractionStatus: .partiallySucceeded
        )
        let duplicateA = thing("Printer Paper")
        let duplicateB = thing("printer paper")
        let conflictEvent = event(
            "Dentist appointment",
            day: 120,
            type: .appointment,
            thing: nil,
            metadata: [
                LedgerEventMetadataEntry(
                    key: .dueDate,
                    valueKind: .date,
                    dateValue: "2026-05-15",
                    sourceText: "May 15"
                )
            ]
        )
        let needsNaming = Thing(name: "changed oil", normalizedKey: "changed oil")

        context.insert(airFilters)
        context.insert(dogFood)
        context.insert(vehicle)
        context.insert(overdue)
        context.insert(retryMessage)
        context.insert(partialMessage)
        context.insert(duplicateA)
        context.insert(duplicateB)
        context.insert(conflictEvent)
        context.insert(needsNaming)
        try context.save()

        let items = try service(context, now: now).refresh()
        let kinds = Set(items.map(\.kind))

        XCTAssertTrue(kinds.isSuperset(of: Set([
            .intervalReminder,
            .overdueReminderReview,
            .localRecovery,
            .extractionReview,
            .duplicateThing,
            .conflictingDate,
            .normalizationCandidate
        ])))
        XCTAssertTrue(items.first { $0.kind == .intervalReminder && $0.title.contains("Air filter") }?.detail.contains("90 days") == true)
        XCTAssertTrue(items.first { $0.kind == .intervalReminder && $0.title.contains("Dog food") }?.detail.contains("Saved records") == true)
        XCTAssertTrue(items.first { $0.kind == .intervalReminder && $0.title.contains("Oil change") }?.detail.contains("5,000 miles") == true)
        XCTAssertTrue(items.allSatisfy { !$0.title.localizedCaseInsensitiveContains("stress") })
        XCTAssertTrue(items.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("productivity") })
        XCTAssertTrue(items.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("coaching") })
        XCTAssertTrue(items.allSatisfy { $0.detail.contains("No ") || $0.kind != .intervalReminder })
        XCTAssertTrue(items.allSatisfy { !$0.evidence.isEmpty || $0.kind == .normalizationCandidate })
    }

    func testSoftLowInformationExtractionDoesNotGenerateReviewItem() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "Still have a hole in the wall and unsure what to do with it.",
            extractionStatus: .partiallySucceeded
        )
        let envelope = ExtractionEnvelope.empty(
            warnings: [ExtractionWarning(code: "requires_review", message: "low_information_message")]
        )
        let attempt = ExtractionAttempt(
            status: .partiallySucceeded,
            normalizedJSONText: try envelope.jsonString(),
            createdNoteIDs: [UUID()],
            sourceMessage: message
        )

        context.insert(message)
        context.insert(attempt)
        try context.save()

        let items = try service(context).refresh()

        XCTAssertFalse(items.contains { $0.kind == .extractionReview && $0.targetID == message.id })
    }

    func testActionableExtractionWarningStillGeneratesReviewItem() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today.",
            extractionStatus: .partiallySucceeded
        )
        let envelope = ExtractionEnvelope.empty(
            warnings: [ExtractionWarning(code: "requires_review", message: "possible_duplicate")]
        )
        let attempt = ExtractionAttempt(
            status: .partiallySucceeded,
            normalizedJSONText: try envelope.jsonString(),
            createdEventIDs: [UUID()],
            sourceMessage: message
        )

        context.insert(message)
        context.insert(attempt)
        try context.save()

        let item = try XCTUnwrap(try service(context).refresh().first { $0.kind == .extractionReview })

        XCTAssertEqual(item.targetID, message.id)
    }

    func testDedupePreventsRepeatedPromptAfterDismissal() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Needs retry.", extractionStatus: .pendingRetry)
        context.insert(message)
        try context.save()

        let generated = try XCTUnwrap(service(context).refresh().first)
        generated.dismiss(at: date(day: 2))
        try context.save()

        let refreshed = try service(context).refresh()

        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed.first?.id, generated.id)
        XCTAssertEqual(refreshed.first?.state, .dismissed)
    }

    func testRecoveryItemsExplainConcreteLocalNextStep() throws {
        let context = makeInMemoryModelContext()
        let missingToken = ChatMessage(
            role: .user,
            text: "Needs service token.",
            extractionStatus: .pendingToken,
            extractionErrorCode: .missingServiceToken
        )
        let invalidToken = ChatMessage(
            role: .user,
            text: "Needs updated key.",
            extractionStatus: .pendingToken,
            extractionErrorCode: .invalidServiceToken
        )
        let timedOut = ChatMessage(
            role: .user,
            text: "Needs connection.",
            extractionStatus: .pendingRetry,
            extractionErrorCode: .timeout
        )
        [missingToken, invalidToken, timedOut].forEach(context.insert)
        try context.save()

        let details = Set(try service(context).refresh().map(\.detail))

        XCTAssertTrue(details.contains("The original entry is saved locally. Retry this entry to connect its details."))
        XCTAssertTrue(details.contains("The original entry is saved locally. Retry this entry to reconnect its details."))
        XCTAssertTrue(details.contains("The original entry is saved locally. Use Retry Now when your connection is working, or wait for the next automatic retry."))
        XCTAssertTrue(details.allSatisfy { !$0.localizedCaseInsensitiveContains("process") })
        XCTAssertTrue(details.allSatisfy { !$0.localizedCaseInsensitiveContains("assistant") })
    }

    func testAmbiguousReminderReviewIncludesSuggestedInterpretationEvidenceAndDedupe() async throws {
        let context = makeInMemoryModelContext()
        let now = date(year: 2026, month: 5, day: 20)
        let input = "I think Bogey needs a haircut in a week or two."
        _ = try await ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: now)
        ).send(input)

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let thing = try XCTUnwrap(try context.fetch(FetchDescriptor<Thing>()).first)
        let originalThingIDs = try context.fetch(FetchDescriptor<Thing>()).map(\.id)
        let originalRuleIDs = try context.fetch(FetchDescriptor<LedgerRule>()).map(\.id)
        let originalNoteIDs = try context.fetch(FetchDescriptor<LedgerNote>()).map(\.id)

        let items = try service(context, now: now).refresh()
        let item = try XCTUnwrap(items.first { $0.kind == .extractionReview && $0.targetID == message.id })
        let entry = try LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(token: "sk-test-device-token")
        ).entry(for: item)

        XCTAssertEqual(item.state, .candidate)
        XCTAssertEqual(item.targetType, .chatMessage)
        XCTAssertEqual(item.targetID, message.id)
        XCTAssertEqual(item.title, "Review reminder for Bogey")
        XCTAssertEqual(item.actionTitle, "Choose Date")
        XCTAssertTrue(item.detail.localizedCaseInsensitiveContains("haircut reminder for Bogey"))
        XCTAssertTrue(item.detail.contains("\"in a week or two\""))
        XCTAssertTrue(item.detail.contains("May 27 to June 3, 2026"))
        XCTAssertTrue(item.detail.contains("no exact reminder date was saved"))
        XCTAssertTrue(item.evidence.contains { $0.sourceType == .chatMessage && $0.sourceID == message.id && $0.summary == input })
        XCTAssertTrue(item.evidence.contains { $0.summary == "Suggested reminder: Haircut for Bogey" })
        XCTAssertTrue(item.evidence.contains { $0.sourceType == .thing && $0.sourceID == thing.id })
        XCTAssertEqual(entry.correctionClass, .quickReview)
        XCTAssertEqual(entry.primaryActionTitle, "Choose Date")
        XCTAssertEqual(entry.createdRecords.map(\.title), ["Bogey"])
        XCTAssertTrue(entry.blockedMessage?.contains("created saved records") == true)
        XCTAssertTrue(entry.isActionBlocked)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).map(\.id), originalThingIDs)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).map(\.id), originalRuleIDs)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).map(\.id), originalNoteIDs)

        let refreshed = try service(context, now: now).refresh()
        let matching = refreshed.filter { $0.kind == .extractionReview && $0.targetID == message.id }

        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.id, item.id)
    }

    func testResolvedUnderlyingConditionsSupersedeOpenItems() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Needs retry.", extractionStatus: .pendingRetry)
        context.insert(message)
        try context.save()

        let generated = try XCTUnwrap(service(context).refresh().first)
        message.extractionStatus = .succeeded
        try context.save()
        _ = try service(context).refresh()

        XCTAssertEqual(generated.state, .superseded)
    }

    func testExistingActiveReminderSuppressesIntervalCandidate() throws {
        let context = makeInMemoryModelContext()
        let filters = thing("HVAC air filter", category: .homeMaintenance)
        filters.events = [
            event("Replaced HVAC air filter", day: 1, type: .replacement, thing: filters),
            event("Replaced HVAC air filter", day: 91, type: .replacement, thing: filters),
            event("Replaced HVAC air filter", day: 181, type: .replacement, thing: filters)
        ]
        filters.rules = [
            LedgerRule(
                title: "Replace HVAC air filter",
                ruleType: .reminder,
                startsAt: date(day: 190),
                thing: filters
            )
        ]
        context.insert(filters)
        try context.save()

        let items = try service(context, now: date(day: 182)).refresh()

        XCTAssertFalse(items.contains { $0.kind == .intervalReminder })
    }

    func testDuplicateThingCandidatesConsiderAliases() throws {
        let context = makeInMemoryModelContext()
        let storage = thing("Storage renewal")
        let boxwell = thing("Boxwell")
        storage.registerAlias("Boxwell", updatedAt: date(day: 10))

        context.insert(storage)
        context.insert(boxwell)
        try context.save()

        let item = try XCTUnwrap(try service(context).refresh().first { $0.kind == .duplicateThing })

        XCTAssertTrue(item.detail.contains("normalized name or alias"))
        XCTAssertEqual(Set(item.evidence.map(\.summary)), ["Storage renewal", "Boxwell"])
    }

    func testConflictingDateReviewIgnoresSameCalendarDayMetadataDatetime() throws {
        let context = makeInMemoryModelContext()
        let eventDate = date(year: 2026, month: 5, day: 24)
        let event = LedgerEvent(
            title: "Call my mother and Caitlyn",
            occurredAt: eventDate,
            rawText: "Call my mother and Caitlyn tomorrow.",
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .dueDate,
                    valueKind: .date,
                    dateValue: "2026-05-24T00:00:00-04:00",
                    sourceText: "tomorrow"
                )
            ]
        )
        context.insert(event)
        try context.save()

        let items = try service(context, now: date(year: 2026, month: 5, day: 23)).refresh()

        XCTAssertFalse(items.contains { $0.kind == .conflictingDate && $0.targetID == event.id })
    }

    func testConflictingDateReviewStillFlagsDifferentCalendarDayMetadata() throws {
        let context = makeInMemoryModelContext()
        let event = LedgerEvent(
            title: "Window service renewal",
            occurredAt: date(year: 2026, month: 5, day: 24),
            rawText: "Window service renewal due May 25.",
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .dueDate,
                    valueKind: .date,
                    dateValue: "2026-05-25T00:00:00-04:00",
                    sourceText: "May 25"
                )
            ]
        )
        context.insert(event)
        try context.save()

        let item = try XCTUnwrap(try service(context, now: date(year: 2026, month: 5, day: 23)).refresh().first { $0.kind == .conflictingDate })

        XCTAssertEqual(item.targetID, event.id)
        XCTAssertTrue(item.detail.contains("saved metadata includes 2026-05-25"))
    }

    private func service(
        _ context: ModelContext,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> LedgerReviewItemGenerationService {
        LedgerReviewItemGenerationService(
            modelContext: context,
            now: { now },
            calendar: calendar,
            intervalInference: OperationalIntervalInferenceService(calendar: calendar)
        )
    }

    private func thing(_ name: String, category: ThingCategory? = nil) -> Thing {
        Thing(name: name, category: category)
    }

    private func event(
        _ title: String,
        day: Int,
        type: LedgerEventType,
        thing: Thing?,
        mileage: Double? = nil,
        subtype: String? = nil,
        metadata: [LedgerEventMetadataEntry]? = nil
    ) -> LedgerEvent {
        LedgerEvent(
            title: title,
            occurredAt: date(day: day),
            rawText: title,
            createdAt: date(day: day),
            updatedAt: date(day: day),
            eventType: type,
            metadataEntries: metadata ?? [
                mileage.map { LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: $0, unit: "mi") },
                subtype.map { LedgerEventMetadataEntry(key: .subtype, valueKind: .string, stringValue: $0) }
            ].compactMap { $0 },
            thing: thing
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day))!
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
