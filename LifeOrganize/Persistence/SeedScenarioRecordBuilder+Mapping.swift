import Foundation

extension SeedScenarioRecordBuilder {
    func chatRole(_ value: String) -> ChatRole {
        ChatRole(rawValue: value) ?? .system
    }

    func extractionStatus(_ value: String) -> ExtractionStatus {
        ExtractionStatus(rawValue: value) ?? .notRequired
    }

    func extractionAttemptStatus(_ value: String) -> ExtractionAttemptStatus {
        ExtractionAttemptStatus(rawValue: value) ?? .pending
    }

    func extractionErrorCode(_ value: String) -> ExtractionErrorCode {
        ExtractionErrorCode(rawValue: value) ?? .unknown
    }

    func entityType(_ value: String) -> EntityLinkType {
        switch value {
        case "chatMessage":
            .chatMessage
        case "event":
            .event
        case "note":
            .note
        case "rule":
            .rule
        case "thing":
            .thing
        default:
            .chatMessage
        }
    }

    func entityRelation(_ value: String) -> EntityLinkRelation {
        switch value {
        case "created_from":
            .extractedFrom
        case "mentions":
            .mentionsThing
        case "linked_to":
            .aboutThing
        case "related_to":
            .sameMessage
        default:
            .mentionsThing
        }
    }

    func entityRelation(_ value: String, from sourceType: String, to targetType: String) -> EntityLinkRelation {
        if value == "linked_to", targetType == "thing" {
            switch sourceType {
            case "event", "rule":
                return .primaryThing
            case "note":
                return .aboutThing
            default:
                break
            }
        }
        return entityRelation(value)
    }

    func entityCreator(_ value: String) -> EntityLinkCreator {
        switch value {
        case "extracted":
            .extraction
        case "manual":
            .user
        case "system":
            .system
        default:
            .system
        }
    }

    func reviewItemKind(_ value: String) -> LedgerReviewItemKind {
        LedgerReviewItemKind(rawValue: value) ?? .normalizationCandidate
    }

    func reviewItemState(_ value: String) -> LedgerReviewItemState {
        LedgerReviewItemState(rawValue: value) ?? .candidate
    }

    func reviewItemTargetType(_ value: String) -> LedgerReviewItemTargetType {
        LedgerReviewItemTargetType(rawValue: value) ?? .none
    }
}

extension LedgerEvent {
    static func encodeSeedMetadata(_ entries: [LedgerEventMetadataEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension LedgerReviewItem {
    static func encodeSeedEvidence(_ evidence: [LedgerReviewItemEvidence]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(evidence) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
