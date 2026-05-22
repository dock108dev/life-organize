import Foundation

struct RuleStatusService {
    func isActive(_ rule: LedgerRule, at date: Date = Date()) -> Bool {
        status(for: rule, at: date) == .active
    }

    func isActive(
        startsAt: Date,
        expiresAt: Date?,
        manuallyDeactivatedAt: Date?,
        at date: Date = Date()
    ) -> Bool {
        if manuallyDeactivatedAt != nil { return false }
        if startsAt > date { return false }
        guard let expiresAt else { return true }
        return date < expiresAt
    }

    func status(for rule: LedgerRule, at date: Date = Date()) -> RuleStatus {
        if rule.manuallyDeactivatedAt != nil { return .inactive }
        if rule.startsAt > date { return .scheduled }
        if let expiresAt = rule.expiresAt, date >= expiresAt { return .expired }
        return .active
    }

    func daysRemaining(until expiresAt: Date, at date: Date = Date()) -> Int {
        let start = Self.calendar.startOfDay(for: date)
        let end = Self.calendar.startOfDay(for: expiresAt)
        let days = Self.calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }

    func daysRemainingDisplay(until expiresAt: Date, at date: Date = Date()) -> String {
        let days = daysRemaining(until: expiresAt, at: date)
        if days == 0 { return "Expires today." }
        if days == 1 { return "1 day left." }
        return "\(days) days left."
    }

    func expirationDisplay(for rule: LedgerRule, at date: Date = Date()) -> String {
        if rule.continuityBehavior == .recurringText {
            return "Recurring text saved; no automated repeat"
        }
        switch status(for: rule, at: date) {
        case .active:
            if rule.continuityBehavior == .dateBasedReminder {
                return dueDisplay(for: rule.startsAt, at: date)
            }
            if let expiresAt = rule.expiresAt {
                return rule.continuityBehavior == .timeLimitedWindow
                    ? "Window ends \(Self.date(expiresAt))"
                    : "Expires \(Self.date(expiresAt))"
            }
            return "No expiration"
        case .scheduled:
            if rule.continuityBehavior == .dateBasedReminder {
                return "Due \(Self.date(rule.startsAt))"
            }
            if let expiresAt = rule.expiresAt {
                return rule.continuityBehavior == .timeLimitedWindow
                    ? "Window \(Self.date(rule.startsAt)) to \(Self.date(expiresAt))"
                    : "Starts \(Self.date(rule.startsAt)), expires \(Self.date(expiresAt))"
            }
            return "Starts \(Self.date(rule.startsAt)), no expiration"
        case .expired:
            guard let expiresAt = rule.expiresAt else { return "Expired" }
            return "Expired \(Self.date(expiresAt))"
        case .inactive:
            guard let expiresAt = rule.expiresAt else { return "Dismissed" }
            return "Dismissed; original end date \(Self.date(expiresAt))"
        }
    }

    static func date(_ date: Date) -> String {
        DateFormatting.string(from: date, format: "MMMM d, yyyy", calendar: calendar, timeZone: calendar.timeZone)
    }

    private func dueDisplay(for dueDate: Date, at date: Date) -> String {
        if Self.calendar.isDate(dueDate, inSameDayAs: date) {
            return "Due today"
        }
        if dueDate < date {
            return "Due since \(Self.date(dueDate))"
        }
        return "Due \(Self.date(dueDate))"
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

struct RelatedRuleEvent: Identifiable {
    let event: LedgerEvent
    let source: RelatedRuleEventSource
    let sourceLabel: String

    var id: UUID {
        event.id
    }
}

enum RelatedRuleEventSource: String, Codable {
    case directLink
    case sameMessage
    case sharedSourceMessage
    case sharedThing
    case textOverlap

    var displayName: String {
        switch self {
        case .directLink:
            "Direct link"
        case .sameMessage:
            "Same message"
        case .sharedSourceMessage:
            "Shared source"
        case .sharedThing:
            "Linked thing"
        case .textOverlap:
            "Text overlap"
        }
    }
}

struct RuleRelatedEventService {
    private let traversalService = RelationshipTraversalService()

    func relatedEvents(
        for rule: LedgerRule,
        events: [LedgerEvent],
        entityLinks: [EntityLink] = []
    ) -> [RelatedRuleEvent] {
        var thingsByID: [UUID: Thing] = [:]
        for thing in ([rule.thing] + events.map(\.thing)).compactMap({ $0 }) {
            thingsByID[thing.id] = thing
        }

        let records = RelationshipTraversalRecords(
            things: Array(thingsByID.values),
            events: events,
            rules: [rule],
            entityLinks: entityLinks
        )

        let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        return traversalService.relatedRecords(
            for: .rule(rule.id),
            in: records,
            allowedTargetTypes: [.event],
            includeTextOverlap: true
        )
        .compactMap { result in
            guard case .event(let id) = result.target,
                  let event = eventByID[id],
                  let source = RelatedRuleEventSource(result.source) else {
                return nil
            }
            return RelatedRuleEvent(event: event, source: source, sourceLabel: result.sourceLabel)
        }
    }
}

private extension RelatedRuleEventSource {
    init?(_ traversalSource: RelationshipTraversalSource) {
        switch traversalSource {
        case .directLink, .extractedRecord, .sourceMessage:
            self = .directLink
        case .sameMessage:
            self = .sameMessage
        case .sharedSourceMessage:
            self = .sharedSourceMessage
        case .linkedThing, .mentionedThing, .sharedThing:
            self = .sharedThing
        case .textOverlap:
            self = .textOverlap
        }
    }
}
