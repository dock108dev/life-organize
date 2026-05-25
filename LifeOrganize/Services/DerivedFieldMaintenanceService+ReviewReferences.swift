import Foundation
import SwiftData

extension DerivedFieldMaintenanceService {
    func retargetReviewReferences(to targetType: LedgerReviewItemTargetType, from sourceID: UUID, to targetID: UUID) throws {
        let timestamp = now()
        for item in try modelContext.fetch(FetchDescriptor<LedgerReviewItem>()) {
            var changed = false
            if item.targetType == targetType, item.targetID == sourceID {
                item.targetID = targetID
                changed = true
            }
            let evidence = item.evidence
            let retargetedEvidence = evidence.map { itemEvidence in
                guard itemEvidence.sourceType == targetType, itemEvidence.sourceID == sourceID else {
                    return itemEvidence
                }
                return LedgerReviewItemEvidence(
                    sourceType: itemEvidence.sourceType,
                    sourceID: targetID,
                    summary: itemEvidence.summary,
                    detail: itemEvidence.detail
                )
            }
            if retargetedEvidence != evidence {
                item.evidence = retargetedEvidence
                changed = true
            }
            if changed {
                item.updatedAt = timestamp
            }
        }
    }

    func removeReviewReferences(to targetType: LedgerReviewItemTargetType, id: UUID) throws {
        let timestamp = now()
        for item in try modelContext.fetch(FetchDescriptor<LedgerReviewItem>()) {
            var changed = false
            if item.targetType == targetType, item.targetID == id {
                item.targetID = nil
                changed = true
            }
            let evidence = item.evidence
            let keptEvidence = evidence.filter { $0.sourceType != targetType || $0.sourceID != id }
            if keptEvidence != evidence {
                item.evidence = keptEvidence
                changed = true
            }
            guard changed else { continue }
            if item.targetID == nil, item.evidence.isEmpty, item.state.isAmbientlyVisible {
                item.supersede(at: timestamp)
            } else {
                item.updatedAt = timestamp
            }
        }
    }
}
