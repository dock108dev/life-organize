import Foundation
import SwiftData

@MainActor
struct ChatSendService {
    let modelContext: ModelContext
    let extractor: any MessageExtractionClient
    var webRequestClient: (any WebRequestClient)?
    var dateProvider: any DateProvider = SystemDateProvider()
    var dataGeneration: UUID?
    var isDataGenerationCurrent: (UUID) -> Bool = { _ in true }
    private let responseFormatter = ChatResponseFormatter()
    private let intentClassifier = ChatIntentClassifier()

    @discardableResult
    func send(
        _ input: String,
        onRawMessagePersisted: ((ChatMessage) -> Void)? = nil
    ) async throws -> ChatMessage? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let now = dateProvider.now
        let classification = intentClassifier.classify(text)
        if classification.intent == .webLookup || classification.intent == .webImport {
            return try await sendWebRequest(text, classification: classification, now: now, onRawMessagePersisted: onRawMessagePersisted)
        }
        if let lifecycleMessage = try handleLocalLifecycleCommand(text, now: now, onRawMessagePersisted: onRawMessagePersisted) {
            return lifecycleMessage
        }
        if !classification.intent.needsExtraction {
            let message = ChatMessage(role: .user, text: text, createdAt: now, extractionStatus: .notRequired)
            modelContext.insert(message)
            try modelContext.save()
            onRawMessagePersisted?(message)
            let answer = try ChatRecallResponseService(modelContext: modelContext, now: now).answer(for: classification)
            persistAssistantMessage(answer)
            try modelContext.save()
            return message
        }

        let message = ChatMessage(
            role: .user,
            text: text,
            createdAt: now,
            extractionStatus: .pending,
            extractionVersion: ExtractionContract.schemaVersion,
            extractionAttemptCount: 1,
            lastExtractionAttemptAt: now
        )
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)

        modelContext.insert(message)
        modelContext.insert(attempt)
        try modelContext.save()
        onRawMessagePersisted?(message)
        message.extractionStatus = .extracting
        try modelContext.save()

        do {
            let payload = try await extractor.extractRawResponse(for: text, now: now)
            guard canWriteResults(for: dataGeneration) else {
                return nil
            }
            try complete(message: message, attempt: attempt, payload: payload)
        } catch {
            guard canWriteResults(for: dataGeneration) else {
                return nil
            }
            try fail(message: message, attempt: attempt, error: error)
        }
        return message
    }

    private func sendWebRequest(
        _ text: String,
        classification: ChatIntentClassification,
        now: Date,
        onRawMessagePersisted: ((ChatMessage) -> Void)?
    ) async throws -> ChatMessage {
        let mode: WebRequestMode = classification.intent == .webImport ? .importRecords : .answer
        let message = ChatMessage(
            role: .user,
            text: text,
            createdAt: now,
            extractionStatus: mode == .importRecords ? .pending : .notRequired,
            extractionVersion: ExtractionContract.schemaVersion,
            extractionAttemptCount: mode == .importRecords ? 1 : 0,
            lastExtractionAttemptAt: mode == .importRecords ? now : nil
        )
        let attempt = mode == .importRecords ? ExtractionAttempt(startedAt: now, sourceMessage: message) : nil

        modelContext.insert(message)
        if let attempt {
            modelContext.insert(attempt)
        }
        try modelContext.save()
        onRawMessagePersisted?(message)

        guard let webRequestClient else {
            if let attempt {
                try fail(message: message, attempt: attempt, error: AppError.missingServiceToken)
            } else {
                persistAssistantMessage(responseFormatter.webLookupUnavailable())
                try modelContext.save()
            }
            return message
        }

        if mode == .importRecords {
            message.extractionStatus = .extracting
            try modelContext.save()
        }

        do {
            let result = try await webRequestClient.resolve(classification.targetText, mode: mode, now: now)
            guard canWriteResults(for: dataGeneration) else {
                return message
            }
            if let payload = result.extractionPayload, let attempt {
                try complete(message: message, attempt: attempt, payload: payload)
            } else {
                message.extractionStatus = .notRequired
                persistAssistantMessage(responseFormatter.webLookupAnswer(result.assistantText?.nilIfEmpty))
            }
            try modelContext.save()
        } catch {
            guard canWriteResults(for: dataGeneration) else {
                return message
            }
            if let attempt {
                try fail(message: message, attempt: attempt, error: error)
            } else {
                persistAssistantMessage(responseFormatter.webLookupUnavailable())
                try modelContext.save()
            }
        }
        return message
    }

    func complete(
        message: ChatMessage,
        attempt: ExtractionAttempt,
        payload: ExtractionResponsePayload
    ) throws {
        attempt.rawResponseText = payload.rawResponseText
        attempt.requestJSON = payload.requestJSON
        attempt.modelName = payload.modelName
        message.rawLLMResponse = payload.rawResponseText

        do {
            let parsed = try ExtractionService.parse(rawResponseText: payload.rawResponseText)
            let envelope = TemporalPriorityResolver.resolve(
                envelope: parsed.envelope,
                sourceText: message.text,
                now: message.createdAt
            )
            attempt.normalizedJSONText = try envelope.jsonString()
            let warningsRequiringReview = Self.warningsRequiringReview(envelope.warnings)
            let createdRecords = try createEntities(from: envelope, sourceMessage: message, attempt: attempt)
            let recallAnswer = try recallAnswer(from: envelope)
            if !hasCreatedEntities(attempt), let recallAnswer {
                message.extractionStatus = .notRequired
                message.extractionError = nil
                message.extractionErrorCode = nil
                attempt.status = .succeeded
                persistAssistantMessage(recallAnswer)
            } else if !hasCreatedEntities(attempt) {
                let warning = ExtractionWarning(
                    code: "no_extractable_record",
                    message: "The response did not contain any structured records."
                )
                try recordFailure(
                    message: message,
                    attempt: attempt,
                    status: .failedNeedsReview,
                    code: .schemaValidationFailed,
                    userMessage: responseFormatter.rawOnlyFailure(),
                    detail: warning.message,
                    normalizedJSON: ExtractionEnvelope.empty(warnings: envelope.warnings + [warning])
                )
            } else if warningsRequiringReview.isEmpty {
                message.extractionStatus = .succeeded
                message.extractionError = nil
                message.extractionErrorCode = nil
                attempt.status = .succeeded
                persistAssistantMessage(
                    responseFormatter.confirmation(for: createdRecords, recallAnswer: recallAnswer)
                )
            } else if hasCreatedEntities(attempt) {
                message.extractionStatus = .partiallySucceeded
                message.extractionError = "Some extracted details need review."
                message.extractionErrorCode = .partialValidationFailed
                attempt.status = .partiallySucceeded
                attempt.errorCode = .partialValidationFailed
                attempt.errorMessage = message.extractionError
                persistAssistantMessage(
                    responseFormatter.confirmation(
                        for: createdRecords,
                        reviewLine: "Some saved details need review.",
                        recallAnswer: recallAnswer
                    )
                )
            }
        } catch {
            let code: ExtractionErrorCode
            if case ExtractionProcessingError.schemaValidationFailed = error {
                code = .schemaValidationFailed
            } else {
                code = .invalidJSON
            }
            let warning = ExtractionWarning(code: code.rawValue, message: error.localizedDescription)
            try recordFailure(
                message: message,
                attempt: attempt,
                status: .failedNeedsReview,
                code: code,
                userMessage: responseFormatter.extractionFailed(),
                detail: error.localizedDescription,
                normalizedJSON: ExtractionEnvelope.empty(warnings: [warning])
            )
        }
        attempt.completedAt = dateProvider.now
        try modelContext.save()
        try refreshReviewItems()
    }

    func fail(message: ChatMessage, attempt: ExtractionAttempt, error: Error) throws {
        let mapped = mapExtractionError(error)
        try recordFailure(
            message: message,
            attempt: attempt,
            status: mapped.status,
            code: mapped.code,
            userMessage: mapped.userMessage,
            detail: mapped.detail,
            normalizedJSON: ExtractionEnvelope.empty(
                warnings: [
                    ExtractionWarning(code: mapped.code.rawValue, message: mapped.detail)
                ]
            )
        )
        if mapped.status == .pendingRetry {
            message.nextExtractionRetryAt = nextRetryDate(for: message.extractionAttemptCount)
        } else {
            message.nextExtractionRetryAt = nil
        }
        attempt.completedAt = dateProvider.now
        try modelContext.save()
        try refreshReviewItems()
    }

    private func refreshReviewItems() throws {
        _ = try LedgerReviewItemGenerationService(modelContext: modelContext, now: { dateProvider.now }).refresh()
    }

    private static func warningsRequiringReview(_ warnings: [ExtractionWarning]) -> [ExtractionWarning] {
        warnings.filter { warning in
            guard warning.code == "requires_review" else { return true }
            let reasons = warning.message
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "none" }
            guard !reasons.isEmpty else { return false }
            return reasons.contains { $0 != "low_information_message" }
        }
    }

    private func recordFailure(
        message: ChatMessage,
        attempt: ExtractionAttempt,
        status: ExtractionStatus,
        code: ExtractionErrorCode,
        userMessage: String,
        detail: String,
        normalizedJSON: ExtractionEnvelope
    ) throws {
        message.extractionStatus = status
        message.extractionErrorCode = code
        message.extractionError = detail
        attempt.status = .failed
        attempt.errorCode = code
        attempt.errorMessage = detail
        attempt.normalizedJSONText = try normalizedJSON.jsonString()
        persistAssistantMessage(userMessage)
    }

    private func handleLocalLifecycleCommand(
        _ text: String,
        now: Date,
        onRawMessagePersisted: ((ChatMessage) -> Void)?
    ) throws -> ChatMessage? {
        guard let target = lifecyclePauseTarget(from: text) else { return nil }
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
        guard let rule = bestLifecycleMatch(for: target, in: rules, now: now) else {
            return nil
        }

        let message = ChatMessage(role: .user, text: text, createdAt: now, extractionStatus: .notRequired)
        modelContext.insert(message)
        try modelContext.save()
        onRawMessagePersisted?(message)

        ReminderRuleLifecycleMutation.deactivate(
            rule,
            at: now,
            maintenance: DerivedFieldMaintenanceService(modelContext: modelContext, now: { now })
        )
        try EntityLinkWriter(modelContext: modelContext, now: { now }).linkExtracted(message: message, rule: rule)
        if let thing = rule.thing {
            try EntityLinkWriter(modelContext: modelContext, now: { now }).linkMessage(message, mentions: thing)
        }
        persistAssistantMessage("Saved.")
        try modelContext.save()
        return message
    }

    private func lifecyclePauseTarget(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let prefixes = ["pause work on ", "pause ", "stop work on ", "stop "]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else { return nil }
        let target = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return target.nilIfEmpty
    }

    private func bestLifecycleMatch(for target: String, in rules: [LedgerRule], now: Date) -> LedgerRule? {
        let statusService = RuleStatusService()
        let candidates = rules
            .filter { rule in
                switch statusService.status(for: rule, at: now) {
                case .active, .scheduled:
                    true
                case .expired, .inactive:
                    false
                }
            }
            .compactMap { rule -> (rule: LedgerRule, score: Int)? in
                let score = lifecycleMatchScore(rule: rule, target: target)
                return score > 0 ? (rule, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.rule.startsAt != rhs.rule.startsAt { return lhs.rule.startsAt < rhs.rule.startsAt }
                return lhs.rule.updatedAt > rhs.rule.updatedAt
            }
        guard let best = candidates.first, best.score >= 3 else { return nil }
        return best.rule
    }

    private func lifecycleMatchScore(rule: LedgerRule, target: String) -> Int {
        let targetTokens = Set(ThingNormalizer.normalizeKey(target).split(separator: " ").map(String.init))
        guard !targetTokens.isEmpty else { return 0 }
        let searchable = ThingNormalizer.normalizeKey(
            [rule.title, rule.rawText, rule.reason, rule.thing?.name]
                .compactMap { $0 }
                .joined(separator: " ")
        )
        let searchableTokens = Set(searchable.split(separator: " ").map(String.init))
        let overlap = targetTokens.intersection(searchableTokens).count
        let titleContainsTarget = searchable.contains(ThingNormalizer.normalizeKey(target))
        return overlap + (titleContainsTarget ? 4 : 0)
    }
}
