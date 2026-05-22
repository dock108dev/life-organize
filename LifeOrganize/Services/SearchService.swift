import Foundation

enum LocalSearchEntityKind: String, Codable, CaseIterable {
    case thing
    case event
    case rule
    case note
    case chatMessage
    case timelineSlice

    var displayName: String {
        switch self {
        case .thing:
            "Thing"
        case .event:
            "Event"
        case .rule:
            "Reminder"
        case .note:
            "Note"
        case .chatMessage:
            "Message"
        case .timelineSlice:
            "Timeline"
        }
    }
}

enum LocalSearchFieldKey: String, Codable, CaseIterable {
    case title
    case name
    case alias
    case category
    case body
    case rawText
    case note
    case eventType
    case metadata
    case reason
    case linkedThingName
    case reminderType
    case reminderBehavior
    case reminderStatus
    case reminderDate
    case chatText
    case timeline
}

struct LocalSearchField: Hashable {
    let key: LocalSearchFieldKey
    let rawValue: String
    let normalizedValue: String
    let weight: Double

    init(key: LocalSearchFieldKey, rawValue: String?, weight: Double) {
        self.key = key
        self.rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.normalizedValue = SearchService.normalizeForLocalSearch(self.rawValue)
        self.weight = weight
    }
}

enum LocalSearchNavigationTarget: Hashable {
    case thingDetail(UUID)
    case eventDetail(UUID)
    case ruleDetail(UUID)
    case noteDetail(UUID)
    case chatMessage(UUID)
    case timelineSlice(TimelineSliceReplayDescriptor)
}

struct LocalSearchRecord: Identifiable, Hashable {
    let id: UUID
    let kind: LocalSearchEntityKind
    let title: String
    let subtitle: String?
    let body: String?
    let searchableFields: [LocalSearchField]
    let createdAt: Date
    let occurredAt: Date?
    let updatedAt: Date?
    let linkedThingId: UUID?
    let linkedThingName: String?
    let isActiveRule: Bool?
    let ruleBadge: String?
    let ruleLane: ReminderContinuityLane?
    let timelineDateRange: TimelineSliceDateRange?
    let navigationTarget: LocalSearchNavigationTarget

    var displayDate: Date {
        timelineDateRange?.start ?? occurredAt ?? updatedAt ?? createdAt
    }
}

struct LocalSearchQuery {
    let rawText: String
    let normalizedText: String
    let scopes: Set<LocalSearchEntityKind>
    let limit: Int
    let includeInactiveRules: Bool
    let now: Date
    let linkedThingIdFilter: UUID?
    let dateRange: TimelineSliceDateRange?
    let rangeTitle: String?
    let textFilter: String?

    init(
        rawText: String,
        scopes: Set<LocalSearchEntityKind> = Set(LocalSearchEntityKind.allCases),
        limit: Int = 50,
        includeInactiveRules: Bool = true,
        now: Date = Date(),
        linkedThingIdFilter: UUID? = nil,
        dateRange: TimelineSliceDateRange? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let parsed = LocalSearchTimingParser(calendar: calendar, now: now).parse(rawText)
        let effectiveDateRange = dateRange ?? parsed.dateRange
        let effectiveText = effectiveDateRange == nil ? rawText : parsed.remainingText
        self.rawText = rawText
        self.normalizedText = SearchService.normalizeForLocalSearch(effectiveText)
        self.scopes = scopes
        self.limit = limit
        self.includeInactiveRules = includeInactiveRules
        self.now = now
        self.linkedThingIdFilter = linkedThingIdFilter
        self.dateRange = effectiveDateRange
        self.rangeTitle = dateRange == nil ? parsed.rangeTitle : nil
        self.textFilter = effectiveText.nilIfEmpty
    }
}

struct LocalSearchResult: Identifiable, Hashable {
    let record: LocalSearchRecord
    let matchedFields: [LocalSearchFieldKey]
    let score: Double

    var id: String {
        "\(record.kind.rawValue)-\(record.id.uuidString)"
    }

    var sourceKind: LocalSearchEntityKind {
        record.kind
    }

    var stableID: UUID {
        record.id
    }

    var title: String {
        record.title
    }

    var subtitle: String? {
        record.subtitle
    }

    var body: String? {
        record.body
    }

    var date: Date {
        record.displayDate
    }

    var linkedThingId: UUID? {
        record.linkedThingId
    }

    var linkedThingName: String? {
        record.linkedThingName
    }

    var ruleBadge: String? {
        record.ruleBadge
    }

    var ruleLane: ReminderContinuityLane? {
        record.ruleLane
    }

    var navigationTarget: LocalSearchNavigationTarget {
        record.navigationTarget
    }
}

struct SearchService {
    static let activeMode = V1ScopeContract.SearchMode.localSubstring

    static func normalizeForLocalSearch(_ value: String) -> String {
        LedgerTextMatching.normalizedAlphanumericText(value, foldingDiacritics: true)
    }

    func contains(_ query: String, in candidate: String) -> Bool {
        let normalizedQuery = Self.normalizeForLocalSearch(query)
        guard !normalizedQuery.isEmpty else { return false }
        return Self.normalizeForLocalSearch(candidate).contains(normalizedQuery)
    }

    func contains(_ query: String, in thing: Thing) -> Bool {
        let key = Self.normalizeForLocalSearch(query)
        guard !key.isEmpty else { return false }

        if Self.normalizeForLocalSearch(thing.normalizedKey) == key || Self.normalizeForLocalSearch(thing.name).contains(key) {
            return true
        }

        if Self.normalizeForLocalSearch(thing.details).contains(key) {
            return true
        }

        return thing.aliases.contains { alias in
            Self.normalizeForLocalSearch(alias).contains(key)
        }
    }

    func records(
        things: [Thing],
        events: [LedgerEvent] = [],
        rules: [LedgerRule] = [],
        notes: [LedgerNote] = [],
        messages: [ChatMessage] = []
    ) -> [LocalSearchRecord] {
        things.map(record(for:))
            + events.map(record(for:))
            + rules.map(record(for:))
            + notes.map(record(for:))
            + messages.map(record(for:))
    }

    func search(_ rawText: String, in records: [LocalSearchRecord], limit: Int = 50) -> [LocalSearchResult] {
        search(LocalSearchQuery(rawText: rawText, limit: limit), in: records)
    }

    func search(_ query: LocalSearchQuery, in records: [LocalSearchRecord]) -> [LocalSearchResult] {
        guard !query.normalizedText.isEmpty || query.dateRange != nil || query.linkedThingIdFilter != nil else { return [] }

        let recordResults = records.compactMap { record in
            result(for: record, query: query)
        }

        return (recordResults + timelineSliceResults(for: query, records: records))
        .uniquedByID()
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.sourceKind != rhs.sourceKind {
                return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
            }
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.stableID.uuidString < rhs.stableID.uuidString
        }
        .prefix(max(query.limit, 0))
        .map { $0 }
    }

    func record(for thing: Thing) -> LocalSearchRecord {
        var fields = [
            LocalSearchField(key: .name, rawValue: thing.name, weight: 100),
            LocalSearchField(key: .category, rawValue: thing.category?.rawValue, weight: 35),
            LocalSearchField(key: .body, rawValue: thing.details, weight: 25),
        ]
        fields.append(contentsOf: aliasFields(for: thing, weight: 90))

        return LocalSearchRecord(
            id: thing.id,
            kind: .thing,
            title: thing.name.nilIfEmpty ?? "Untitled Thing",
            subtitle: thing.category?.rawValue.capitalized,
            body: thing.aliases.isEmpty ? thing.details.nilIfEmpty : thing.aliases.joined(separator: ", "),
            searchableFields: fields.filter { !$0.normalizedValue.isEmpty },
            createdAt: thing.createdAt,
            occurredAt: thing.lastEventAt,
            updatedAt: thing.updatedAt,
            linkedThingId: thing.id,
        linkedThingName: thing.name,
        isActiveRule: nil,
        ruleBadge: nil,
        ruleLane: nil,
        timelineDateRange: nil,
        navigationTarget: .thingDetail(thing.id)
        )
    }

    func record(for event: LedgerEvent) -> LocalSearchRecord {
        let linkedThing = event.thing
        let eventTypeDisplay = event.eventType.displayName
        var fields = [
            LocalSearchField(key: .title, rawValue: event.title, weight: 85),
            LocalSearchField(key: .eventType, rawValue: eventTypeDisplay, weight: 60),
            LocalSearchField(key: .eventType, rawValue: event.eventType.rawValue, weight: 55),
            LocalSearchField(key: .rawText, rawValue: event.rawText, weight: 45),
            LocalSearchField(key: .note, rawValue: event.note, weight: 55),
            LocalSearchField(key: .linkedThingName, rawValue: linkedThing?.name, weight: 80),
        ]
        fields.append(contentsOf: linkedThing.map { aliasFields(for: $0, weight: 70) } ?? [])
        fields.append(contentsOf: metadataFields(for: event))

        return LocalSearchRecord(
            id: event.id,
            kind: .event,
            title: event.title.nilIfEmpty ?? "Untitled Event",
            subtitle: eventSubtitle(thingName: linkedThing?.name, eventType: event.eventType),
            body: eventBody(for: event),
            searchableFields: fields.filter { !$0.normalizedValue.isEmpty },
            createdAt: event.createdAt,
            occurredAt: event.occurredAt,
            updatedAt: event.updatedAt,
            linkedThingId: linkedThing?.id,
            linkedThingName: linkedThing?.name,
            isActiveRule: nil,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: nil,
            navigationTarget: .eventDetail(event.id)
        )
    }

    func record(for rule: LedgerRule) -> LocalSearchRecord {
        let linkedThing = rule.thing
        let statusService = RuleStatusService()
        let continuityService = ReminderContinuityPresentationService(statusService: statusService)
        let presentation = continuityService.presentation(for: rule)
        let behaviorDisplay = continuityService.continuityTypeDisplayName(for: rule.continuityBehavior)
        var fields = [
            LocalSearchField(key: .title, rawValue: rule.title, weight: 95),
            LocalSearchField(key: .reason, rawValue: rule.reason, weight: 60),
            LocalSearchField(key: .rawText, rawValue: rule.rawText, weight: 50),
            LocalSearchField(key: .linkedThingName, rawValue: linkedThing?.name, weight: 80),
            LocalSearchField(key: .reminderType, rawValue: "Reminder", weight: 45),
            LocalSearchField(key: .reminderType, rawValue: rule.ruleType.savedDisplayNoun, weight: 70),
            LocalSearchField(key: .reminderType, rawValue: rule.ruleType.rawValue, weight: 65),
            LocalSearchField(key: .reminderBehavior, rawValue: behaviorDisplay, weight: 70),
            LocalSearchField(key: .reminderBehavior, rawValue: rule.continuityBehavior.rawValue, weight: 65),
            LocalSearchField(key: .reminderStatus, rawValue: presentation.lane.title, weight: 75),
            LocalSearchField(key: .reminderStatus, rawValue: presentation.badge, weight: 70),
            LocalSearchField(key: .reminderStatus, rawValue: presentation.primaryLine, weight: 65),
        ]
        fields.append(contentsOf: ruleDateFields(for: rule))
        fields.append(contentsOf: linkedThing.map { aliasFields(for: $0, weight: 70) } ?? [])

        return LocalSearchRecord(
            id: rule.id,
            kind: .rule,
            title: rule.title.nilIfEmpty ?? "Untitled Reminder",
            subtitle: reminderSubtitle(behaviorDisplay: behaviorDisplay, statusDisplay: presentation.primaryLine),
            body: rule.reason ?? rule.rawText,
            searchableFields: fields.filter { !$0.normalizedValue.isEmpty },
            createdAt: rule.createdAt,
            occurredAt: rule.startsAt,
            updatedAt: rule.updatedAt,
            linkedThingId: linkedThing?.id,
            linkedThingName: linkedThing?.name,
            isActiveRule: statusService.isActive(rule),
            ruleBadge: presentation.badge,
            ruleLane: presentation.lane,
            timelineDateRange: nil,
            navigationTarget: .ruleDetail(rule.id)
        )
    }

    func record(for note: LedgerNote) -> LocalSearchRecord {
        let primaryThing = note.linkedThings.first
        var fields = [
            LocalSearchField(key: .body, rawValue: note.text, weight: 65),
        ]
        fields.append(contentsOf: note.linkedThings.map { LocalSearchField(key: .linkedThingName, rawValue: $0.name, weight: 75) })
        fields.append(contentsOf: note.linkedThings.flatMap { aliasFields(for: $0, weight: 65) })

        return LocalSearchRecord(
            id: note.id,
            kind: .note,
            title: LedgerDisplayFormatting.noteTitle(for: note.text),
            subtitle: note.linkedThings.map(\.name).joined(separator: ", ").nilIfEmpty,
            body: note.text,
            searchableFields: fields.filter { !$0.normalizedValue.isEmpty },
            createdAt: note.createdAt,
            occurredAt: nil,
            updatedAt: note.updatedAt,
            linkedThingId: primaryThing?.id,
            linkedThingName: primaryThing?.name,
            isActiveRule: nil,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: nil,
            navigationTarget: .noteDetail(note.id)
        )
    }

    func record(for message: ChatMessage) -> LocalSearchRecord {
        LocalSearchRecord(
            id: message.id,
            kind: .chatMessage,
            title: message.role == .user ? "You" : message.role.rawValue.capitalized,
            subtitle: DateFormatting.shortDate.string(from: message.createdAt),
            body: message.text,
            searchableFields: [
                LocalSearchField(key: .chatText, rawValue: message.text, weight: 40),
            ].filter { !$0.normalizedValue.isEmpty },
            createdAt: message.createdAt,
            occurredAt: nil,
            updatedAt: nil,
            linkedThingId: nil,
            linkedThingName: nil,
            isActiveRule: nil,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: nil,
            navigationTarget: .chatMessage(message.id)
        )
    }

    private func aliasFields(for thing: Thing, weight: Double) -> [LocalSearchField] {
        let values = Array(
            Set(thing.aliases + Array(LedgerTextMatching.thingKeys(for: thing)))
        )
        return values.map { LocalSearchField(key: .alias, rawValue: $0, weight: weight) }
    }

    private func metadataFields(for event: LedgerEvent) -> [LocalSearchField] {
        event.metadataEntries.flatMap { entry -> [LocalSearchField] in
            [
                LocalSearchField(key: .metadata, rawValue: entry.key.displayName, weight: 60),
                LocalSearchField(key: .metadata, rawValue: entry.key.rawValue, weight: 55),
                LocalSearchField(key: .metadata, rawValue: entry.displayValue, weight: 65),
                LocalSearchField(key: .metadata, rawValue: entry.stringValue, weight: 60),
                LocalSearchField(key: .metadata, rawValue: entry.numberValue.map { LedgerDisplayFormatting.decimal($0) }, weight: 60),
                LocalSearchField(key: .metadata, rawValue: entry.numberValue.flatMap(compactThousandsText), weight: 50),
                LocalSearchField(key: .metadata, rawValue: entry.dateValue, weight: 60),
                LocalSearchField(key: .metadata, rawValue: entry.unit, weight: 50),
                LocalSearchField(key: .metadata, rawValue: entry.sourceText, weight: 50),
            ]
        }
    }

    private func ruleDateFields(for rule: LedgerRule) -> [LocalSearchField] {
        let startValues = ["Due", "Original due date"] + searchableDateValues(rule.startsAt)
        var fields = startValues.map { LocalSearchField(key: .reminderDate, rawValue: $0, weight: 60) }
        if let expiresAt = rule.expiresAt {
            fields += (["End date"] + searchableDateValues(expiresAt)).map { LocalSearchField(key: .reminderDate, rawValue: $0, weight: 55) }
        }
        if let deactivatedAt = rule.manuallyDeactivatedAt {
            fields += (["Completed", "Stopped"] + searchableDateValues(deactivatedAt)).map { LocalSearchField(key: .reminderDate, rawValue: $0, weight: 70) }
        }
        return fields
    }

    private func searchableDateValues(_ date: Date) -> [String] {
        [DateFormatting.dateOnlyString(date), DateFormatting.shortDate.string(from: date), DateFormatting.fullDate.string(from: date)]
    }

    private func eventSubtitle(thingName: String?, eventType: LedgerEventType) -> String? {
        let typeName = eventType == .generic ? nil : eventType.displayName
        return [thingName, typeName].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty
    }

    private func eventBody(for event: LedgerEvent) -> String? {
        let metadataSummary = EventMetadataDisplayFormatter.summary(
            for: event.metadataEntries,
            eventType: event.eventType,
            limit: 3,
            labelSeparator: " "
        )
        return [event.note, metadataSummary]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private func reminderSubtitle(behaviorDisplay: String, statusDisplay: String) -> String? {
        [
            behaviorDisplay,
            statusDisplay,
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: " · ")
        .nilIfEmpty
    }

    private func compactThousandsText(for value: Double) -> String? {
        guard value >= 1_000, value.truncatingRemainder(dividingBy: 1_000) == 0 else { return nil }
        return "\(Int(value / 1_000))k"
    }

}
