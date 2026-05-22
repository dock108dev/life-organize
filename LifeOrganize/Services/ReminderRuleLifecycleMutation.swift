import Foundation

@MainActor
enum ReminderRuleLifecycleMutation {
    static func deactivate(
        _ rule: LedgerRule,
        at date: Date,
        maintenance: DerivedFieldMaintenanceService
    ) {
        maintenance.deactivateRule(rule, at: date)
    }

    static func moveDueDate(
        _ rule: LedgerRule,
        to date: Date,
        at updatedAt: Date,
        maintenance: DerivedFieldMaintenanceService,
        calendar: Calendar = .current
    ) throws {
        rule.startsAt = DateFormatting.normalizedDateOnly(date, calendar: calendar)
        rule.expiresAt = nil
        rule.manuallyDeactivatedAt = nil
        rule.lifecycleStateRawValue = LedgerRuleLifecycleState.open.rawValue
        rule.updatedAt = updatedAt
        try maintenance.updateRule(rule)
    }

    static func setEndDate(
        _ rule: LedgerRule,
        to date: Date,
        at updatedAt: Date,
        maintenance: DerivedFieldMaintenanceService,
        calendar: Calendar = .current
    ) throws {
        rule.expiresAt = DateFormatting.normalizedDateOnly(date, calendar: calendar)
        rule.manuallyDeactivatedAt = nil
        rule.lifecycleStateRawValue = LedgerRuleLifecycleState.open.rawValue
        rule.updatedAt = updatedAt
        try maintenance.updateRule(rule)
    }
}
