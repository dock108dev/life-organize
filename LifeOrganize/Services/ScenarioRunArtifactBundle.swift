import Foundation
import SwiftData

enum ScenarioRunStatus: String, Codable {
    case passed
    case failed
    case errored
    case skipped
    case timedOut = "timed_out"
}

enum ScenarioKind: String, Codable {
    case unit
    case ui
}

struct ScenarioRunGitInfo: Codable, Equatable {
    let branch: String
    let commit: String
    let dirty: Bool
}

struct ScenarioRunXcodeInfo: Codable, Equatable {
    let scheme: String
    let destination: String
    let resultBundlePath: String
}

struct ScenarioRunDeterminism: Codable, Equatable {
    let uiTesting: Bool
    let fakeExtractor: Bool
    let fixedNow: String?
    let resetStoreForScenarios: Bool
    let networkRequired: Bool
}

struct ScenarioRunArtifacts: Codable, Equatable {
    let xctestResultBundle: String
    let junit: String?
    let testSummary: String?
}

struct ScenarioRunCounts: Codable, Equatable {
    let scenarios: Int
    let passed: Int
    let failed: Int
    let relationshipAuditFailures: Int
    let missingRequiredArtifacts: Int
    let invalidJSONArtifacts: Int
}

struct ScenarioRunSummary: Codable, Equatable {
    let schemaVersion: Int
    let runId: String
    let createdAt: String
    let git: ScenarioRunGitInfo
    let xcode: ScenarioRunXcodeInfo
    let determinism: ScenarioRunDeterminism
    let status: ScenarioRunStatus
    let startedAt: String
    let finishedAt: String
    let durationSeconds: Int
    let counts: ScenarioRunCounts
    let artifacts: ScenarioRunArtifacts
    let scenarios: [ScenarioRunScenarioSummary]
}

struct ScenarioRunScenarioSummary: Codable, Equatable {
    let id: String
    let name: String
    let testIdentifier: String
    let status: ScenarioRunStatus
    let kind: ScenarioKind
    let durationSeconds: Int?
    let artifacts: ScenarioManifestArtifacts
}

struct ScenarioManifestSource: Codable, Equatable {
    let file: String
    let testClass: String
    let testMethod: String
}

struct ScenarioManifestDeterminism: Codable, Equatable {
    let fixedNow: String?
    let launchArguments: [String]
}

struct ScenarioSignal: Codable, Equatable {
    let kind: String
    let value: String
}

struct ScenarioManifestArtifacts: Codable, Equatable {
    let scenario: String?
    let ledgerExport: String?
    let relationshipAudit: String?
    let relationshipAuditMarkdown: String?
    let screenshotsDirectory: String?
    let screenshots: [String]
}

struct ScenarioManifest: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let name: String
    let kind: ScenarioKind
    let source: ScenarioManifestSource
    let determinism: ScenarioManifestDeterminism
    let inputs: [ScenarioSignal]
    let expectedSignals: [ScenarioSignal]
    let status: ScenarioRunStatus
    let artifacts: ScenarioManifestArtifacts
    let semanticChecks: [ScenarioSemanticCheck]
    let artifactFailures: [String]
}

struct ScenarioArtifactDefinition: Equatable {
    let id: String
    let name: String
    let kind: ScenarioKind
    let source: ScenarioManifestSource
    let determinism: ScenarioManifestDeterminism
    let inputs: [ScenarioSignal]
    let expectedSignals: [ScenarioSignal]
    let semanticChecks: [ScenarioSemanticCheck]
    let expectedScreenshots: [String]
    let sourceTestIdentifier: String
    var status: ScenarioRunStatus = .passed
    var durationSeconds: Int?
}

struct ScenarioRunArtifactRequest {
    let runId: String
    let rootDirectory: URL
    let createdAt: Date
    let startedAt: Date
    let finishedAt: Date
    let git: ScenarioRunGitInfo
    let xcode: ScenarioRunXcodeInfo
    let determinism: ScenarioRunDeterminism
    let scenarios: [ScenarioArtifactDefinition]
    let requiresXCTestResultBundle: Bool
}

struct ScenarioRunArtifactResult {
    let runDirectory: URL
    let summary: ScenarioRunSummary
}

@MainActor
struct ScenarioRunArtifactBundleWriter {
    var fileManager: FileManager = .default
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current
    var auditService = RelationshipAuditService()

    func writeRun(
        _ request: ScenarioRunArtifactRequest,
        exportService: (ScenarioArtifactDefinition) throws -> LocalJSONExportService
    ) throws -> ScenarioRunArtifactResult {
        let runURL = request.rootDirectory.appendingPathComponent(request.runId, isDirectory: true)
        try fileManager.createDirectory(at: runURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runURL.appendingPathComponent("xctest", isDirectory: true), withIntermediateDirectories: true)

        var scenarioSummaries: [ScenarioRunScenarioSummary] = []
        var failedScenarios = 0
        var relationshipAuditFailures = 0
        var missingArtifacts = missingXCTestArtifacts(request, runURL: runURL)
        var invalidJSONArtifacts = 0

        for scenario in request.scenarios {
            let result = try writeScenario(scenario, runURL: runURL) {
                try exportService(scenario)
            }
            scenarioSummaries.append(result.summary)
            failedScenarios += result.summary.status == .passed ? 0 : 1
            relationshipAuditFailures += result.relationshipAuditFailures
            missingArtifacts += result.missingArtifacts
            invalidJSONArtifacts += result.invalidJSONArtifacts
        }

        let passedScenarios = scenarioSummaries.filter { $0.status == .passed }.count
        let runPassed = failedScenarios == 0
            && relationshipAuditFailures == 0
            && missingArtifacts == 0
            && invalidJSONArtifacts == 0
        let runStatus: ScenarioRunStatus = runPassed ? .passed : .failed
        let summary = ScenarioRunSummary(
            schemaVersion: 1,
            runId: request.runId,
            createdAt: timestamp(request.createdAt),
            git: request.git,
            xcode: request.xcode,
            determinism: request.determinism,
            status: runStatus,
            startedAt: timestamp(request.startedAt),
            finishedAt: timestamp(request.finishedAt),
            durationSeconds: max(0, Int(request.finishedAt.timeIntervalSince(request.startedAt))),
            counts: ScenarioRunCounts(
                scenarios: scenarioSummaries.count,
                passed: passedScenarios,
                failed: failedScenarios,
                relationshipAuditFailures: relationshipAuditFailures,
                missingRequiredArtifacts: missingArtifacts,
                invalidJSONArtifacts: invalidJSONArtifacts
            ),
            artifacts: ScenarioRunArtifacts(
                xctestResultBundle: request.xcode.resultBundlePath,
                junit: "xctest/junit.xml",
                testSummary: "xctest/test-summary.json"
            ),
            scenarios: scenarioSummaries
        )
        try writeJSON(summary, to: runURL.appendingPathComponent("scenario-run-summary.json"))
        return ScenarioRunArtifactResult(runDirectory: runURL, summary: summary)
    }

    private func writeScenario(
        _ definition: ScenarioArtifactDefinition,
        runURL: URL,
        exportService: () throws -> LocalJSONExportService
    ) throws -> (summary: ScenarioRunScenarioSummary, relationshipAuditFailures: Int, missingArtifacts: Int, invalidJSONArtifacts: Int) {
        let scenarioURL = runURL.appendingPathComponent("scenarios", isDirectory: true)
            .appendingPathComponent(definition.id, isDirectory: true)
        let screenshotsURL = scenarioURL.appendingPathComponent("screenshots", isDirectory: true)
        try fileManager.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)

        var artifactFailures: [String] = []
        var relationshipFailures = 0
        var invalidJSON = 0
        var screenshotPaths: [String] = []

        do {
            let service = try exportService()
            let envelope = try service.envelope()
            let exportData = try encoded(envelope)
            let exportURL = scenarioURL.appendingPathComponent("ledger-export.json")
            try exportData.write(to: exportURL, options: [.atomic])
            let validationFailures = ScenarioLedgerExportValidator().validate(data: exportData)
            artifactFailures.append(contentsOf: validationFailures)
            invalidJSON += validationFailures.isEmpty ? 0 : 1

            let audit = auditService.audit(envelope, scenarioId: definition.id, semanticChecks: definition.semanticChecks)
            relationshipFailures += audit.summary.failures
            try writeJSON(audit, to: scenarioURL.appendingPathComponent("relationship-audit.json"))
            try auditService.markdown(for: audit).write(to: scenarioURL.appendingPathComponent("relationship-audit.md"), atomically: true, encoding: .utf8)
        } catch {
            artifactFailures.append("ledger-export.json could not be emitted: \(error.localizedDescription)")
        }

        for screenshot in definition.expectedScreenshots {
            let relativePath = "screenshots/\(screenshot)"
            let url = scenarioURL.appendingPathComponent(relativePath)
            screenshotPaths.append(relativePath)
            if !fileManager.fileExists(atPath: url.path) {
                artifactFailures.append("Missing expected screenshot \(relativePath).")
            }
        }

        let scenarioPassed = definition.status == .passed
            && artifactFailures.isEmpty
            && relationshipFailures == 0
        let status: ScenarioRunStatus = scenarioPassed ? .passed : .failed
        let artifacts = ScenarioManifestArtifacts(
            scenario: nil,
            ledgerExport: "ledger-export.json",
            relationshipAudit: "relationship-audit.json",
            relationshipAuditMarkdown: "relationship-audit.md",
            screenshotsDirectory: definition.expectedScreenshots.isEmpty ? nil : "screenshots",
            screenshots: screenshotPaths
        )
        let manifest = ScenarioManifest(
            schemaVersion: 1,
            id: definition.id,
            name: definition.name,
            kind: definition.kind,
            source: definition.source,
            determinism: definition.determinism,
            inputs: definition.inputs,
            expectedSignals: definition.expectedSignals,
            status: status,
            artifacts: artifacts,
            semanticChecks: definition.semanticChecks,
            artifactFailures: artifactFailures
        )
        try writeJSON(manifest, to: scenarioURL.appendingPathComponent("scenario.json"))
        return (
            ScenarioRunScenarioSummary(
                id: definition.id,
                name: definition.name,
                testIdentifier: definition.sourceTestIdentifier,
                status: status,
                kind: definition.kind,
                durationSeconds: definition.durationSeconds,
                artifacts: ScenarioManifestArtifacts(
                    scenario: "scenarios/\(definition.id)/scenario.json",
                    ledgerExport: "scenarios/\(definition.id)/ledger-export.json",
                    relationshipAudit: "scenarios/\(definition.id)/relationship-audit.json",
                    relationshipAuditMarkdown: "scenarios/\(definition.id)/relationship-audit.md",
                    screenshotsDirectory: definition.expectedScreenshots.isEmpty ? nil : "scenarios/\(definition.id)/screenshots",
                    screenshots: screenshotPaths.map { "scenarios/\(definition.id)/\($0)" }
                )
            ),
            relationshipFailures,
            artifactFailures.filter { $0.hasPrefix("Missing expected") || $0.contains("could not be emitted") }.count,
            invalidJSON
        )
    }

    private func missingXCTestArtifacts(_ request: ScenarioRunArtifactRequest, runURL: URL) -> Int {
        guard request.requiresXCTestResultBundle else { return 0 }
        let resultURL = runURL.appendingPathComponent(request.xcode.resultBundlePath)
        return fileManager.fileExists(atPath: resultURL.path) ? 0 : 1
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try encoded(value).write(to: url, options: [.atomic])
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func timestamp(_ date: Date) -> String {
        DateFormatting.isoDateTimeString(date, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}

struct ScenarioLedgerExportValidator {
    func validate(data: Data) -> [String] {
        var failures: [String] = []
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ["ledger-export.json root is not an object."]
            }
            for key in ["schemaVersion", "exportedAt", "exportedFrom", "locale", "records"] where root[key] == nil {
                failures.append("ledger-export.json is missing \(key).")
            }
            guard let records = root["records"] as? [String: Any] else {
                failures.append("ledger-export.json records is not an object.")
                return failures
            }
            for key in ["chatMessages", "extractionRuns", "things", "events", "rules", "notes", "ledgerReviewItems", "entityLinks"] where records[key] == nil {
                failures.append("ledger-export.json records is missing \(key).")
            }
            _ = try JSONDecoder().decode(LedgerExportEnvelope.self, from: data)
        } catch {
            failures.append("ledger-export.json could not be parsed: \(error.localizedDescription)")
        }
        return failures
    }
}
