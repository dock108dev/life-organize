import Foundation

enum TimelineSliceDateKind: String, CaseIterable, Codable {
    case occurred
    case dueStart = "due_start"
    case completedDeactivated = "completed_deactivated"
    case created
    case updated
    case attention

    var displayName: String {
        switch self {
        case .occurred: "Occurred"
        case .dueStart: "Due"
        case .completedDeactivated: "Completed"
        case .created: "Created"
        case .updated: "Updated"
        case .attention: "Needs review"
        }
    }

    var sortRank: Int {
        switch self {
        case .occurred: 0
        case .dueStart: 1
        case .completedDeactivated: 2
        case .created: 3
        case .updated: 4
        case .attention: 5
        }
    }
}

enum TimelineSliceRecordKind: String, CaseIterable, Codable {
    case message
    case event
    case reminder
    case note
    case thing

    var displayName: String {
        switch self {
        case .message: "Message"
        case .event: "Event"
        case .reminder: "Reminder"
        case .note: "Note"
        case .thing: "Thing"
        }
    }

    var sortRank: Int {
        switch self {
        case .message: 0
        case .event: 1
        case .reminder: 2
        case .note: 3
        case .thing: 4
        }
    }
}

struct TimelineSliceDateRange: Hashable {
    let start: Date
    let endExclusive: Date

    static func month(year: Int, month: Int, calendar: Calendar) -> TimelineSliceDateRange? {
        guard
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }

        return TimelineSliceDateRange(start: calendar.startOfDay(for: start), endExclusive: calendar.startOfDay(for: end))
    }

    static func since(_ date: Date, through endExclusive: Date, calendar: Calendar) -> TimelineSliceDateRange {
        TimelineSliceDateRange(start: calendar.startOfDay(for: date), endExclusive: endExclusive)
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

enum TimelineSliceThingFilter: Hashable {
    case id(UUID)
    case text(String)

    var normalizedText: String? {
        switch self {
        case .id:
            nil
        case .text(let value):
            SearchService.normalizeForLocalSearch(value).nilIfEmpty
        }
    }
}

struct TimelineSliceQuery: Hashable {
    let dateRange: TimelineSliceDateRange?
    let linkedThingFilter: TimelineSliceThingFilter?
    let textFilter: String?

    var normalizedTextFilter: String? {
        textFilter.flatMap { SearchService.normalizeForLocalSearch($0).nilIfEmpty }
    }

    init(
        dateRange: TimelineSliceDateRange? = nil,
        linkedThingFilter: TimelineSliceThingFilter? = nil,
        textFilter: String? = nil
    ) {
        self.dateRange = dateRange
        self.linkedThingFilter = linkedThingFilter
        self.textFilter = textFilter?.nilIfEmpty
    }
}

struct TimelineSliceReplayDescriptor: Hashable {
    let title: String
    let query: TimelineSliceQuery

    static func month(year: Int, month: Int, calendar: Calendar) -> TimelineSliceReplayDescriptor? {
        guard let range = TimelineSliceDateRange.month(year: year, month: month, calendar: calendar) else { return nil }
        let title = DateFormatting.string(from: range.start, format: "MMMM yyyy", calendar: calendar, timeZone: calendar.timeZone)
        return TimelineSliceReplayDescriptor(title: title, query: TimelineSliceQuery(dateRange: range))
    }

    static func linkedThing(_ thing: Thing) -> TimelineSliceReplayDescriptor {
        TimelineSliceReplayDescriptor(
            title: "\(thing.name) timeline",
            query: TimelineSliceQuery(linkedThingFilter: .id(thing.id))
        )
    }
}

struct TimelineSliceThingContext: Hashable {
    let id: UUID
    let name: String
    let aliases: [String]
    let relationshipSourceLabel: String?
}

struct TimelineSliceRelationshipContext: Hashable {
    let sourceLabel: String
    let sourceMessageID: UUID?
    let confidence: Double?
}

struct TimelineSliceRow: Identifiable, Hashable {
    let sourceID: UUID
    let sourceKind: TimelineSliceRecordKind
    let dateKind: TimelineSliceDateKind
    let timelineDate: Date
    let createdAt: Date
    let updatedAt: Date?
    let navigationTarget: LocalSearchNavigationTarget
    let displayLabel: String
    let summaryText: String
    let linkedThings: [TimelineSliceThingContext]
    let relationshipContext: TimelineSliceRelationshipContext?
    let searchableText: String

    var id: String {
        "\(sourceKind.rawValue)-\(sourceID.uuidString)-\(dateKind.rawValue)"
    }
}
