import SwiftData
import XCTest
@testable import LifeOrganize

final class AbendHardeningTests: XCTestCase {
    func testLocalDiagnosticEventStoreRedactsSensitiveMetadataAndBoundsEvents() throws {
        let defaults = try makeIsolatedDefaults()
        let store = LocalDiagnosticEventStore(defaults: defaults, now: { fixedTestNow }, maxEvents: 2)

        store.record(
            severity: .error,
            category: "settings",
            operation: "prepare_service_token",
            errorKind: "FirstError",
            metadata: ["deviceToken": "raw-token", "requestJSON": #"{"text":"private"}"#, "safe": "visible"]
        )
        store.record(
            severity: .warning,
            category: "review_queue",
            operation: "load_entries",
            errorKind: "SecondError"
        )
        store.record(
            severity: .warning,
            category: "extraction",
            operation: "retry",
            errorKind: "ThirdError"
        )

        let events = store.load()
        XCTAssertEqual(events.map(\.errorKind), ["SecondError", "ThirdError"])
        store.clear()

        store.record(
            severity: .error,
            category: "settings",
            operation: "prepare_service_token",
            errorKind: "SensitiveError",
            metadata: ["deviceToken": "raw-token", "requestJSON": #"{"text":"private"}"#, "safe": "visible"]
        )

        let event = try XCTUnwrap(store.load().first)
        XCTAssertEqual(event.metadata["deviceToken"], "[redacted]")
        XCTAssertEqual(event.metadata["requestJSON"], "[redacted]")
        XCTAssertEqual(event.metadata["safe"], "visible")
    }

    @MainActor
    func testLocalDataIntegrityValidatorReportsCorruptPersistedJSON() throws {
        let context = makeInMemoryModelContext()
        let event = LedgerEvent(title: "Oil change", occurredAt: fixedTestNow, rawText: "Oil change.")
        event.metadataJSONText = "{"
        let reviewItem = LedgerReviewItem(
            dedupeKey: "corrupt-review",
            kind: .normalizationCandidate,
            title: "Review",
            detail: "Needs review",
            targetType: .event,
            targetID: event.id,
            evidence: []
        )
        reviewItem.evidenceJSONText = "{"
        let attempt = ExtractionAttempt(
            normalizedJSONText: "{",
            startedAt: fixedTestNow
        )
        context.insert(event)
        context.insert(reviewItem)
        context.insert(attempt)
        try context.save()

        let findings = try LocalDataIntegrityValidator(modelContext: context).validate()

        XCTAssertEqual(Set(findings.map(\.field)), [
            "metadataJSONText",
            "evidenceJSONText",
            "normalizedJSONText"
        ])
        XCTAssertTrue(findings.allSatisfy { $0.severity == .error })
    }

    @MainActor
    func testLaunchMaintenanceServiceContinuesIndependentRepairsAndRecordsFailures() throws {
        enum TestError: Error { case failed }
        let defaults = try makeIsolatedDefaults()
        let diagnostics = LocalDiagnosticEventStore(defaults: defaults, now: { fixedTestNow })
        var ranDerivedFields = false
        var ranReviewRefresh = false
        let service = LaunchMaintenanceService(
            diagnostics: diagnostics,
            repairInterruptedEntries: {
                throw TestError.failed
            },
            repairDerivedFields: {
                ranDerivedFields = true
            },
            refreshReviewItems: {
                ranReviewRefresh = true
            }
        )

        let failures = service.repair()

        XCTAssertEqual(failures.map(\.operation), [.extractionRecovery])
        XCTAssertTrue(ranDerivedFields)
        XCTAssertTrue(ranReviewRefresh)
        let event = try XCTUnwrap(diagnostics.load().first)
        XCTAssertEqual(event.category, "launch_maintenance")
        XCTAssertEqual(event.operation, LaunchMaintenanceOperation.extractionRecovery.rawValue)
    }

    func testReviewQueueLoadStateReturnsFailureInsteadOfEmptySuccess() {
        enum TestError: Error { case failed }

        let state = LedgerReviewQueueLoadState.load {
            throw TestError.failed
        }

        XCTAssertEqual(state.entries, [])
        XCTAssertEqual(
            state.errorMessage,
            "Review could not load. Reopen Review or try again after restarting the app."
        )
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "LifeOrganizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
