import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class ContinuityScenarioRegressionTests: XCTestCase {
    func testOperationalHomeScenarioKeepsHouseholdContinuityReviewableAndLocal() throws {
        let context = makeInMemoryModelContext()
        let now = date(2026, 7, 5, 12)
        let scenario = try OperationalHomeScenarioFactory(calendar: calendar).scenario(now: now, context: context)
        let intervalService = OperationalIntervalInferenceService(calendar: calendar)

        let filterInference = try XCTUnwrap(intervalService.inferences(for: scenario.filters, now: now).first)
        XCTAssertEqual(filterInference.track, .airFilter)
        XCTAssertEqual(filterInference.calendarIntervalDays, 90)
        XCTAssertEqual(filterInference.nextExpectedDateRange?.start, date(2026, 9, 23))
        XCTAssertEqual(filterInference.nextExpectedDateRange?.end, date(2026, 10, 11))
        XCTAssertEqual(filterInference.confidence.level, .medium)
        XCTAssertEqual(filterInference.evidence.filter { $0.source == .event }.map(\.summary), scenario.filterEvents.map(\.title))

        let dogFoodInference = try XCTUnwrap(intervalService.inferences(for: scenario.dogFood, now: now).first)
        XCTAssertEqual(dogFoodInference.track, .dogFood)
        XCTAssertEqual(dogFoodInference.calendarIntervalDays, 25)
        XCTAssertEqual(dogFoodInference.nextExpectedDateRange?.start, date(2026, 6, 5))
        XCTAssertEqual(dogFoodInference.nextExpectedDateRange?.end, date(2026, 6, 7))
        XCTAssertEqual(dogFoodInference.confidence.level, .strong)
        XCTAssertEqual(dogFoodInference.operationalReason, "This is based on saved purchase records for a recurring household supply.")
        XCTAssertTrue(dogFoodInference.evidence.contains { $0.summary == "25-day interval" })
        XCTAssertTrue(dogFoodInference.evidence.contains { $0.detail?.contains("Corner Pet Supply") == true })

        let oilInference = try XCTUnwrap(intervalService.inferences(for: scenario.car, now: now).first)
        XCTAssertEqual(oilInference.track, .oilChange)
        XCTAssertEqual(oilInference.mileageInterval, 5_000)
        XCTAssertEqual(oilInference.nextExpectedMileage, 45_000)

        XCTAssertTrue(intervalService.inferences(for: scenario.garage, now: now).isEmpty)
        XCTAssertTrue(intervalService.inferences(for: scenario.householdSupplies, now: now).isEmpty)
        XCTAssertTrue(intervalService.inferences(for: scenario.dryerVent, now: now).isEmpty)
        XCTAssertTrue(intervalService.inferences(for: scenario.smokeDetectorBatteries, now: now).isEmpty)

        let reviewItems = try reviewGenerationService(context, now: now).refresh()
        let filterReviewItem = try XCTUnwrap(reviewItems.first {
            $0.kind == .intervalReminder && $0.targetID == scenario.filters.id
        })
        XCTAssertEqual(filterReviewItem.title, "Air filter cadence is ready for review")
        XCTAssertTrue(filterReviewItem.detail.contains("Saved items show about every 90 days."))
        XCTAssertTrue(filterReviewItem.detail.contains("next date range 2026-09-23 to 2026-10-11"))
        XCTAssertTrue(filterReviewItem.detail.contains("No reminder has been created or changed."))

        let dogFoodReviewItem = try XCTUnwrap(reviewItems.first {
            $0.kind == .intervalReminder && $0.targetID == scenario.dogFood.id
        })
        XCTAssertEqual(dogFoodReviewItem.title, "Dog food purchase cadence is ready for review")
        XCTAssertTrue(dogFoodReviewItem.detail.contains("Saved items show about every 25 days."))
        XCTAssertTrue(dogFoodReviewItem.detail.contains("next date range 2026-06-05 to 2026-06-07"))
        XCTAssertTrue(dogFoodReviewItem.detail.contains("No reminder has been created or changed."))

        XCTAssertTrue(reviewItems.contains { $0.kind == .intervalReminder && $0.targetID == scenario.car.id })
        XCTAssertFalse(reviewItems.contains { $0.kind == .intervalReminder && $0.targetID == scenario.garage.id })
        XCTAssertFalse(reviewItems.contains { $0.kind == .intervalReminder && $0.targetID == scenario.householdSupplies.id })
        XCTAssertFalse(reviewItems.contains { $0.kind == .intervalReminder && $0.targetID == scenario.dryerVent.id })
        XCTAssertFalse(reviewItems.contains { $0.kind == .intervalReminder && $0.targetID == scenario.smokeDetectorBatteries.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerRule>()).allSatisfy { $0.thing?.id != scenario.dogFood.id })

        let reminder = LedgerRule(
            title: "Replace Home Air Filters",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Replace Home Air Filters on the calendar.",
            startsAt: date(2026, 9, 30),
            createdAt: now,
            updatedAt: now,
            thing: scenario.filters
        )
        scenario.filters.rules = [reminder]
        context.insert(reminder)
        try context.save()

        let suppressed = try XCTUnwrap(intervalService.inferences(for: scenario.filters, now: now, includeSuppressed: true).first)
        XCTAssertTrue(suppressed.isSuppressed)
        XCTAssertNil(suppressed.reviewItem())
        XCTAssertTrue(suppressed.suppressionReason?.contains("Existing scheduled reminder") == true)
        XCTAssertTrue(suppressed.suppressionReason?.contains("Replace Home Air Filters") == true)
        XCTAssertTrue(suppressed.suppressionReason?.contains("covers this operational cadence") == true)

        let reviewItemsAfterReminder = try reviewGenerationService(context, now: now).refresh()
        XCTAssertFalse(reviewItemsAfterReminder.contains {
            $0.kind == .intervalReminder && $0.targetID == scenario.filters.id && isOpenReviewState($0.state)
        })
        XCTAssertTrue(reviewItemsAfterReminder.contains {
            $0.kind == .intervalReminder && $0.targetID == scenario.dogFood.id && isOpenReviewState($0.state)
        })
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 1)

        let detailSnapshot = ThingDetailSnapshot(thing: scenario.filters, now: now, calendar: calendar)
        XCTAssertEqual(detailSnapshot.continuitySummary?.label, "Replacement rhythm")
        XCTAssertEqual(detailSnapshot.continuitySummary?.value, "About every 90 days")
        XCTAssertEqual(detailSnapshot.continuitySummary?.detail, "Reminder already saved: Replace Home Air Filters")

        let dogFoodSnapshot = ThingDetailSnapshot(thing: scenario.dogFood, now: now, calendar: calendar)
        XCTAssertEqual(dogFoodSnapshot.continuitySummary?.label, "Purchase rhythm")
        XCTAssertEqual(dogFoodSnapshot.continuitySummary?.value, "About every 25 days")

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            things: scenario.allThings,
            events: scenario.allEvents,
            reminders: [reminder],
            notes: []
        )
        let replay = TimelineSliceReplayModel(title: "Operational home timeline", query: TimelineSliceQuery(), rows: rows, calendar: calendar, now: now)
        let replayLabels = replay.sections.flatMap(\.rows).map(\.displayLabel)
        XCTAssertTrue(replayLabels.contains("Replaced Home Air Filters"))
        XCTAssertTrue(replayLabels.contains("Bought dog food"))
        XCTAssertTrue(replayLabels.contains("Cleaned garage"))
        XCTAssertTrue(replayLabels.contains("Bought household supplies"))
        XCTAssertTrue(replayLabels.contains("Cleaned dryer vent"))
        XCTAssertTrue(replayLabels.contains("Replaced smoke detector battery"))
        XCTAssertTrue(replayLabels.contains("Replace Home Air Filters"))
        let replayText = replaySurfaceText(replay)
        XCTAssertTrue(replayText.contains { $0.contains("Corner Pet Supply") })
        XCTAssertTrue(replayText.contains { $0.contains("30 lb") })
        XCTAssertTrue(replayText.contains { $0.contains("Harbor Warehouse") })
        XCTAssertTrue(replayText.contains { $0.contains("$163.40") || $0.contains("163.4") })
        XCTAssertTrue(replayText.contains { $0.contains("donation pile") })
        XCTAssertTrue(replayText.contains { $0.contains("exterior flap") })
        XCTAssertTrue(replayText.contains { $0.contains("basement smoke detector") })
        let replayTargets = replay.sections.flatMap(\.rows).map(\.navigationTarget)
        XCTAssertTrue(replayTargets.contains(.eventDetail(scenario.filterEvents[2].id)))
        XCTAssertTrue(replayTargets.contains(.eventDetail(scenario.dogFoodEvents[4].id)))
        XCTAssertTrue(replayTargets.contains(.eventDetail(scenario.householdSupplyEvents[1].id)))
        XCTAssertTrue(replayTargets.contains(.eventDetail(scenario.garageEvents[1].id)))
        XCTAssertTrue(replayTargets.contains(.ruleDetail(reminder.id)))

        let search = SearchService()
        let searchRecords = search.records(things: scenario.allThings, events: scenario.allEvents, rules: [reminder], notes: [])
        assertSearch(search, "air filters", in: searchRecords, includes: [.thingDetail(scenario.filters.id), .eventDetail(scenario.filterEvents[2].id), .ruleDetail(reminder.id)])
        assertSearch(search, "dog food", in: searchRecords, includes: [.thingDetail(scenario.dogFood.id), .eventDetail(scenario.dogFoodEvents[4].id)])
        assertSearch(search, "30 lb", in: searchRecords, includes: [.eventDetail(scenario.dogFoodEvents[4].id)])
        assertSearch(search, "garage", in: searchRecords, includes: [.thingDetail(scenario.garage.id), .eventDetail(scenario.garageEvents[1].id)])
        assertSearch(search, "Harbor Warehouse", in: searchRecords, includes: scenario.householdSupplyEvents.map { .eventDetail($0.id) })
        assertSearch(search, "163.40", in: searchRecords, includes: [.eventDetail(scenario.householdSupplyEvents[1].id)])
        assertSearch(search, "dryer vent", in: searchRecords, includes: [.thingDetail(scenario.dryerVent.id), .eventDetail(scenario.dryerVentEvents[1].id)])
        assertSearch(search, "smoke detector", in: searchRecords, includes: [.thingDetail(scenario.smokeDetectorBatteries.id), .eventDetail(scenario.smokeDetectorEvents[1].id)])

        assertNoOperationalLanguageLeaks(
            [
                filterInference.operationalReason,
                dogFoodInference.operationalReason,
                dogFoodReviewItem.title,
                dogFoodReviewItem.detail,
                filterReviewItem.title,
                filterReviewItem.detail,
                suppressed.suppressionReason ?? ""
            ] + replayText + surfaceText(from: search.search("dog food", in: searchRecords))
        )
    }

    func testCarContinuityScenarioCombinesMileageReminderRelatedHistoryAndReplay() throws {
        let now = date(2026, 5, 20, 12)
        let car = Thing(
            name: "Blue sedan",
            aliases: ["daily driver"],
            category: .vehicle,
            createdAt: date(2025, 6, 1),
            updatedAt: now
        )
        let oilChanges = [
            event("Oil change", on: date(2025, 6, 1), type: .maintenance, thing: car, mileage: 30_000, subtype: "oil_change"),
            event("Oil change", on: date(2025, 12, 1), type: .maintenance, thing: car, mileage: 35_000, subtype: "oil_change"),
            event("Oil change", on: date(2026, 5, 1), type: .maintenance, thing: car, mileage: 40_000, subtype: "oil_change")
        ]
        let tireRotation = event("Tire rotation", on: date(2026, 5, 3), type: .maintenance, thing: car, mileage: 40_200, subtype: "tire_rotation")
        let registration = event("Registration renewal", on: date(2026, 5, 8), type: .renewal, thing: car)
        let insurance = LedgerNote(text: "Insurance card is in the glove box.", createdAt: date(2026, 5, 9), linkedThings: [car])
        let reminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            startsAt: date(2026, 6, 15),
            createdAt: date(2026, 5, 9),
            thing: car
        )
        car.events = oilChanges + [tireRotation, registration]
        car.rules = [reminder]

        let inference = try XCTUnwrap(OperationalIntervalInferenceService(calendar: calendar).inferences(for: car, now: now).first)
        XCTAssertEqual(inference.track, .oilChange)
        XCTAssertEqual(inference.mileageInterval, 5_000)
        XCTAssertEqual(inference.nextExpectedMileage, 45_000)
        XCTAssertTrue((44_500...45_500).contains(try XCTUnwrap(inference.nextExpectedMileage)))
        XCTAssertEqual(inference.calendarIntervalDays, 167)
        XCTAssertTrue(inference.evidence.contains { $0.source == .derivedMileageInterval && $0.summary == "5000-mile interval" })

        let related = RuleRelatedEventService().relatedEvents(for: reminder, events: oilChanges + [tireRotation, registration])
        XCTAssertTrue(related.contains { $0.event.id == registration.id && $0.source == .sharedThing })
        XCTAssertTrue(related.contains { $0.event.id == tireRotation.id && $0.source == .sharedThing })

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            query: TimelineSliceReplayDescriptor.linkedThing(car).query,
            things: [car],
            events: oilChanges + [tireRotation, registration],
            reminders: [reminder],
            notes: [insurance]
        )
        let replay = TimelineSliceReplayModel(
            title: "Blue sedan timeline",
            query: TimelineSliceReplayDescriptor.linkedThing(car).query,
            rows: rows,
            calendar: calendar,
            now: now
        )
        let replayLabels = replay.sections.flatMap(\.rows).map(\.displayLabel)
        XCTAssertTrue(replayLabels.contains("Oil change"))
        XCTAssertTrue(replayLabels.contains("Tire rotation"))
        XCTAssertTrue(replayLabels.contains("Registration renewal"))
        XCTAssertTrue(replay.sections.flatMap(\.rows).contains { $0.summaryText.contains("Insurance card") })
        XCTAssertTrue(replay.sections.flatMap(\.rows).contains { $0.navigationTarget == .ruleDetail(reminder.id) })

        let search = SearchService()
        let records = search.records(things: [car], events: oilChanges + [tireRotation, registration], rules: [reminder], notes: [insurance])
        XCTAssertTrue(search.search("40,000", in: records).contains { $0.navigationTarget == .eventDetail(oilChanges[2].id) })
        XCTAssertTrue(search.search("insurance", in: records).contains { $0.navigationTarget == .noteDetail(insurance.id) })
        XCTAssertTrue(search.search("registration", in: records).contains { $0.navigationTarget == .ruleDetail(reminder.id) })
        assertNoLeakedPrimarySurfaceTerms(surfaceText(from: search.search("car", in: records)) + replaySurfaceText(replay))
    }

    func testWorkSecurityNormalizationReviewCorrectionAndRecallStayLocal() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let canonical = Thing(name: "Nimbus Web Services", aliases: ["Nimbus infra"], category: .work, createdAt: now, updatedAt: now)
        let message = ChatMessage(role: .user, text: "NWS security review found vulns for auth.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        context.insert(canonical)
        context.insert(message)
        context.insert(attempt)

        let acronymCandidate = try XCTUnwrap(ThingNormalizer.candidates(
            for: "NWS",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [canonical],
            modelConfidence: 0.86
        ).first)
        XCTAssertEqual(acronymCandidate.targetThingID, canonical.id)
        XCTAssertEqual(acronymCandidate.matchReason, .acronymVariant)
        XCTAssertEqual(acronymCandidate.sourceEvidence.first?.categoryEvidence?.primaryCategory, .work)
        XCTAssertFalse(acronymCandidate.allowsAutomaticMerge)

        let securityCanonical = Thing(name: "Vulnerabilities", category: .work, createdAt: now, updatedAt: now)
        let abbreviationCandidate = try XCTUnwrap(ThingNormalizer.candidates(
            for: "vulns",
            aliases: ["security issues"],
            categoryHint: "work",
            contextText: message.text,
            existingThings: [securityCanonical],
            modelConfidence: 0.7
        ).first)
        XCTAssertEqual(abbreviationCandidate.matchReason, .seedAlias)
        XCTAssertTrue(abbreviationCandidate.allowsAutomaticMerge)

        let sourceThing = try ThingResolver(modelContext: context, now: { now }).resolve(
            name: "NWS",
            aliases: [],
            categoryHint: "work",
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt,
            modelConfidence: 0.86
        )
        let securityEvent = event("Security review", on: now, type: .project, thing: sourceThing)
        let followUp = LedgerRule(title: "Review NWS auth notes", ruleType: .reminder, startsAt: now.addingTimeInterval(86_400), thing: sourceThing)
        let note = LedgerNote(text: "Security alias NWS should point to Nimbus Web Services.", createdAt: now, linkedThings: [sourceThing])
        context.insert(securityCanonical)
        context.insert(securityEvent)
        context.insert(followUp)
        context.insert(note)
        try context.save()

        let generatedItem = try XCTUnwrap(
            try context.fetch(FetchDescriptor<LedgerReviewItem>()).first { $0.kind == .normalizationCandidate }
        )
        XCTAssertEqual(generatedItem.title, "Thing match needs review")
        XCTAssertTrue(generatedItem.detail.contains("NWS may match Nimbus Web Services"))
        XCTAssertTrue(generatedItem.detail.contains("No items have been merged"))

        let correctionItem = LedgerReviewItem(
            dedupeKey: "normalization_candidate|scenario|\(sourceThing.id.uuidString)",
            kind: .normalizationCandidate,
            title: "Thing match needs review",
            detail: "NWS may match Nimbus Web Services. No items have been merged.",
            actionTitle: "Review Thing",
            targetType: .thing,
            targetID: sourceThing.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: securityEvent.id, summary: securityEvent.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .rule, sourceID: followUp.id, summary: followUp.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .none, sourceID: note.id, summary: note.text, detail: nil),
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: canonical.id, summary: canonical.name, detail: nil)
            ],
            createdAt: now,
            updatedAt: now
        )
        context.insert(correctionItem)
        try context.save()

        let queue = LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"),
            dateProvider: TestDateProvider(now: now)
        )
        let entry = try queue.entry(for: correctionItem)
        XCTAssertEqual(entry.correctionClass, .reassignRecordsToThing)
        XCTAssertEqual(entry.primaryActionTitle, "Review Thing")
        try queue.reassignRecords(from: correctionItem, to: canonical.id)

        XCTAssertEqual(securityEvent.thing?.id, canonical.id)
        XCTAssertEqual(followUp.thing?.id, canonical.id)
        XCTAssertEqual(note.linkedThingIDs, [canonical.id])
        XCTAssertEqual(correctionItem.state, .accepted)

        let recallAnswer = try ChatRecallResponseService(modelContext: context, now: now).answer(
            for: ChatIntentClassification(intent: .localSearch, targetText: "security")
        )
        XCTAssertTrue(recallAnswer.contains("Local results:"))
        XCTAssertTrue(recallAnswer.contains("Security review"))
        XCTAssertTrue(recallAnswer.contains("Related to Nimbus Web Services") || recallAnswer.contains("For Nimbus Web Services"))
        assertNoLeakedPrimarySurfaceTerms([generatedItem.title, generatedItem.detail, entry.title, entry.detail, recallAnswer])
    }

    func testLocalFirstRecoveryExportAndClearSafeguardsPreserveUserControl() async throws {
        let context = makeInMemoryModelContext()
        let tokenStore = InMemoryDeviceTokenStore(token: "unit-test-device-token")
        let now = fixedTestNow

        try await ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.missingServiceToken),
            dateProvider: TestDateProvider(now: now)
        ).send("Replaced Home Air Filters.")
        try await ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.invalidServiceToken),
            dateProvider: TestDateProvider(now: now.addingTimeInterval(1))
        ).send("Changed car oil at 40,000 miles.")
        try await ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: now.addingTimeInterval(2))
        ).send("Bought dog food.")

        let userMessages = try context.fetch(FetchDescriptor<ChatMessage>())
            .filter { $0.role == .user }
            .sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(userMessages.map(\.text), [
            "Replaced Home Air Filters.",
            "Changed car oil at 40,000 miles.",
            "Bought dog food."
        ])
        XCTAssertEqual(userMessages.map(\.extractionStatus), [.pendingToken, .pendingToken, .pendingRetry])
        XCTAssertEqual(userMessages.map(\.extractionErrorCode), [.missingServiceToken, .invalidServiceToken, .serverError])
        XCTAssertNil(userMessages[0].nextExtractionRetryAt)
        XCTAssertNil(userMessages[1].nextExtractionRetryAt)
        XCTAssertEqual(userMessages[2].nextExtractionRetryAt, now.addingTimeInterval(62))

        let reviewItems = try reviewGenerationService(context, now: now).refresh()
        XCTAssertEqual(reviewItems.filter { $0.kind == .localRecovery }.count, 3)
        XCTAssertTrue(reviewItems.contains { $0.detail.contains("entry is saved on this device") && $0.actionTitle == "Try Again" })
        XCTAssertTrue(reviewItems.contains { $0.detail.contains("Try again later") && $0.actionTitle == "Try Again" })

        let search = SearchService()
        let searchResults = search.search("dog food", in: search.records(things: [], messages: userMessages))
        XCTAssertTrue(searchResults.contains { $0.sourceKind == .chatMessage && $0.title == "You" })
        let feedSurface = userMessages.map { message in
            LedgerFeedRowContent(item: .message(message)).sourceLabel
        }

        let export = try LocalJSONExportService(
            modelContext: context,
            now: { now },
            calendar: calendar,
            timeZone: calendar.timeZone
        ).envelope()
        let exportedUsers = export.records.chatMessages.filter { $0.role == "user" }
        XCTAssertEqual(exportedUsers.count, 3)
        XCTAssertTrue(exportedUsers.contains { $0.text == "Replaced Home Air Filters." && $0.extractionState?.recoveryAction?.contains("Try this entry again when the service is available") == true })
        XCTAssertTrue(exportedUsers.contains { $0.text == "Changed car oil at 40,000 miles." && $0.extractionState?.recoveryAction?.contains("Try this entry again when the service is available") == true })
        XCTAssertTrue(exportedUsers.contains { $0.text == "Bought dog food." && $0.extractionState?.recoveryAction?.contains("Try this entry again") == true })

        var clearFlow = SettingsClearDataFlow()
        XCTAssertTrue(clearFlow.offersExportBeforeClear)
        XCTAssertTrue(SettingsClearDataCopy.exportPrompt.contains("Before clearing"))
        clearFlow.exportSucceeded()
        XCTAssertTrue(clearFlow.showsFinalConfirmation)

        let staleContext = makeInMemoryModelContext()
        let sessionState = AppSessionState()
        let staleGeneration = sessionState.dataGeneration
        let controlledExtractor = ControlledScenarioExtractionClient()
        let extractionStarted = expectation(description: "extraction started")
        controlledExtractor.onStart = { extractionStarted.fulfill() }
        let sendTask = Task { @MainActor in
            try await ChatSendService(
                modelContext: staleContext,
                extractor: controlledExtractor,
                dataGeneration: staleGeneration,
                isDataGenerationCurrent: sessionState.isCurrentDataGeneration
            ).send("Changed oil.") == nil
        }

        await fulfillment(of: [extractionStarted], timeout: 2)
        sessionState.invalidateInFlightDataWork()
        try LocalDataClearService(modelContext: staleContext).clearLedgerData()
        sessionState.reloadAfterLocalDataClear()
        controlledExtractor.succeed(
            ExtractionResponsePayload(
                rawResponseText: canonicalExtractionJSON(
                    events: [canonicalEvent("event_1", title: "Changed oil", thingRef: nil, occurredAt: "2027-01-15")]
                )
            )
        )
        let staleCompletionSuppressed = try await sendTask.value
        XCTAssertTrue(staleCompletionSuppressed)
        try assertStoreIsEmpty(staleContext)

        try LocalDataClearService(modelContext: context).clearLedgerData()
        XCTAssertEqual(try tokenStore.loadDeviceToken(), "unit-test-device-token")
        try assertStoreIsEmpty(context)
        XCTAssertTrue(LedgerFeedProjection().sections(messages: [], events: [], reminders: [], notes: []).isEmpty)
        XCTAssertTrue(SearchService().records(things: [], events: [], rules: [], notes: [], messages: []).isEmpty)
        XCTAssertTrue(try LedgerReviewQueueService(modelContext: context, deviceTokenStore: tokenStore).entries(from: []).isEmpty)
        assertNoLeakedPrimarySurfaceTerms(
            feedSurface + reviewItems.flatMap { [$0.title, $0.detail, $0.actionTitle ?? ""] } + surfaceText(from: searchResults)
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func reviewGenerationService(_ context: ModelContext, now: Date) -> LedgerReviewItemGenerationService {
        LedgerReviewItemGenerationService(
            modelContext: context,
            now: { now },
            calendar: calendar,
            intervalInference: OperationalIntervalInferenceService(calendar: calendar)
        )
    }

    private func event(
        _ title: String,
        on date: Date,
        type: LedgerEventType,
        thing: Thing,
        mileage: Double? = nil,
        subtype: String? = nil,
        rawText: String? = nil,
        metadata: [LedgerEventMetadataEntry]? = nil
    ) -> LedgerEvent {
        LedgerEvent(
            title: title,
            occurredAt: date,
            rawText: rawText ?? title,
            createdAt: date,
            updatedAt: date,
            eventType: type,
            metadataEntries: metadata ?? [
                mileage.map { LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: $0, unit: "mi") },
                subtype.map { LedgerEventMetadataEntry(key: .subtype, valueKind: .string, stringValue: $0) }
            ].compactMap { $0 },
            thing: thing
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
