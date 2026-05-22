import Foundation
@testable import LifeOrganize

struct ScenarioFixture: Decodable {
    static let supportedFixtureSchemaVersion = 1
    static let supportedLedgerSchemaVersion = 3

    let fixtureSchemaVersion: Int
    let ledgerSchemaVersion: Int
    let id: String
    let title: String
    let description: String
    let clock: ScenarioFixtureClock
    let records: ExportRecords
    let expectations: ScenarioExpectations

    static func load(_ id: String) throws -> ScenarioFixture {
        if id == HeavyHistorySeedScenarioGenerator.fixtureID {
            return try decode(HeavyHistorySeedScenarioGenerator.jsonData(), fileName: "\(id).generated.json")
        }
        let url = try fixtureURL(for: id)
        let data = try Data(contentsOf: url)
        return try decode(data, fileName: url.lastPathComponent)
    }

    static func loadAllBundledScenarios() throws -> [ScenarioFixture] {
        try allBundledScenarioIDs().map(load)
    }

    static func allBundledScenarioIDs() throws -> [String] {
        let directory = fixturesDirectoryURL()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let fileIDs = urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Array(Set(fileIDs + [HeavyHistorySeedScenarioGenerator.fixtureID])).sorted()
    }

    static func decode(_ data: Data, fileName: String = "inline fixture") throws -> ScenarioFixture {
        do {
            let fixture = try JSONDecoder().decode(ScenarioFixture.self, from: data)
            try ScenarioFixtureValidator().validate(fixture)
            return fixture
        } catch let error as ScenarioFixtureError {
            throw error
        } catch let error as DecodingError {
            throw ScenarioFixtureError.invalidFixture("\(fileName): \(error.readableDescription)")
        } catch {
            throw ScenarioFixtureError.invalidFixture("\(fileName): \(error.localizedDescription)")
        }
    }

    private static func fixtureURL(for id: String) throws -> URL {
        let fileName = "\(id).json"
        if let bundleURL = Bundle(for: ScenarioFixtureBundleMarker.self).url(
            forResource: id,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) {
            return bundleURL
        }

        let sourceURL = fixturesDirectoryURL().appending(path: fileName)
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }
        throw ScenarioFixtureError.invalidFixture("Missing scenario fixture: \(fileName)")
    }

    private static func fixturesDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
    }
}

private final class ScenarioFixtureBundleMarker {}

struct ScenarioFixtureClock: Decodable {
    let now: String
    let calendar: String
    let timeZone: String
}

struct ScenarioExpectations: Decodable {
    let requiredCounts: ScenarioRequiredCounts?
    let requiredVisibleSurfaces: [ScenarioVisibleSurfaceExpectation]
    let relationshipChecks: [ScenarioRelationshipExpectation]
    let searchExpectations: [ScenarioSearchExpectation]
    let replayExpectations: [ScenarioReplayExpectation]
    let reviewQueueExpectations: [ScenarioReviewQueueExpectation]
}

struct ScenarioRequiredCounts: Decodable {
    let chatMessages: Int?
    let extractionRuns: Int?
    let things: Int?
    let events: Int?
    let rules: Int?
    let notes: Int?
    let ledgerReviewItems: Int?
    let entityLinks: Int?
}

struct ScenarioVisibleSurfaceExpectation: Decodable {
    let surface: String
    let requiredRecordIds: [String]
}

struct ScenarioRelationshipExpectation: Decodable {
    let kind: String
    let fromType: String
    let fromId: String
    let toType: String
    let toId: String
}

struct ScenarioSearchExpectation: Decodable {
    let query: String
    let expectedTargets: [ScenarioExpectedTarget]
    let disallowedText: [String]
}

struct ScenarioReplayExpectation: Decodable {
    let sourceType: String
    let sourceId: String
    let requiredText: [String]
    let expectedTargets: [ScenarioExpectedTarget]
}

struct ScenarioReviewQueueExpectation: Decodable {
    let kind: String
    let state: String
    let targetType: String
    let targetId: String?
    let requiredEvidenceIds: [String]
}

struct ScenarioExpectedTarget: Decodable {
    let type: String
    let id: String
}

enum ScenarioFixtureError: LocalizedError, Equatable {
    case invalidFixture(String)

    var errorDescription: String? {
        switch self {
        case .invalidFixture(let message):
            message
        }
    }
}
