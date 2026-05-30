import Foundation

struct ReviewItemDefinition {
    let dedupeKey: String
    let kind: LedgerReviewItemKind
    let title: String
    let detail: String
    let actionTitle: String?
    let targetType: LedgerReviewItemTargetType
    let targetID: UUID?
    let confidence: Double
    let evidence: [LedgerReviewItemEvidence]

    func makeItem(at date: Date) -> LedgerReviewItem {
        LedgerReviewItem(
            dedupeKey: dedupeKey,
            kind: kind,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            targetType: targetType,
            targetID: targetID,
            confidence: confidence,
            evidence: evidence,
            createdAt: date,
            updatedAt: date
        )
    }

    func apply(to item: LedgerReviewItem, at date: Date) {
        item.kind = kind
        item.title = title
        item.detail = detail
        item.actionTitle = actionTitle
        item.targetType = targetType
        item.targetID = targetID
        item.confidence = confidence
        item.evidence = evidence
        item.failureReason = nil
        item.resolvedAt = nil
        item.snoozedUntil = nil
        item.updatedAt = date
        item.state = .candidate
    }
}

extension LedgerReviewItemGenerationService {
    func latestExtractionEnvelope(for message: ChatMessage) -> ExtractionEnvelope? {
        message.extractionAttempts
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { attempt -> ExtractionEnvelope? in
                guard let data = attempt.normalizedJSONText.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(ExtractionEnvelope.self, from: data)
            }
            .first
    }
}
