import Foundation
import SwiftData

enum SeedScenarioLoader {
    static func load(
        _ scenarioIDs: [String],
        into container: ModelContainer,
        now _: Date? = nil,
        isAutomationRuntime: Bool
    ) throws {
        guard !scenarioIDs.isEmpty else { return }
        guard isAutomationRuntime else { return }

        let scenarios = try scenarioIDs.map { id in
            guard let scenario = SeedScenario(argumentValue: id) else {
                throw SeedScenarioLoaderError.unknownScenario(id)
            }
            return scenario
        }
        let fixtures = try scenarios.map { try loadFixture(for: $0) }
        try load(fixtures, into: container)
    }

    static func loadFixtureData(_ data: Data, into container: ModelContainer, fileName: String = "inline fixture") throws {
        let fixture = try decodeFixture(data, fileName: fileName, expectedID: nil)
        try load([fixture], into: container)
    }

    static func loadFixture(_ fixture: SeedScenarioFixture, into context: ModelContext) throws {
        do {
            try SeedScenarioRecordBuilder(context: context, fixture: fixture).insertRecords()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func fixture(for scenario: SeedScenario) throws -> SeedScenarioFixture {
        try loadFixture(for: scenario)
    }

    private static func load(_ fixtures: [SeedScenarioFixture], into container: ModelContainer) throws {
        let context = ModelContext(container)
        do {
            for fixture in fixtures {
                try SeedScenarioRecordBuilder(context: context, fixture: fixture).insertRecords()
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func loadFixture(for scenario: SeedScenario) throws -> SeedScenarioFixture {
        let fixtureID = scenario.fixtureID
        if scenario == .heavyHistory {
            return HeavyHistorySeedScenarioGenerator.fixture()
        }
        guard let url = fixtureURL(for: fixtureID) else {
            throw SeedScenarioLoaderError.missingFixture(fixtureID)
        }
        let data = try Data(contentsOf: url)
        return try decodeFixture(data, fileName: url.lastPathComponent, expectedID: fixtureID)
    }

    private static func decodeFixture(
        _ data: Data,
        fileName: String,
        expectedID: String?
    ) throws -> SeedScenarioFixture {
        do {
            let fixture = try JSONDecoder().decode(SeedScenarioFixture.self, from: data)
            try SeedScenarioFixtureValidator().validate(fixture, expectedID: expectedID)
            return fixture
        } catch let error as SeedScenarioLoaderError {
            throw error
        } catch let error as DecodingError {
            throw SeedScenarioLoaderError.invalidFixture("\(fileName): \(error.readableDescription)")
        } catch {
            throw SeedScenarioLoaderError.invalidFixture("\(fileName): \(error.localizedDescription)")
        }
    }

    private static func fixtureURL(for id: String) -> URL? {
        if let bundleURL = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "SeedScenarios") {
            return bundleURL
        }
        if let resourceBundleURL = Bundle.main.url(
            forResource: id,
            withExtension: "json",
            subdirectory: "Resources/SeedScenarios"
        ) {
            return resourceBundleURL
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources")
            .appending(path: "SeedScenarios")
            .appending(path: "\(id).json")
        return FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil
    }
}

private extension DecodingError {
    var readableDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            "Missing required field \(key.stringValue) at \(context.codingPath.readablePath)."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            "\(context.debugDescription) at \(context.codingPath.readablePath)."
        @unknown default:
            localizedDescription
        }
    }
}

private extension [CodingKey] {
    var readablePath: String {
        guard !isEmpty else { return "<root>" }
        return map(\.stringValue).joined(separator: ".")
    }
}
