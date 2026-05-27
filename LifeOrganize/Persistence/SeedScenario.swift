import Foundation

enum SeedScenario: CaseIterable, Identifiable {
    case firstLaunchEmpty
    case ambiguousDogGrooming
    case carMaintenance
    case heavyHistory
    case operationalHome
    case timelineSearch
    case workContinuity

    var id: String { fixtureID }

    var fixtureID: String {
        switch self {
        case .firstLaunchEmpty:
            "first_launch_empty"
        case .ambiguousDogGrooming:
            "ambiguous_dog_grooming"
        case .carMaintenance:
            "car_maintenance"
        case .heavyHistory:
            "heavy_history"
        case .operationalHome:
            "operational_home"
        case .timelineSearch:
            "timeline_search"
        case .workContinuity:
            "work_continuity"
        }
    }

    init?(argumentValue: String) {
        let normalized = Self.aliases[argumentValue] ?? argumentValue
        guard let scenario = Self.allCases.first(where: { $0.fixtureID == normalized }) else {
            return nil
        }
        self = scenario
    }

    private static let aliases = [
        "first-run-empty": "first_launch_empty",
        "overview-basic": "car_maintenance",
        "review-partial": "ambiguous_dog_grooming",
        "dog-continuity": "operational_home",
        "dog_continuity": "operational_home"
    ]
}

struct SeedScenarioFixture: Codable {
    static let supportedFixtureSchemaVersion = 1
    static let supportedLedgerSchemaVersion = 3

    let fixtureSchemaVersion: Int
    let ledgerSchemaVersion: Int
    let id: String
    let title: String
    let description: String
    let clock: SeedScenarioClock
    let records: ExportRecords
    let expectations: JSONValue
}

struct SeedScenarioClock: Codable {
    let now: String
    let calendar: String
    let timeZone: String
}

enum SeedScenarioLoaderError: LocalizedError, CustomStringConvertible, Equatable {
    case unknownScenario(String)
    case missingFixture(String)
    case invalidFixture(String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .unknownScenario(let id):
            "Unknown seed scenario: \(id)"
        case .missingFixture(let id):
            "Missing seed scenario fixture: \(id).json"
        case .invalidFixture(let message):
            "Invalid seed scenario fixture: \(message)"
        }
    }
}

enum SeedScenarioDateParser {
    static func timestamp(_ text: String, field: String) throws -> Date {
        if let date = DateFormatting.parseISODateTime(text) {
            return date
        }
        throw SeedScenarioLoaderError.invalidFixture("\(field) has invalid timestamp \(text).")
    }

    static func dateOnly(_ text: String, calendar: Calendar, field: String) throws -> Date {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw SeedScenarioLoaderError.invalidFixture("\(field) has invalid date \(text).")
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0

        guard let date = calendar.date(from: components),
              DateFormatting.dateOnlyString(date, calendar: calendar, timeZone: calendar.timeZone) == text else {
            throw SeedScenarioLoaderError.invalidFixture("\(field) has invalid date \(text).")
        }
        return date
    }
}
