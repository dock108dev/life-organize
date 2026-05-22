import Foundation
import SwiftData

@Model
final class LedgerRule {
    @Attribute(.unique) var id: UUID
    var title: String
    var reason: String?
    var rawText: String
    var startsAt: Date
    var expiresAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var manuallyDeactivatedAt: Date?
    var lifecycleStateRawValue: String?
    var sourceClientID: String?
    var sourceExtractionRunID: UUID?
    var ruleTypeRawValue: String?
    var continuityBehaviorRawValue: String?
    var thing: Thing?
    var sourceMessage: ChatMessage?

    var ruleType: LedgerRuleType {
        get {
            guard let ruleTypeRawValue else { return .restriction }
            return LedgerRuleType(rawValue: ruleTypeRawValue) ?? .other
        }
        set {
            ruleTypeRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var continuityBehavior: LedgerContinuityBehavior {
        get {
            if let continuityBehaviorRawValue,
               let behavior = LedgerContinuityBehavior(rawValue: continuityBehaviorRawValue) {
                return behavior
            }
            return LedgerContinuityBehavior.inferred(
                ruleType: ruleType,
                expiresAt: expiresAt,
                rawText: rawText
            )
        }
        set {
            continuityBehaviorRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var details: String {
        get { reason ?? "" }
        set {
            reason = newValue.isEmpty ? nil : newValue
            updatedAt = Date()
        }
    }

    var thingID: UUID? {
        get { thing?.id }
        set { }
    }

    var sourceMessageID: UUID? {
        sourceMessage?.id
    }

    var isCurrentlyActive: Bool {
        isActive
    }

    var status: RuleStatus {
        RuleStatusService().status(for: self)
    }

    var lifecycleState: LedgerRuleLifecycleState {
        get {
            if let lifecycleStateRawValue,
               let state = LedgerRuleLifecycleState(rawValue: lifecycleStateRawValue) {
                return state
            }
            return manuallyDeactivatedAt == nil ? .open : .deactivated
        }
        set {
            lifecycleStateRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        reason: String? = nil,
        ruleType: LedgerRuleType = .restriction,
        continuityBehavior: LedgerContinuityBehavior? = nil,
        lifecycleState: LedgerRuleLifecycleState? = nil,
        rawText: String = "",
        startsAt: Date = Date(),
        expiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool? = nil,
        manuallyDeactivatedAt: Date? = nil,
        sourceClientID: String? = nil,
        sourceExtractionRunID: UUID? = nil,
        thing: Thing? = nil,
        sourceMessage: ChatMessage? = nil
    ) {
        self.id = id
        self.title = title
        self.reason = reason ?? (details.isEmpty ? nil : details)
        self.rawText = rawText.isEmpty ? title : rawText
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive ?? RuleStatusService().isActive(
            startsAt: startsAt,
            expiresAt: expiresAt,
            manuallyDeactivatedAt: manuallyDeactivatedAt,
            at: createdAt
        )
        self.manuallyDeactivatedAt = manuallyDeactivatedAt
        self.lifecycleStateRawValue = (lifecycleState ?? (manuallyDeactivatedAt == nil ? .open : .deactivated)).rawValue
        self.sourceClientID = sourceClientID
        self.sourceExtractionRunID = sourceExtractionRunID
        self.ruleTypeRawValue = ruleType.rawValue
        self.continuityBehaviorRawValue = (
            continuityBehavior ?? LedgerContinuityBehavior.inferred(
                ruleType: ruleType,
                expiresAt: expiresAt,
                rawText: self.rawText
            )
        ).rawValue
        self.thing = thing
        self.sourceMessage = sourceMessage
    }
}

enum RuleStatus: String, Codable, CaseIterable {
    case active
    case scheduled
    case inactive
    case expired
}

enum LedgerRuleLifecycleState: String, Codable, CaseIterable {
    case open
    case deactivated
}

enum LedgerRuleType: String, Codable, CaseIterable {
    case restriction
    case reminder
    case preference
    case deadline
    case waitingPeriod = "waiting_period"
    case other
}

enum LedgerContinuityBehavior: String, Codable, CaseIterable {
    case ongoing
    case dateBasedReminder = "date_based_reminder"
    case timeLimitedWindow = "time_limited_window"
    case recurringText = "recurring_text"

    static func inferred(
        ruleType: LedgerRuleType,
        expiresAt: Date?,
        rawText: String
    ) -> LedgerContinuityBehavior {
        if containsRecurringPhrase(rawText) {
            return .recurringText
        }
        if expiresAt != nil {
            return .timeLimitedWindow
        }
        if ruleType.isReminderLike {
            return .dateBasedReminder
        }
        return .ongoing
    }

    static func inferred(
        ruleType: LedgerRuleType,
        expiresAt: String?,
        rawText: String
    ) -> LedgerContinuityBehavior {
        inferred(ruleType: ruleType, expiresAt: expiresAt.flatMap { _ in Date() }, rawText: rawText)
    }

    private static func containsRecurringPhrase(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = [
            "every ",
            " every ",
            " daily",
            " weekly",
            " monthly",
            " yearly",
            " annually",
            " each ",
        ]
        return markers.contains { normalized.contains($0) }
    }
}

extension LedgerRuleType {
    static func normalized(_ value: String) -> LedgerRuleType {
        LedgerRuleType(rawValue: value) ?? .other
    }

    var isReminderLike: Bool {
        switch self {
        case .reminder, .deadline:
            true
        case .restriction, .preference, .waitingPeriod, .other:
            false
        }
    }

    var isRestrictive: Bool {
        switch self {
        case .restriction, .waitingPeriod:
            true
        case .reminder, .preference, .deadline, .other:
            false
        }
    }

    var savedDisplayNoun: String {
        switch self {
        case .restriction:
            "Restriction"
        case .reminder:
            "Reminder"
        case .preference:
            "Preference"
        case .deadline:
            "Deadline"
        case .waitingPeriod:
            "Waiting period"
        case .other:
            "Continuity item"
        }
    }
}
