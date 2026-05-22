import Foundation
import SwiftData

@Model
final class LedgerReviewItem {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dedupeKey: String
    var kindRawValue: String
    var stateRawValue: String
    var title: String
    var detail: String
    var actionTitle: String?
    var targetTypeRawValue: String
    var targetID: UUID?
    var confidence: Double
    var evidenceJSONText: String
    var createdAt: Date
    var updatedAt: Date
    var presentedAt: Date?
    var resolvedAt: Date?
    var snoozedUntil: Date?
    var expiresAt: Date?
    var failureReason: String?

    var kind: LedgerReviewItemKind {
        get { LedgerReviewItemKind(rawValue: kindRawValue) ?? .normalizationCandidate }
        set { kindRawValue = newValue.rawValue }
    }

    var state: LedgerReviewItemState {
        get { LedgerReviewItemState(rawValue: stateRawValue) ?? .candidate }
        set { stateRawValue = newValue.rawValue }
    }

    var targetType: LedgerReviewItemTargetType {
        get { LedgerReviewItemTargetType(rawValue: targetTypeRawValue) ?? .none }
        set { targetTypeRawValue = newValue.rawValue }
    }

    var evidence: [LedgerReviewItemEvidence] {
        get { Self.decodeEvidence(from: evidenceJSONText) }
        set {
            evidenceJSONText = Self.encodeEvidence(newValue)
            updatedAt = Date()
        }
    }

    var suppressesRepeat: Bool {
        switch state {
        case .candidate, .ready, .presented, .accepted, .dismissed, .snoozed, .superseded, .expired:
            true
        case .failed:
            false
        }
    }

    init(
        id: UUID = UUID(),
        dedupeKey: String,
        kind: LedgerReviewItemKind,
        state: LedgerReviewItemState = .candidate,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        targetType: LedgerReviewItemTargetType,
        targetID: UUID?,
        confidence: Double = 1,
        evidence: [LedgerReviewItemEvidence],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.dedupeKey = dedupeKey
        self.kindRawValue = kind.rawValue
        self.stateRawValue = state.rawValue
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.targetTypeRawValue = targetType.rawValue
        self.targetID = targetID
        self.confidence = confidence
        self.evidenceJSONText = Self.encodeEvidence(evidence)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.presentedAt = nil
        self.resolvedAt = nil
        self.snoozedUntil = nil
        self.expiresAt = expiresAt
        self.failureReason = nil
    }

    func markReady(at date: Date = Date()) {
        transition(to: .ready, at: date)
    }

    func markPresented(at date: Date = Date()) {
        presentedAt = date
        transition(to: .presented, at: date)
    }

    func accept(at date: Date = Date()) {
        resolvedAt = date
        transition(to: .accepted, at: date)
    }

    func dismiss(at date: Date = Date()) {
        resolvedAt = date
        transition(to: .dismissed, at: date)
    }

    func snooze(until date: Date, at updatedDate: Date = Date()) {
        snoozedUntil = date
        transition(to: .snoozed, at: updatedDate)
    }

    func supersede(at date: Date = Date()) {
        resolvedAt = date
        transition(to: .superseded, at: date)
    }

    func expire(at date: Date = Date()) {
        resolvedAt = date
        transition(to: .expired, at: date)
    }

    func fail(reason: String, at date: Date = Date()) {
        failureReason = reason
        transition(to: .failed, at: date)
    }

    private func transition(to newState: LedgerReviewItemState, at date: Date) {
        state = newState
        updatedAt = date
    }

    private static func decodeEvidence(from text: String) -> [LedgerReviewItemEvidence] {
        guard let data = text.data(using: .utf8),
              let evidence = try? JSONDecoder().decode([LedgerReviewItemEvidence].self, from: data) else {
            return []
        }
        return evidence
    }

    private static func encodeEvidence(_ evidence: [LedgerReviewItemEvidence]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(evidence) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

enum LedgerReviewItemState: String, Codable, CaseIterable {
    case candidate
    case ready
    case presented
    case accepted
    case dismissed
    case snoozed
    case superseded
    case expired
    case failed
}

enum LedgerReviewItemKind: String, Codable, CaseIterable {
    case intervalReminder = "interval_reminder"
    case overdueReminderReview = "overdue_reminder_review"
    case localRecovery = "local_recovery"
    case extractionReview = "extraction_review"
    case duplicateThing = "duplicate_thing"
    case conflictingDate = "conflicting_date"
    case normalizationCandidate = "normalization_candidate"
}

enum LedgerReviewItemTargetType: String, Codable, CaseIterable {
    case none
    case chatMessage = "chat_message"
    case thing
    case event
    case rule
}

struct LedgerReviewItemEvidence: Codable, Equatable {
    let sourceType: LedgerReviewItemTargetType
    let sourceID: UUID
    let summary: String
    let detail: String?
}
