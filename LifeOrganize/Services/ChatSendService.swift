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
            } else if envelope.warnings.isEmpty {
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
}
