import Foundation
import SwiftData

struct QARateMetric: Equatable {
    let numerator: Int
    let denominator: Int

    var value: Double? {
        guard denominator > 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }
}

struct QACountBreakdown: Identifiable, Equatable {
    let label: String
    let count: Int

    var id: String { label }
}

struct QALatencyMetrics: Equatable {
    let sampleCount: Int
    let averageSeconds: Double?
    let p50Seconds: Double?
    let p95Seconds: Double?
    let maxSeconds: Double?
    let invalidTimingCount: Int
}

struct QAExtractionPipelineMetrics: Equatable {
    let userMessageCount: Int
    let candidateMessageCount: Int
    let attemptedMessageCount: Int
    let deterministicAttemptCount: Int
    let aiAttemptCount: Int
    let persistedEntityCandidateVolume: Int
    let attemptCoverage: QARateMetric
    let strictMessageSuccessRate: QARateMetric
    let operationalMessageSuccessRate: QARateMetric
    let strictAttemptSuccessRate: QARateMetric
    let operationalAttemptSuccessRate: QARateMetric
    let retryRate: QARateMetric
    let attentionBurdenRate: QARateMetric
    let retryDueCount: Int
    let retryNotDueCount: Int
    let retryMissingScheduleCount: Int
    let messageStatusDistribution: [QACountBreakdown]
    let attemptStatusDistribution: [QACountBreakdown]
    let attemptErrorDistribution: [QACountBreakdown]
    let latency: QALatencyMetrics
}

struct QAReviewQualityMetrics: Equatable {
    let totalReviewItems: Int
    let reviewRate: QARateMetric
    let openReviewCount: Int
    let resolvedReviewCount: Int
    let failedReviewActionCount: Int
    let duplicateThingReviewCount: Int
    let normalizationCandidateReviewCount: Int
    let temporalReviewCount: Int
    let failedTemporalInterpretationSignals: Int
    let reviewAcceptanceProxy: QARateMetric
    let openReviewCountsByKind: [QACountBreakdown]
    let resolvedReviewCountsByKind: [QACountBreakdown]
    let reviewStateDistribution: [QACountBreakdown]
}

struct QAEntityLinkQualityMetrics: Equatable {
    let nodeCount: Int
    let linkCount: Int
    let graphDensity: Double?
    let extractionCreatedLinkCount: Int
    let extractionCreatedLinkCoverage: QARateMetric
    let averageLinkConfidence: Double?
    let lowConfidenceLinkRate: QARateMetric
    let invalidConfidenceCount: Int
    let linkConfidenceDistribution: [QACountBreakdown]
    let linkCountsByCreator: [QACountBreakdown]
    let linkCountsByRelation: [QACountBreakdown]
    let orphanLikeFailureCount: Int
    let orphanLikeFailuresByCode: [QACountBreakdown]
}

struct QAExtractionQualityMetricsSnapshot: Equatable {
    let generatedAt: Date
    let extraction: QAExtractionPipelineMetrics
    let reviews: QAReviewQualityMetrics
    let entityLinks: QAEntityLinkQualityMetrics
}

@MainActor
struct QAExtractionQualityMetricsService {
    let modelContext: ModelContext
    var now: Date = Date()

    func snapshot() throws -> QAExtractionQualityMetricsSnapshot {
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let attempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
        let reviewItems = try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        let nodeCount = try relationshipNodeCount()
        let integrity = try RelationshipIntegrityValidator(modelContext: modelContext).validate(now: now)

        let candidates = messages.filter(Self.isExtractionCandidate)
        return QAExtractionQualityMetricsSnapshot(
            generatedAt: now,
            extraction: extractionMetrics(messages: messages, candidates: candidates, attempts: attempts),
            reviews: reviewMetrics(reviewItems: reviewItems, candidateCount: candidates.count, attempts: attempts, messages: messages),
            entityLinks: entityLinkMetrics(links: links, attempts: attempts, nodeCount: nodeCount, integrity: integrity)
        )
    }

    private func extractionMetrics(
        messages: [ChatMessage],
        candidates: [ChatMessage],
        attempts: [ExtractionAttempt]
    ) -> QAExtractionPipelineMetrics {
        let attemptedMessages = candidates.filter { !$0.extractionAttempts.isEmpty || $0.extractionAttemptCount > 0 }
        let terminalAttempts = attempts.filter { [.succeeded, .failed, .partiallySucceeded].contains($0.status) }
        let successfulMessages = candidates.filter { $0.extractionStatus == .succeeded }.count
        let operationalMessages = candidates.filter { [.succeeded, .partiallySucceeded].contains($0.extractionStatus) }.count
        let successfulAttempts = terminalAttempts.filter { $0.status == .succeeded }.count
        let operationalAttempts = terminalAttempts.filter { [.succeeded, .partiallySucceeded].contains($0.status) }.count
        let retryMessages = attemptedMessages.filter { max($0.extractionAttemptCount, $0.extractionAttempts.count) > 1 }.count
        let attentionMessages = candidates.filter(\.requiresPrimaryFeedAttention).count
        let pendingRetry = candidates.filter { $0.extractionStatus == .pendingRetry }

        return QAExtractionPipelineMetrics(
            userMessageCount: messages.filter { $0.role == .user }.count,
            candidateMessageCount: candidates.count,
            attemptedMessageCount: attemptedMessages.count,
            deterministicAttemptCount: attempts.filter(Self.isDeterministicAttempt).count,
            aiAttemptCount: attempts.filter { !Self.isDeterministicAttempt($0) }.count,
            persistedEntityCandidateVolume: attempts.reduce(0) { $0 + Self.createdEntityCount($1) },
            attemptCoverage: QARateMetric(numerator: attemptedMessages.count, denominator: candidates.count),
            strictMessageSuccessRate: QARateMetric(numerator: successfulMessages, denominator: candidates.count),
            operationalMessageSuccessRate: QARateMetric(numerator: operationalMessages, denominator: candidates.count),
            strictAttemptSuccessRate: QARateMetric(numerator: successfulAttempts, denominator: terminalAttempts.count),
            operationalAttemptSuccessRate: QARateMetric(numerator: operationalAttempts, denominator: terminalAttempts.count),
            retryRate: QARateMetric(numerator: retryMessages, denominator: attemptedMessages.count),
            attentionBurdenRate: QARateMetric(numerator: attentionMessages, denominator: candidates.count),
            retryDueCount: pendingRetry.filter { ($0.nextExtractionRetryAt).map { $0 <= now } ?? false }.count,
            retryNotDueCount: pendingRetry.filter { ($0.nextExtractionRetryAt).map { $0 > now } ?? false }.count,
            retryMissingScheduleCount: pendingRetry.filter { $0.nextExtractionRetryAt == nil }.count,
            messageStatusDistribution: breakdown(candidates.map { $0.extractionStatus.rawValue }),
            attemptStatusDistribution: breakdown(attempts.map { $0.status.rawValue }),
            attemptErrorDistribution: breakdown(attempts.compactMap(\.errorCodeRawValue)),
            latency: latencyMetrics(attempts)
        )
    }

    private func reviewMetrics(
        reviewItems: [LedgerReviewItem],
        candidateCount: Int,
        attempts: [ExtractionAttempt],
        messages: [ChatMessage]
    ) -> QAReviewQualityMetrics {
        let openStates: Set<LedgerReviewItemState> = [.candidate, .ready, .presented, .snoozed]
        let resolvedStates: Set<LedgerReviewItemState> = [.accepted, .dismissed, .superseded, .expired]
        let openItems = reviewItems.filter { openStates.contains($0.state) }
        let resolvedItems = reviewItems.filter { resolvedStates.contains($0.state) }
        let acceptedDismissed = reviewItems.filter { [.accepted, .dismissed].contains($0.state) }
        let accepted = acceptedDismissed.filter { $0.state == .accepted }.count
        let temporalReviews = reviewItems.filter(Self.isTemporalReviewSignal)
        let temporalErrorSignals = attempts.filter(Self.hasTemporalErrorSignal).count
            + messages.filter(Self.hasTemporalErrorSignal).count

        return QAReviewQualityMetrics(
            totalReviewItems: reviewItems.count,
            reviewRate: QARateMetric(numerator: reviewItems.count, denominator: candidateCount),
            openReviewCount: openItems.count,
            resolvedReviewCount: resolvedItems.count,
            failedReviewActionCount: reviewItems.filter { $0.state == .failed || $0.failureReason != nil }.count,
            duplicateThingReviewCount: reviewItems.filter { $0.kind == .duplicateThing }.count,
            normalizationCandidateReviewCount: reviewItems.filter { $0.kind == .normalizationCandidate }.count,
            temporalReviewCount: temporalReviews.count,
            failedTemporalInterpretationSignals: temporalReviews.count + temporalErrorSignals,
            reviewAcceptanceProxy: QARateMetric(numerator: accepted, denominator: acceptedDismissed.count),
            openReviewCountsByKind: breakdown(openItems.map { $0.kind.rawValue }),
            resolvedReviewCountsByKind: breakdown(resolvedItems.map { $0.kind.rawValue }),
            reviewStateDistribution: breakdown(reviewItems.map { $0.state.rawValue })
        )
    }

    private func entityLinkMetrics(
        links: [EntityLink],
        attempts: [ExtractionAttempt],
        nodeCount: Int,
        integrity: RelationshipIntegrityResult
    ) -> QAEntityLinkQualityMetrics {
        let createdEntityIDs = Set(attempts.flatMap(Self.createdEntityIDs))
        let extractionCreatedLinks = links.filter { $0.createdBy == .extraction }
        let coveredCreatedEntityIDs = Set(extractionCreatedLinks.flatMap { link in
            [link.sourceID, link.targetID].filter { createdEntityIDs.contains($0) }
        })
        let lowConfidenceCount = links.filter { $0.confidence < 0.5 }.count
        let invalidConfidenceCount = links.filter { !$0.confidence.isFinite || !(0...1).contains($0.confidence) }.count
        let orphanLikeFailures = integrity.failures.filter(Self.isOrphanLikeFailure)

        return QAEntityLinkQualityMetrics(
            nodeCount: nodeCount,
            linkCount: links.count,
            graphDensity: nodeCount > 0 ? Double(links.count) / Double(nodeCount) : nil,
            extractionCreatedLinkCount: extractionCreatedLinks.count,
            extractionCreatedLinkCoverage: QARateMetric(numerator: coveredCreatedEntityIDs.count, denominator: createdEntityIDs.count),
            averageLinkConfidence: average(links.map(\.confidence)),
            lowConfidenceLinkRate: QARateMetric(numerator: lowConfidenceCount, denominator: links.count),
            invalidConfidenceCount: invalidConfidenceCount,
            linkConfidenceDistribution: breakdown(links.map { Self.confidenceBucket($0.confidence) }),
            linkCountsByCreator: breakdown(links.map { $0.createdBy.rawValue }),
            linkCountsByRelation: breakdown(links.map { $0.relation.rawValue }),
            orphanLikeFailureCount: orphanLikeFailures.count,
            orphanLikeFailuresByCode: breakdown(orphanLikeFailures.map(\.code))
        )
    }

    private func latencyMetrics(_ attempts: [ExtractionAttempt]) -> QALatencyMetrics {
        var invalidTimingCount = 0
        let durations = attempts.compactMap { attempt -> Double? in
            guard let completedAt = attempt.completedAt else { return nil }
            let duration = completedAt.timeIntervalSince(attempt.startedAt)
            if duration < 0 {
                invalidTimingCount += 1
                return nil
            }
            return duration
        }
        return QALatencyMetrics(
            sampleCount: durations.count,
            averageSeconds: average(durations),
            p50Seconds: percentile(0.50, values: durations),
            p95Seconds: percentile(0.95, values: durations),
            maxSeconds: durations.max(),
            invalidTimingCount: invalidTimingCount
        )
    }

    private func relationshipNodeCount() throws -> Int {
        let messageCount = try modelContext.fetch(FetchDescriptor<ChatMessage>()).count
        let thingCount = try modelContext.fetch(FetchDescriptor<Thing>()).count
        let eventCount = try modelContext.fetch(FetchDescriptor<LedgerEvent>()).count
        let ruleCount = try modelContext.fetch(FetchDescriptor<LedgerRule>()).count
        let noteCount = try modelContext.fetch(FetchDescriptor<LedgerNote>()).count
        return messageCount + thingCount + eventCount + ruleCount + noteCount
    }

    private func breakdown(_ values: [String]) -> [QACountBreakdown] {
        Dictionary(grouping: values, by: { $0 })
            .map { QACountBreakdown(label: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentile(_ percentile: Double, values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = Int(ceil(percentile * Double(sorted.count)))
        return sorted[max(0, min(rank - 1, sorted.count - 1))]
    }

    private static func isExtractionCandidate(_ message: ChatMessage) -> Bool {
        message.role == .user
            && (message.extractionStatus != .notRequired
                || message.extractionAttemptCount > 0
                || !message.extractionAttempts.isEmpty
                || !message.linkedEntityIDs.isEmpty)
    }

    private static func isDeterministicAttempt(_ attempt: ExtractionAttempt) -> Bool {
        let model = attempt.modelName?.lowercased() ?? ""
        let request = attempt.requestJSON?.lowercased() ?? ""
        return model.contains("deterministic") || request.contains("deterministic")
    }

    private static func createdEntityCount(_ attempt: ExtractionAttempt) -> Int {
        createdEntityIDs(attempt).count
    }

    private static func createdEntityIDs(_ attempt: ExtractionAttempt) -> [UUID] {
        attempt.createdThingIDs + attempt.createdEventIDs + attempt.createdRuleIDs + attempt.createdNoteIDs
    }

    private static func isTemporalReviewSignal(_ item: LedgerReviewItem) -> Bool {
        item.kind == .conflictingDate
            || (item.kind == .extractionReview && containsTemporalSignal(item.title + " " + item.detail))
    }

    private static func hasTemporalErrorSignal(_ attempt: ExtractionAttempt) -> Bool {
        containsTemporalSignal([attempt.errorCodeRawValue, attempt.errorMessage].compactMap { $0 }.joined(separator: " "))
    }

    private static func hasTemporalErrorSignal(_ message: ChatMessage) -> Bool {
        containsTemporalSignal([message.extractionErrorCodeRawValue, message.extractionError].compactMap { $0 }.joined(separator: " "))
    }

    private static func containsTemporalSignal(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return ["temporal", "ambiguous_date", "conflicting_date", "date conflict", "in a week or two"].contains {
            lowercased.contains($0)
        }
    }

    private static func confidenceBucket(_ confidence: Double) -> String {
        guard confidence.isFinite, (0...1).contains(confidence) else { return "invalid" }
        switch confidence {
        case ..<0.25:
            return "very_low"
        case ..<0.5:
            return "low"
        case ..<0.75:
            return "medium"
        default:
            return "high"
        }
    }

    private static func isOrphanLikeFailure(_ failure: RelationshipIntegrityFailure) -> Bool {
        [
            "entity_link_missing_source",
            "entity_link_missing_target",
            "entity_link_missing_source_message"
        ].contains(failure.code)
    }
}
