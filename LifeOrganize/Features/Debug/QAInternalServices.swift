import Foundation
import SwiftData

struct QARecordCounts: Equatable {
    var sourceMessages: Int
    var things: Int
    var events: Int
    var reminders: Int
    var notes: Int
    var extractionAttempts: Int
    var reviewItems: Int
    var entityLinks: Int
}

extension QARecordCounts {
    init(records: ExportRecords) {
        self.init(
            sourceMessages: records.chatMessages.count,
            things: records.things.count,
            events: records.events.count,
            reminders: records.rules.count,
            notes: records.notes.count,
            extractionAttempts: records.extractionRuns.count,
            reviewItems: records.ledgerReviewItems.count,
            entityLinks: records.entityLinks.count
        )
    }
}

struct QAFixtureDescriptor: Identifiable, Equatable {
    enum Category: String, CaseIterable {
        case quick = "Quick Fixtures"
        case extraction = "Extraction Fixtures"
        case graph = "Graph Fixtures"
        case dates = "Date Fixtures"
    }

    let scenario: SeedScenario
    let title: String
    let category: Category
    let summary: String
    let recommendedFakeNow: Date?
    let counts: QARecordCounts

    var id: String { scenario.fixtureID }
}

struct QAFixtureLoadOptions: Equatable {
    var resetBeforeLoad: Bool = false
    var applyRecommendedFakeDate: Bool = false
}

struct QAFixtureLoadResult: Equatable {
    let fixtureID: String
    let insertedCounts: QARecordCounts
    let warnings: [String]
}

@MainActor
struct QAFixtureLoader {
    let modelContext: ModelContext
    var fakeDateStore = QAFakeDateStore()

    func descriptors() -> [QAFixtureDescriptor] {
        SeedScenario.allCases.compactMap { scenario in
            guard let fixture = try? SeedScenarioLoader.fixture(for: scenario) else { return nil }
            return QAFixtureDescriptor(
                scenario: scenario,
                title: fixture.title,
                category: category(for: scenario),
                summary: fixture.description,
                recommendedFakeNow: try? SeedScenarioDateParser.timestamp(fixture.clock.now, field: "clock.now"),
                counts: QARecordCounts(records: fixture.records)
            )
        }
    }

    func load(_ descriptor: QAFixtureDescriptor, options: QAFixtureLoadOptions) throws -> QAFixtureLoadResult {
        if options.resetBeforeLoad {
            try LocalDataClearService(modelContext: modelContext).clearLedgerData()
        }
        let fixture = try SeedScenarioLoader.fixture(for: descriptor.scenario)
        let wasAlreadyPresent = try allRecordIDsExist(in: fixture.records)
        try SeedScenarioLoader.loadFixture(fixture, into: modelContext)
        if options.applyRecommendedFakeDate, let recommendedFakeNow = descriptor.recommendedFakeNow {
            fakeDateStore.setOverride(recommendedFakeNow)
        }
        var warnings: [String] = []
        if wasAlreadyPresent, !options.resetBeforeLoad {
            warnings.append("Fixture records already existed and were updated in place.")
        }
        return QAFixtureLoadResult(fixtureID: descriptor.id, insertedCounts: QARecordCounts(records: fixture.records), warnings: warnings)
    }

    private func category(for scenario: SeedScenario) -> QAFixtureDescriptor.Category {
        switch scenario {
        case .ambiguousDogGrooming:
            .extraction
        case .operationalHome, .workContinuity:
            .graph
        case .timelineSearch:
            .dates
        case .firstLaunchEmpty, .carMaintenance, .heavyHistory:
            .quick
        }
    }

    private func allRecordIDsExist(in records: ExportRecords) throws -> Bool {
        let snapshot = try RelationshipIntegrityStoreSnapshot(modelContext: modelContext)
        let ids = try FixtureIDs(records: records)
        return ids.messageIDs.allSatisfy { snapshot.messagesByID[$0] != nil } &&
            ids.thingIDs.allSatisfy { snapshot.thingsByID[$0] != nil } &&
            ids.eventIDs.allSatisfy { snapshot.eventsByID[$0] != nil } &&
            ids.ruleIDs.allSatisfy { snapshot.rulesByID[$0] != nil } &&
            ids.noteIDs.allSatisfy { snapshot.notesByID[$0] != nil }
    }
}

struct QADatabaseResetOptions: Equatable {
    var clearsFakeDate: Bool = true
}

@MainActor
struct QADatabaseResetService {
    let modelContext: ModelContext
    var fakeDateStore = QAFakeDateStore()

    func reset(options: QADatabaseResetOptions = QADatabaseResetOptions()) throws {
        try LocalDataClearService(modelContext: modelContext).clearLedgerData()
        if options.clearsFakeDate {
            fakeDateStore.clearOverride()
        }
    }
}

struct QAFakeDateStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "InternalQA.effectiveDateOverride") {
        self.defaults = defaults
        self.key = key
    }

    var overrideDate: Date? {
        defaults.object(forKey: key) as? Date
    }

    func effectiveNow(fallback: Date = AppRuntimeConfiguration.current.dateProvider.now) -> Date {
        overrideDate ?? fallback
    }

    func setOverride(_ date: Date) {
        defaults.set(date, forKey: key)
    }

    func clearOverride() {
        defaults.removeObject(forKey: key)
    }

    func parseOverride(_ text: String) throws -> Date {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = Self.isoFormatter.date(from: trimmed) {
            return date
        }
        throw SeedScenarioLoaderError.invalidFixture("Fake date must be ISO-8601.")
    }

    func displayText(for date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

@MainActor
struct QAReprocessService {
    let modelContext: ModelContext
    let deviceTokenStore: any DeviceTokenStore

    func retryableMessages() throws -> [ChatMessage] {
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        let retry = ManualExtractionRetryService(modelContext: modelContext, deviceTokenStore: deviceTokenStore)
        return try messages.filter { try retry.canRetry($0) == nil }
    }

    func reprocess(_ message: ChatMessage) async throws {
        try await ManualExtractionRetryService(modelContext: modelContext, deviceTokenStore: deviceTokenStore).retry(message)
    }

    func reprocess(messageID: UUID) async throws {
        let descriptor = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == messageID })
        guard let message = try modelContext.fetch(descriptor).first else {
            throw SeedScenarioLoaderError.invalidFixture("Source entry no longer exists.")
        }
        try await reprocess(message)
    }
}

struct QATimelineJumpOption: Identifiable, Hashable {
    let id: String
    let title: String
    let descriptor: TimelineSliceReplayDescriptor
}

struct QATimelineJumpService {
    var calendar: Calendar = .autoupdatingCurrent
    var now: Date = Date()

    func options() -> [QATimelineJumpOption] {
        var values: [QATimelineJumpOption] = []
        if let currentMonth = monthOption(offset: 0, title: "Current Month") {
            values.append(currentMonth)
        }
        if let previousMonth = monthOption(offset: -1, title: "Previous Month") {
            values.append(previousMonth)
        }
        let upcoming = TimelineSliceDateRange(start: now, endExclusive: .distantFuture)
        values.append(QATimelineJumpOption(id: "upcoming", title: "Upcoming", descriptor: TimelineSliceReplayDescriptor(title: "Upcoming", query: TimelineSliceQuery(dateRange: upcoming))))
        return values
    }

    private func monthOption(offset: Int, title: String) -> QATimelineJumpOption? {
        guard let date = calendar.date(byAdding: .month, value: offset, to: now) else { return nil }
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        guard let descriptor = TimelineSliceReplayDescriptor.month(year: year, month: month, calendar: calendar) else { return nil }
        return QATimelineJumpOption(id: "\(year)-\(month)", title: title, descriptor: descriptor)
    }
}

struct QAGraphInspectionResult: Equatable {
    let integrity: RelationshipIntegrityResult
    let orphanedLinks: [RelationshipIntegrityFailure]
    let provenanceRows: [QAGraphProvenanceRow]
    let affectedSourceRecords: [QAAffectedSourceRecord]
}

struct QAGraphProvenanceRow: Identifiable, Equatable {
    let id: UUID
    let sourceMessageID: UUID?
    let extractionAttemptID: UUID?
    let recordType: String
    let recordID: UUID
    let title: String
}

struct QAAffectedSourceRecord: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
}

@MainActor
struct QAGraphInspectionService {
    let modelContext: ModelContext
    var now: Date = Date()

    func inspect() throws -> QAGraphInspectionResult {
        let integrity = try RelationshipIntegrityValidator(modelContext: modelContext).validate(now: now)
        let snapshot = try RelationshipIntegrityStoreSnapshot(modelContext: modelContext)
        let orphanedCodes: Set<String> = ["entity_link_missing_source", "entity_link_missing_target", "entity_link_missing_source_message"]
        let orphanedLinks = integrity.failures.filter { orphanedCodes.contains($0.code) }
        let provenanceRows = provenanceRows(snapshot: snapshot)
        let affectedSourceRecords = affectedSources(failures: integrity.failures, snapshot: snapshot)
        return QAGraphInspectionResult(integrity: integrity, orphanedLinks: orphanedLinks, provenanceRows: provenanceRows, affectedSourceRecords: affectedSourceRecords)
    }

    private func provenanceRows(snapshot: RelationshipIntegrityStoreSnapshot) -> [QAGraphProvenanceRow] {
        let eventRows = snapshot.events.map {
            QAGraphProvenanceRow(id: $0.id, sourceMessageID: $0.sourceMessage?.id, extractionAttemptID: $0.sourceExtractionRunID, recordType: "Event", recordID: $0.id, title: $0.title)
        }
        let ruleRows = snapshot.rules.map {
            QAGraphProvenanceRow(id: $0.id, sourceMessageID: $0.sourceMessage?.id, extractionAttemptID: $0.sourceExtractionRunID, recordType: "Reminder", recordID: $0.id, title: $0.title)
        }
        let noteRows = snapshot.notes.map {
            QAGraphProvenanceRow(id: $0.id, sourceMessageID: $0.sourceMessage?.id, extractionAttemptID: $0.sourceExtractionRunID, recordType: "Note", recordID: $0.id, title: LedgerDisplayFormatting.noteTitle(for: $0.text))
        }
        let thingRows = snapshot.things.map {
            QAGraphProvenanceRow(id: $0.id, sourceMessageID: $0.sourceMessageIDs.first, extractionAttemptID: $0.sourceExtractionAttemptIDs.first, recordType: "Thing", recordID: $0.id, title: $0.name)
        }
        return (eventRows + ruleRows + noteRows + thingRows).sorted { $0.title < $1.title }
    }

    private func affectedSources(failures: [RelationshipIntegrityFailure], snapshot: RelationshipIntegrityStoreSnapshot) -> [QAAffectedSourceRecord] {
        let ids = Set(failures.compactMap(\.recordID))
        return snapshot.messages.filter { message in
            ids.contains(message.id) || snapshot.entityLinks.contains { ids.contains($0.id) && $0.sourceMessageID == message.id }
        }
        .map { QAAffectedSourceRecord(id: $0.id, title: "Source entry", detail: $0.text) }
    }
}

private struct FixtureIDs {
    let messageIDs: [UUID]
    let thingIDs: [UUID]
    let eventIDs: [UUID]
    let ruleIDs: [UUID]
    let noteIDs: [UUID]

    init(records: ExportRecords) throws {
        messageIDs = try records.chatMessages.map { try Self.uuid($0.id) }
        thingIDs = try records.things.map { try Self.uuid($0.id) }
        eventIDs = try records.events.map { try Self.uuid($0.id) }
        ruleIDs = try records.rules.map { try Self.uuid($0.id) }
        noteIDs = try records.notes.map { try Self.uuid($0.id) }
    }

    private static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw SeedScenarioLoaderError.invalidFixture("Invalid fixture id \(value).")
        }
        return id
    }
}
