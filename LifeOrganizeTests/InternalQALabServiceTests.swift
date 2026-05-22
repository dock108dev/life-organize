import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class InternalQALabServiceTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "InternalQALabServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testDebugPolicySeparatesInternalQAGateFromExtractionNaming() {
        let locked = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: false)
        let unlocked = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: true)

        XCTAssertFalse(locked.allowsInternalQAScreens)
        XCTAssertTrue(unlocked.allowsInternalQAScreens)
        XCTAssertEqual(DeveloperModeRequiredContent.internalQA.description, "Unlock developer mode from Settings to use internal QA tools.")
    }

    func testFixtureLoaderUsesNamedScenarioRegistryAndDoesNotDuplicateRecords() throws {
        let context = makeInMemoryModelContext()
        let loader = QAFixtureLoader(modelContext: context)
        let descriptor = try XCTUnwrap(loader.descriptors().first { $0.id == "car_maintenance" })

        let firstResult = try loader.load(descriptor, options: QAFixtureLoadOptions())
        let countsAfterFirstLoad = try storeCounts(context)
        let secondResult = try loader.load(descriptor, options: QAFixtureLoadOptions())
        let countsAfterSecondLoad = try storeCounts(context)

        XCTAssertEqual(firstResult.insertedCounts.things, 1)
        XCTAssertEqual(countsAfterFirstLoad, countsAfterSecondLoad)
        XCTAssertTrue(secondResult.warnings.contains("Fixture records already existed and were updated in place."))
    }

    func testFixtureLoaderCanApplyRecommendedFakeDate() throws {
        let context = makeInMemoryModelContext()
        let store = QAFakeDateStore(defaults: defaults, key: "fake-date")
        let loader = QAFixtureLoader(modelContext: context, fakeDateStore: store)
        let descriptor = try XCTUnwrap(loader.descriptors().first { $0.id == "car_maintenance" })

        _ = try loader.load(descriptor, options: QAFixtureLoadOptions(applyRecommendedFakeDate: true))

        XCTAssertEqual(store.overrideDate, descriptor.recommendedFakeNow)
    }

    func testDatabaseResetClearsLedgerDataAndOptionalFakeDate() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Reset me.", createdAt: fixedTestNow)
        context.insert(message)
        try context.save()
        let store = QAFakeDateStore(defaults: defaults, key: "fake-date")
        store.setOverride(fixedTestNow)

        try QADatabaseResetService(modelContext: context, fakeDateStore: store).reset()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatMessage>()).isEmpty)
        XCTAssertNil(store.overrideDate)
    }

    func testFakeDateStoreParsesDisplaysAndFallsBack() throws {
        let store = QAFakeDateStore(defaults: defaults, key: "fake-date")
        let parsed = try store.parseOverride("2026-05-20T09:00:00-04:00")

        XCTAssertEqual(store.effectiveNow(fallback: fixedTestNow), fixedTestNow)
        store.setOverride(parsed)
        XCTAssertEqual(store.effectiveNow(fallback: fixedTestNow), parsed)
        XCTAssertEqual(store.displayText(for: parsed), "2026-05-20T13:00:00Z")
    }

    func testGraphInspectionReportsIntegrityProvenanceAndAffectedSources() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Lunch with Jordan.", createdAt: fixedTestNow)
        let thing = Thing(name: "Jordan", sourceMessageIDs: [message.id])
        let event = LedgerEvent(
            title: "Lunch with Jordan",
            occurredAt: fixedTestNow,
            rawText: "Lunch with Jordan.",
            sourceExtractionRunID: UUID(),
            thing: thing,
            sourceMessage: message
        )
        let badLink = EntityLink(
            sourceType: .event,
            sourceID: event.id,
            targetType: .thing,
            targetID: UUID(),
            relation: .primaryThing,
            createdBy: .system,
            sourceMessageID: message.id
        )
        context.insert(message)
        context.insert(thing)
        context.insert(event)
        context.insert(badLink)
        try context.save()

        let result = try QAGraphInspectionService(modelContext: context, now: fixedTestNow).inspect()

        XCTAssertTrue(result.integrity.failures.contains { $0.code == "entity_link_missing_target" })
        XCTAssertTrue(result.orphanedLinks.contains { $0.recordID == badLink.id })
        XCTAssertTrue(result.provenanceRows.contains { $0.recordID == event.id && $0.sourceMessageID == message.id })
        XCTAssertTrue(result.affectedSourceRecords.contains { $0.id == message.id })
    }

    func testExtractionQualityDashboardAggregatesProxyMetricsFromLocalRecords() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today.",
            createdAt: now,
            extractionStatus: .succeeded,
            extractionAttemptCount: 1
        )
        let retryMessage = ChatMessage(
            role: .user,
            text: "Remind me about Bogey in a week or two.",
            createdAt: now,
            extractionStatus: .pendingRetry,
            extractionError: "Temporal phrase needs review.",
            extractionAttemptCount: 2
        )
        let thing = Thing(name: "Car", sourceMessageIDs: [message.id], eventCount: 1, lastEventAt: now)
        let event = LedgerEvent(title: "Changed oil", occurredAt: now, rawText: "Changed oil today.", thing: thing, sourceMessage: message)
        let deterministicAttempt = ExtractionAttempt(
            status: .succeeded,
            modelName: "deterministic-extractor",
            requestJSON: #"{"mode":"deterministic"}"#,
            startedAt: now,
            completedAt: now.addingTimeInterval(1),
            createdEventIDs: [event.id],
            createdThingIDs: [thing.id],
            sourceMessage: message
        )
        let failedAttempt = ExtractionAttempt(
            status: .failed,
            modelName: "gpt-5.5",
            errorCode: .schemaValidationFailed,
            errorMessage: "ambiguous_date",
            startedAt: now,
            completedAt: now.addingTimeInterval(3),
            sourceMessage: retryMessage
        )
        let pendingAttempt = ExtractionAttempt(
            status: .pending,
            modelName: "gpt-5.5",
            startedAt: now.addingTimeInterval(10),
            sourceMessage: retryMessage
        )
        let extractedLink = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .event,
            targetID: event.id,
            relation: .extractedFrom,
            confidence: 0.9,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
        let primaryLink = EntityLink(
            sourceType: .event,
            sourceID: event.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .primaryThing,
            confidence: 0.4,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
        let duplicateReview = reviewItem(kind: .duplicateThing, state: .ready, title: "Potential duplicate", detail: "Two Things share a normalized key.")
        let normalizationReview = reviewItem(kind: .normalizationCandidate, state: .accepted, title: "Possible match", detail: "Review reassignment.")
        let temporalReview = reviewItem(kind: .conflictingDate, state: .failed, title: "Conflicting date", detail: "Date conflict needs review.")
        temporalReview.failureReason = "Target event could not be updated."
        let ambiguousReview = reviewItem(kind: .extractionReview, state: .candidate, title: "Review temporal reminder", detail: "In a week or two is ambiguous.")

        context.insert(message)
        context.insert(retryMessage)
        context.insert(thing)
        context.insert(event)
        context.insert(deterministicAttempt)
        context.insert(failedAttempt)
        context.insert(pendingAttempt)
        context.insert(extractedLink)
        context.insert(primaryLink)
        context.insert(duplicateReview)
        context.insert(normalizationReview)
        context.insert(temporalReview)
        context.insert(ambiguousReview)
        try context.save()

        let snapshot = try QAExtractionQualityMetricsService(modelContext: context, now: now).snapshot()

        XCTAssertEqual(snapshot.extraction.candidateMessageCount, 2)
        XCTAssertEqual(snapshot.extraction.attemptedMessageCount, 2)
        XCTAssertEqual(snapshot.extraction.deterministicAttemptCount, 1)
        XCTAssertEqual(snapshot.extraction.aiAttemptCount, 2)
        XCTAssertEqual(snapshot.extraction.persistedEntityCandidateVolume, 2)
        XCTAssertEqual(snapshot.extraction.attemptCoverage, QARateMetric(numerator: 2, denominator: 2))
        XCTAssertEqual(snapshot.extraction.strictMessageSuccessRate, QARateMetric(numerator: 1, denominator: 2))
        XCTAssertEqual(snapshot.extraction.retryRate, QARateMetric(numerator: 1, denominator: 2))
        XCTAssertEqual(snapshot.extraction.retryMissingScheduleCount, 1)
        XCTAssertEqual(snapshot.extraction.latency.sampleCount, 2)
        XCTAssertEqual(snapshot.reviews.duplicateThingReviewCount, 1)
        XCTAssertEqual(snapshot.reviews.normalizationCandidateReviewCount, 1)
        XCTAssertEqual(snapshot.reviews.temporalReviewCount, 2)
        XCTAssertEqual(snapshot.reviews.failedReviewActionCount, 1)
        XCTAssertEqual(snapshot.reviews.failedTemporalInterpretationSignals, 4)
        XCTAssertEqual(snapshot.entityLinks.extractionCreatedLinkCount, 2)
        XCTAssertEqual(snapshot.entityLinks.extractionCreatedLinkCoverage, QARateMetric(numerator: 2, denominator: 2))
        XCTAssertEqual(snapshot.entityLinks.lowConfidenceLinkRate, QARateMetric(numerator: 1, denominator: 2))
    }

    func testExtractionQualityDashboardReadsDeterministicSeedFixtureData() throws {
        let context = makeInMemoryModelContext()
        let loader = QAFixtureLoader(modelContext: context)
        let descriptor = try XCTUnwrap(loader.descriptors().first { $0.id == "car_maintenance" })

        _ = try loader.load(descriptor, options: QAFixtureLoadOptions())
        let snapshot = try QAExtractionQualityMetricsService(modelContext: context, now: fixedTestNow).snapshot()

        XCTAssertEqual(snapshot.extraction.candidateMessageCount, 1)
        XCTAssertEqual(snapshot.extraction.deterministicAttemptCount, 1)
        XCTAssertEqual(snapshot.extraction.strictAttemptSuccessRate, QARateMetric(numerator: 1, denominator: 1))
        XCTAssertEqual(snapshot.reviews.totalReviewItems, 0)
        XCTAssertGreaterThan(snapshot.entityLinks.linkCount, 0)
    }

    func testTimelineJumpServiceBuildsReplayDescriptorsFromEffectiveDate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let options = QATimelineJumpService(calendar: Calendar(identifier: .gregorian), now: now).options()

        XCTAssertEqual(options.map(\.title), ["Current Month", "Previous Month", "Upcoming"])
        XCTAssertEqual(options.last?.descriptor.title, "Upcoming")
    }

    private func reviewItem(
        kind: LedgerReviewItemKind,
        state: LedgerReviewItemState,
        title: String,
        detail: String
    ) -> LedgerReviewItem {
        let item = LedgerReviewItem(
            dedupeKey: "\(kind.rawValue)-\(UUID().uuidString)",
            kind: kind,
            title: title,
            detail: detail,
            targetType: .none,
            targetID: nil,
            evidence: [],
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow
        )
        switch state {
        case .candidate:
            break
        case .ready:
            item.markReady(at: fixedTestNow)
        case .presented:
            item.markPresented(at: fixedTestNow)
        case .accepted:
            item.accept(at: fixedTestNow)
        case .dismissed:
            item.dismiss(at: fixedTestNow)
        case .snoozed:
            item.snooze(until: fixedTestNow.addingTimeInterval(3_600), at: fixedTestNow)
        case .superseded:
            item.supersede(at: fixedTestNow)
        case .expired:
            item.expire(at: fixedTestNow)
        case .failed:
            item.fail(reason: "Action failed.", at: fixedTestNow)
        }
        return item
    }

    private func storeCounts(_ context: ModelContext) throws -> QARecordCounts {
        QARecordCounts(
            sourceMessages: try context.fetch(FetchDescriptor<ChatMessage>()).count,
            things: try context.fetch(FetchDescriptor<Thing>()).count,
            events: try context.fetch(FetchDescriptor<LedgerEvent>()).count,
            reminders: try context.fetch(FetchDescriptor<LedgerRule>()).count,
            notes: try context.fetch(FetchDescriptor<LedgerNote>()).count,
            extractionAttempts: try context.fetch(FetchDescriptor<ExtractionAttempt>()).count,
            reviewItems: try context.fetch(FetchDescriptor<LedgerReviewItem>()).count,
            entityLinks: try context.fetch(FetchDescriptor<EntityLink>()).count
        )
    }
}
