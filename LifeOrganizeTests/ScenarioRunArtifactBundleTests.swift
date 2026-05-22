import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class ScenarioRunArtifactBundleTests: XCTestCase {
    func testScenarioRunBundleWritesPlannerReadableArtifacts() throws {
        let root = temporaryDirectory()
        let runID = "20260521-120000-local-iphone-16"
        let xctestURL = root
            .appendingPathComponent(runID, isDirectory: true)
            .appendingPathComponent("xctest", isDirectory: true)
            .appendingPathComponent("LifeOrganize.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: xctestURL, withIntermediateDirectories: true)
        let screenshotURL = root
            .appendingPathComponent(runID, isDirectory: true)
            .appendingPathComponent("scenarios/ui-launch-tabs-persistence/screenshots", isDirectory: true)
            .appendingPathComponent("timeline.after-oil-entry.png")
        try FileManager.default.createDirectory(at: screenshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshotURL)

        let context = try makeScenarioContext()
        let request = try makeRequest(root: root, runID: runID, expectedScreenshots: ["timeline.after-oil-entry.png"])

        let result = try ScenarioRunArtifactBundleWriter().writeRun(request) { _ in
            try makeExportService(context: context)
        }

        XCTAssertEqual(result.summary.status, .passed)
        XCTAssertEqual(result.summary.counts.scenarios, 1)
        XCTAssertEqual(result.summary.counts.relationshipAuditFailures, 0)
        XCTAssertEqual(result.summary.scenarios.first?.artifacts.ledgerExport, "scenarios/ui-launch-tabs-persistence/ledger-export.json")
        XCTAssertEqual(
            result.summary.scenarios.first?.artifacts.screenshots,
            ["scenarios/ui-launch-tabs-persistence/screenshots/timeline.after-oil-entry.png"]
        )

        let scenarioURL = result.runDirectory.appendingPathComponent("scenarios/ui-launch-tabs-persistence", isDirectory: true)
        let manifest = try decode(ScenarioManifest.self, from: scenarioURL.appendingPathComponent("scenario.json"))
        let audit = try decode(RelationshipAuditReport.self, from: scenarioURL.appendingPathComponent("relationship-audit.json"))
        let export = try decode(LedgerExportEnvelope.self, from: scenarioURL.appendingPathComponent("ledger-export.json"))
        let summary = try decode(ScenarioRunSummary.self, from: result.runDirectory.appendingPathComponent("scenario-run-summary.json"))

        XCTAssertEqual(manifest.status, .passed)
        XCTAssertTrue(manifest.artifactFailures.isEmpty)
        XCTAssertEqual(audit.status, "passed")
        XCTAssertEqual(audit.summary.failures, 0)
        XCTAssertEqual(export.records.things.first?.name, "Oil Change")
        XCTAssertEqual(summary.status, .passed)
        XCTAssertTrue(try String(contentsOf: scenarioURL.appendingPathComponent("relationship-audit.md")).contains("Status: passed"))
    }

    func testScenarioRunBundleReportsMissingScreenshotsAsArtifactFailures() throws {
        let root = temporaryDirectory()
        let runID = "20260521-121500-local-iphone-16"
        let context = try makeScenarioContext()
        let request = try makeRequest(root: root, runID: runID, expectedScreenshots: ["missing.png"], requiresXCTest: false)

        let result = try ScenarioRunArtifactBundleWriter().writeRun(request) { _ in
            try makeExportService(context: context)
        }
        let scenarioURL = result.runDirectory.appendingPathComponent("scenarios/ui-launch-tabs-persistence", isDirectory: true)
        let manifest = try decode(ScenarioManifest.self, from: scenarioURL.appendingPathComponent("scenario.json"))

        XCTAssertEqual(result.summary.status, .failed)
        XCTAssertEqual(result.summary.counts.missingRequiredArtifacts, 1)
        XCTAssertEqual(manifest.status, .failed)
        XCTAssertEqual(manifest.artifactFailures, ["Missing expected screenshot screenshots/missing.png."])
    }

    func testScenarioRunBundleIncludesReviewQueueStateAndScreenshotCheckpoint() throws {
        let root = temporaryDirectory()
        let runID = "20260521-123000-local-iphone-16"
        let screenshotURL = root
            .appendingPathComponent(runID, isDirectory: true)
            .appendingPathComponent("scenarios/ui-launch-tabs-persistence/screenshots", isDirectory: true)
            .appendingPathComponent("review-queue.after-generation.png")
        try FileManager.default.createDirectory(at: screenshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshotURL)
        let context = try makeScenarioContext(includeReviewItem: true)
        let request = try makeRequest(
            root: root,
            runID: runID,
            expectedScreenshots: ["review-queue.after-generation.png"],
            requiresXCTest: false
        )

        let result = try ScenarioRunArtifactBundleWriter().writeRun(request) { _ in
            try makeExportService(context: context)
        }

        let scenarioURL = result.runDirectory.appendingPathComponent("scenarios/ui-launch-tabs-persistence", isDirectory: true)
        let manifest = try decode(ScenarioManifest.self, from: scenarioURL.appendingPathComponent("scenario.json"))
        let export = try decode(LedgerExportEnvelope.self, from: scenarioURL.appendingPathComponent("ledger-export.json"))

        XCTAssertEqual(result.summary.status, .passed)
        XCTAssertEqual(
            result.summary.scenarios.first?.artifacts.screenshots,
            ["scenarios/ui-launch-tabs-persistence/screenshots/review-queue.after-generation.png"]
        )
        XCTAssertEqual(manifest.artifacts.screenshots, ["screenshots/review-queue.after-generation.png"])
        XCTAssertEqual(export.records.ledgerReviewItems.count, 1)
        XCTAssertEqual(export.records.ledgerReviewItems.first?.kind, LedgerReviewItemKind.extractionReview.rawValue)
        XCTAssertEqual(export.records.ledgerReviewItems.first?.title, "Entry needs review")
        XCTAssertEqual(export.records.ledgerReviewItems.first?.state, LedgerReviewItemState.candidate.rawValue)
    }

    func testRelationshipAuditReportsExportReferenceFailures() {
        let envelope = LedgerExportEnvelope(
            schemaVersion: 3,
            exportedAt: "2026-05-21T12:00:00Z",
            exportedFrom: ExportedFrom(appName: "LifeOrganize", appBuild: "1", platform: "iOS Simulator"),
            locale: ExportLocale(calendar: "gregorian", timeZone: "America/New_York"),
            records: ExportRecords(
                chatMessages: [],
                extractionRuns: [],
                things: [],
                events: [
                    EventExport(
                        id: "event-a",
                        thingId: "missing-thing",
                        title: "Oil change",
                        eventType: "maintenance",
                        rawText: "Changed oil.",
                        occurredAt: "2026-05-21",
                        createdAt: "2026-05-21T12:00:00Z",
                        updatedAt: "2026-05-21T12:00:00Z",
                        note: nil,
                        metadata: [],
                        source: ExportSource(kind: "manual")
                    ),
                ],
                rules: [],
                notes: [],
                ledgerReviewItems: [],
                entityLinks: []
            )
        )

        let report = RelationshipAuditService().audit(envelope, scenarioId: "unit-continuity-car")

        XCTAssertEqual(report.status, "failed")
        XCTAssertTrue(report.findings.contains { $0.checkId == "event-thing-references-exist" })
    }

    func testLedgerExportValidatorRequiresAllRecordCollections() throws {
        let data = Data(
            #"{"schemaVersion":3,"exportedAt":"2026-05-21T12:00:00Z","exportedFrom":{"appName":"LifeOrganize","appBuild":"1","platform":"iOS Simulator"},"locale":{"calendar":"gregorian","timeZone":"America/New_York"},"records":{"chatMessages":[]}}"#.utf8
        )

        let failures = ScenarioLedgerExportValidator().validate(data: data)

        XCTAssertTrue(failures.contains("ledger-export.json records is missing entityLinks."))
        XCTAssertFalse(failures.isEmpty)
    }

    private func makeScenarioContext(includeReviewItem: Bool = false) throws -> ModelContext {
        let context = makeInMemoryModelContext()
        let now = try date("2026-05-21T12:00:00Z")
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today.",
            createdAt: now,
            extractionStatus: .needsReview
        )
        let thing = Thing(
            name: "Oil Change",
            category: .maintenance,
            createdAt: now,
            updatedAt: now,
            eventCount: 1,
            lastEventAt: now
        )
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: now,
            rawText: "Changed oil today.",
            createdAt: now,
            updatedAt: now,
            eventType: .maintenance,
            thing: thing
        )
        let link = EntityLink(
            sourceType: .event,
            sourceID: event.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .primaryThing,
            createdAt: now,
            createdBy: .system
        )
        context.insert(message)
        context.insert(thing)
        context.insert(event)
        context.insert(link)
        if includeReviewItem {
            context.insert(
                LedgerReviewItem(
                    dedupeKey: "extraction_review|\(message.id.uuidString)|needs_review",
                    kind: .extractionReview,
                    title: "Entry needs review",
                    detail: "The original entry is saved locally. Retry this entry or review details.",
                    actionTitle: "Retry Now",
                    targetType: .chatMessage,
                    targetID: message.id,
                    confidence: 1,
                    evidence: [
                        LedgerReviewItemEvidence(sourceType: .chatMessage, sourceID: message.id, summary: message.text, detail: nil),
                    ],
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        try context.save()
        return context
    }

    private func makeRequest(
        root: URL,
        runID: String,
        expectedScreenshots: [String],
        requiresXCTest: Bool = true
    ) throws -> ScenarioRunArtifactRequest {
        let now = try date("2026-05-21T12:00:00Z")
        return ScenarioRunArtifactRequest(
            runId: runID,
            rootDirectory: root,
            createdAt: now,
            startedAt: now,
            finishedAt: now.addingTimeInterval(12),
            git: ScenarioRunGitInfo(branch: "main", commit: "abcdef123456", dirty: false),
            xcode: ScenarioRunXcodeInfo(
                scheme: "LifeOrganize",
                destination: "platform=iOS Simulator,name=iPhone 16,OS=18.6",
                resultBundlePath: "xctest/LifeOrganize.xcresult"
            ),
            determinism: ScenarioRunDeterminism(
                uiTesting: true,
                fakeExtractor: true,
                fixedNow: "2027-01-15T08:00:00-05:00",
                resetStoreForScenarios: true,
                networkRequired: false
            ),
            scenarios: [
                ScenarioArtifactDefinition(
                    id: "ui-launch-tabs-persistence",
                    name: "Launch tabs, fake extraction, and persistence across relaunch",
                    kind: .ui,
                    source: ScenarioManifestSource(
                        file: "LifeOrganizeUITests/LifeOrganizeUITests.swift",
                        testClass: "LifeOrganizeUITests",
                        testMethod: "testLaunchTabsFakeExtractionAndPersistenceAcrossRelaunch"
                    ),
                    determinism: ScenarioManifestDeterminism(
                        fixedNow: "2027-01-15T08:00:00-05:00",
                        launchArguments: ["-ui-testing", "-use-fake-extractor"]
                    ),
                    inputs: [ScenarioSignal(kind: "chatMessage", value: "Changed oil today.")],
                    expectedSignals: [ScenarioSignal(kind: "uiText", value: "Oil Change")],
                    semanticChecks: [
                        ScenarioSemanticCheck(
                            id: "oil-change-thing-exists",
                            recordType: "thing",
                            match: ScenarioSemanticMatch(nameContains: "Oil"),
                            minCount: 1
                        ),
                        ScenarioSemanticCheck(
                            id: "oil-change-event-exists",
                            recordType: "event",
                            match: ScenarioSemanticMatch(titleContains: "Oil"),
                            minCount: 1
                        ),
                    ],
                    expectedScreenshots: expectedScreenshots,
                    sourceTestIdentifier: "LifeOrganizeUITests/testLaunchTabsFakeExtractionAndPersistenceAcrossRelaunch",
                    durationSeconds: 12
                ),
            ],
            requiresXCTestResultBundle: requiresXCTest
        )
    }

    private func makeExportService(context: ModelContext) throws -> LocalJSONExportService {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return LocalJSONExportService(
            modelContext: context,
            now: { fixedTestNow },
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeOrganizeScenarioArtifacts-\(UUID().uuidString)", isDirectory: true)
    }

    private func date(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }
}
