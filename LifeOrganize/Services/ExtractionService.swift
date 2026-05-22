import Foundation

@MainActor
protocol MessageExtractionClient {
    func extractRawResponse(for text: String, now: Date) async throws -> ExtractionResponsePayload
}

struct OpenAIMessageExtractionClient: MessageExtractionClient {
    private let deviceTokenProvider: () throws -> String?
    private let serviceBaseURL: URL
    var client: (any OpenAIExtractionSending)?

    init(apiKey: String?, serviceBaseURL: URL = AppRuntimeConfiguration.defaultAIServiceBaseURL, client: (any OpenAIExtractionSending)? = nil) {
        self.deviceTokenProvider = { apiKey }
        self.serviceBaseURL = serviceBaseURL
        self.client = client
    }

    init(apiKeyStore: any APIKeyStore, serviceBaseURL: URL = AppRuntimeConfiguration.defaultAIServiceBaseURL, client: (any OpenAIExtractionSending)? = nil) {
        self.deviceTokenProvider = { try apiKeyStore.ensureDeviceToken() }
        self.serviceBaseURL = serviceBaseURL
        self.client = client
    }

    func extractRawResponse(for text: String, now: Date) async throws -> ExtractionResponsePayload {
        let deviceToken = try deviceTokenProvider()
        guard let deviceToken, !deviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.missingAPIKey
        }

        let request = Self.backendRequest(for: text, now: now)
        let requestData = try? Self.encoder.encode(request)
        let requestJSON = requestData.flatMap { String(data: $0, encoding: .utf8) }
        var payload = try await (client ?? OpenAIClient(deviceToken: deviceToken, baseURL: serviceBaseURL)).sendExtraction(request)
        if payload.requestJSON == nil {
            payload.requestJSON = requestJSON
        }
        return payload
    }

    static func backendRequest(for text: String, now: Date, timeZone: TimeZone = .current) -> BackendExtractionRequest {
        BackendExtractionRequest(
            text: text,
            currentDate: DateFormatting.dateOnlyString(now, timeZone: timeZone),
            currentDateTime: DateFormatting.isoDateTimeString(now, timeZone: timeZone, formatOptions: [.withInternetDateTime, .withFractionalSeconds]),
            timezone: timeZone.identifier,
            schemaVersion: ExtractionContract.schemaVersion
        )
    }

    static func request(for text: String, now: Date, timeZone: TimeZone = .current) -> OpenAIRequest {
        OpenAIRequest(
            model: ExtractionContract.modelName,
            input: [
                OpenAIInputMessage(
                    role: "system",
                    content: [
                        OpenAIInputContent(
                            type: "input_text",
                            text: strictInstructions
                        ),
                    ]
                ),
                OpenAIInputMessage(
                    role: "user",
                    content: [
                        OpenAIInputContent(
                            type: "input_text",
                            text: OpenAIUserPayload.string(for: text, now: now, timeZone: timeZone)
                        ),
                    ]
                ),
            ],
            text: OpenAITextOptions(
                format: OpenAIResponseFormat(
                    type: "json_schema",
                    name: OpenAIExtractionSchema.name,
                    strict: true,
                    schema: OpenAIExtractionSchema.value
                )
            )
        )
    }

    private static let encoder = JSONEncoder()

    private static let strictInstructions = """
    You extract structured data for a local personal ledger app.
    Return JSON that matches the provided schema exactly.
    Do not provide advice, coaching, emotional analysis, or conversation.
    Extract only what the user said or what is obvious from the provided current date and timezone.
    Resolve relative dates using currentDate, currentDateTime, and timezone. Never use server time.
    If a date is ambiguous, set date to null, lower confidence, and add an error.
    Use null instead of guessing and empty arrays when there are no entities of a type.
    Use only the eventType values in the schema: generic, maintenance, purchase, visit, replacement,
    cleaning, renewal, appointment, project, note, reminder, measurement, status_change, and other.
    Choose other instead of inventing a new event ontology.
    For ruleType, use reminder for one-time due reminders, restriction for do-not-do commitments,
    waiting_period for temporary waiting windows, deadline for due-by commitments, and preference
    only for standing preferences. Preserve recurring wording as text; do not claim recurring automation.
    Temporal priority order is: explicit reevaluate, revisit, check again, review later, remind me,
    or follow-up language first; then actionable relative durations such as in 90 days; then long-term
    contextual references such as next year or long term. For review/reminder language, use a reminder
    Rule with startsAt set to the actionable date and expiresAt null. Do not turn the review date into
    a restriction expiration unless the user uses clear until, through, from/to, or waiting-window language.
    Prefer Events or reminder Rules for actions, purchases, maintenance, visits, cleaning, renewals,
    appointments, projects, and anything due in the future. Do not store those as standalone Notes.
    Use top-level Notes sparingly for durable freeform facts that are not actions or obligations,
    such as codes, locations, identifiers, and plain memory facts. Link Notes to Things when possible.
    Event note is only a short annotation attached to that Event. Do not use it as a replacement for a
    standalone Note when the user provides broader freeform context.
    Treat top-level DateExtraction entries as evidence. Link them with ownerRef and ownerField when the
    date clearly belongs to one event, rule, note, or recall query; otherwise use null and unknown.
    Put practical scalar details in metadata when present, including mileage, amount, quantity, vendor,
    location, due_date, identifiers, units, and short source spans. Omit malformed metadata rather than guessing.
    """

}

enum ExtractionService {
    static func parse(rawResponseText: String) throws -> ExtractionParseResult {
        let extractedJSONText = try isolateJSONObject(from: rawResponseText)
        let data = Data(extractedJSONText.utf8)

        do {
            let rawEnvelope = try JSONDecoder().decode(CanonicalExtractionResponse.self, from: data)
            let normalized = normalize(rawEnvelope)
            return ExtractionParseResult(envelope: normalized, extractedJSONText: extractedJSONText)
        } catch let error as DecodingError {
            throw ExtractionProcessingError.schemaValidationFailed(error.localizedDescription)
        }
    }

    static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = DateFormatting.parseDateOnly(trimmed) {
            return date
        }
        return isoFormatter.date(from: trimmed)
    }

    private static func isolateJSONObject(from rawText: String) throws -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExtractionProcessingError.invalidJSON("The response was empty.")
        }

        if canDecodeJSONObject(trimmed) {
            return trimmed
        }

        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}"),
              firstBrace < lastBrace else {
            throw ExtractionProcessingError.invalidJSON("No complete JSON object was found.")
        }

        let candidate = String(trimmed[firstBrace...lastBrace])
        guard canDecodeJSONObject(candidate) else {
            throw ExtractionProcessingError.invalidJSON("The response could not be parsed as JSON.")
        }
        return candidate
    }

    private static func canDecodeJSONObject(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else {
            return false
        }
        return true
    }

    private static func normalize(_ raw: CanonicalExtractionResponse) -> ExtractionEnvelope {
        var warnings = arrayWarnings(from: raw)
        let thingByRef = raw.things.values.reduce(into: [String: String]()) { result, thing in
            if result[thing.ref] == nil {
                result[thing.ref] = thing.name
            }
        }
        let aliasesByThingRef = Dictionary(grouping: raw.aliases.values, by: \.thingRef)

        let things = raw.things.values.compactMap { rawThing -> ExtractedThing? in
            guard let name = rawThing.name.nilIfEmpty else {
                warnings.append(.validation("Skipped thing because its name was empty."))
                return nil
            }
            let aliases = aliasesByThingRef[rawThing.ref, default: []].compactMap { $0.alias.nilIfEmpty }
            return ExtractedThing(
                clientID: rawThing.ref,
                name: name,
                aliases: aliases,
                category: rawThing.category,
                confidence: rawThing.confidence
            )
        }

        let events = raw.events.values.compactMap { rawEvent -> ExtractedEvent? in
            guard let title = rawEvent.title.nilIfEmpty else {
                warnings.append(.validation("Skipped event because its title was empty."))
                return nil
            }
            guard let occurredAt = rawEvent.occurredAt.date?.nilIfEmpty,
                  parseDate(occurredAt) != nil else {
                warnings.append(.validation("Skipped event because its date was invalid."))
                return nil
            }
            return ExtractedEvent(
                clientID: rawEvent.ref,
                title: title,
                thingName: rawEvent.thingRef.flatMap { thingByRef[$0] },
                occurredAt: occurredAt,
                rawText: rawEvent.rawText.nilIfEmpty,
                note: rawEvent.note?.nilIfEmpty,
                eventType: normalizedEventType(rawEvent.eventType),
                metadata: normalizedMetadata(from: rawEvent.metadata.values)
            )
        }

        let rules = raw.rules.values.compactMap { rawRule -> ExtractedRule? in
            guard let title = rawRule.title.nilIfEmpty else {
                warnings.append(.validation("Skipped rule because its title was empty."))
                return nil
            }
            guard let startsAt = rawRule.startsAt.date?.nilIfEmpty,
                  parseDate(startsAt) != nil else {
                warnings.append(.validation("Skipped rule because its start date was invalid."))
                return nil
            }
            let expiresAt = rawRule.expiresAt.date?.nilIfEmpty
            if let expiresAt, parseDate(expiresAt) == nil {
                warnings.append(.validation("Skipped rule because its expiration date was invalid."))
                return nil
            }
            let ruleType = LedgerRuleType.normalized(rawRule.ruleType)
            if ruleType == .other && rawRule.ruleType != LedgerRuleType.other.rawValue {
                warnings.append(.validation("Rule type was not recognized and was stored as other."))
            }
            return ExtractedRule(
                clientID: rawRule.ref,
                title: title,
                thingName: rawRule.thingRef.flatMap { thingByRef[$0] },
                ruleType: ruleType,
                continuityBehavior: LedgerContinuityBehavior.inferred(
                    ruleType: ruleType,
                    expiresAt: expiresAt,
                    rawText: rawRule.rawText
                ),
                reason: rawRule.reason?.nilIfEmpty,
                startsAt: startsAt,
                expiresAt: expiresAt
            )
        }

        let notes = raw.notes.values.compactMap { rawNote -> ExtractedNote? in
            guard let text = rawNote.text.nilIfEmpty else {
                warnings.append(.validation("Skipped note because its text was empty."))
                return nil
            }
            return ExtractedNote(
                clientID: rawNote.ref,
                text: text,
                linkedThingNames: rawNote.linkedThingRefs.compactMap { thingByRef[$0] }
            )
        }

        let dates = raw.dates.values.map {
            ExtractedDate(
                clientID: $0.ref,
                sourceText: $0.sourceText,
                date: $0.resolved.date,
                precision: $0.resolved.precision,
                role: $0.dateRole,
                ownerClientID: $0.ownerRef,
                ownerField: $0.ownerField,
                isInferred: $0.resolved.isInferred,
                confidence: $0.confidence,
                resolvedConfidence: $0.resolved.confidence,
                resolvedSourceText: $0.resolved.sourceText
            )
        }
        let aliases = raw.aliases.values.map {
            ExtractedAlias(
                thingClientID: $0.thingRef,
                alias: $0.alias,
                sourceText: $0.sourceText,
                confidence: $0.confidence
            )
        }
        let recallQueries = raw.recallQueries.values.map {
            ExtractedRecallQuery(
                clientID: $0.ref,
                queryType: $0.queryType,
                thingName: $0.thingName,
                thingClientID: $0.thingRef,
                rawText: $0.rawText
            )
        }

        warnings.append(contentsOf: raw.errors.values.compactMap(modelWarning))
        if raw.confidence.requiresReview {
            warnings.append(
                ExtractionWarning(
                    code: "requires_review",
                    message: raw.confidence.reasons.filter { $0 != "none" }.joined(separator: ", ")
                )
            )
        }

        return ExtractionEnvelope(
            schemaVersion: ExtractionContract.schemaVersion,
            classification: raw.messageType,
            events: events,
            rules: rules,
            notes: notes,
            things: things,
            aliases: aliases,
            dates: dates,
            temporalResolutionDecisions: [],
            recallQueries: recallQueries,
            confidence: raw.confidence,
            extractionErrors: raw.errors.values,
            recallQuery: recallQueries.first?.rawText,
            warnings: warnings
        )
    }

    private static func arrayWarnings(from raw: CanonicalExtractionResponse) -> [ExtractionWarning] {
        [
            warning(for: "things", failedCount: raw.things.failedCount),
            warning(for: "events", failedCount: raw.events.failedCount),
            warning(for: "rules", failedCount: raw.rules.failedCount),
            warning(for: "notes", failedCount: raw.notes.failedCount),
            warning(for: "dates", failedCount: raw.dates.failedCount),
            warning(for: "aliases", failedCount: raw.aliases.failedCount),
            warning(for: "recallQueries", failedCount: raw.recallQueries.failedCount),
            warning(for: "errors", failedCount: raw.errors.failedCount),
        ].compactMap { $0 }
    }

    private static func warning(for key: String, failedCount: Int) -> ExtractionWarning? {
        guard failedCount > 0 else { return nil }
        return ExtractionWarning(code: "partial_validation_failed", message: "Skipped \(failedCount) invalid \(key) item(s).")
    }

    private static func modelWarning(_ error: ModelExtractionError) -> ExtractionWarning? {
        guard error.severity != "info" else { return nil }
        return ExtractionWarning(code: error.code, message: error.message)
    }

    private static func normalizedEventType(_ value: String) -> String {
        LedgerEventType(rawValue: value)?.rawValue ?? LedgerEventType.other.rawValue
    }

    private static func normalizedMetadata(from rawMetadata: [CanonicalEventMetadata]) -> [ExtractedEventMetadata] {
        rawMetadata.compactMap { rawMetadata -> ExtractedEventMetadata? in
            guard let entry = LedgerEventMetadataValidation.normalizedExtractionEntry(
                keyRawValue: rawMetadata.key,
                valueKindRawValue: rawMetadata.valueKind,
                stringValue: rawMetadata.stringValue,
                numberValue: rawMetadata.numberValue,
                dateValue: rawMetadata.dateValue,
                boolValue: rawMetadata.boolValue,
                unit: rawMetadata.unit,
                sourceText: rawMetadata.sourceText
            ) else {
                return nil
            }
            return ExtractedEventMetadata(
                key: entry.keyRawValue,
                valueKind: entry.valueKindRawValue,
                stringValue: entry.stringValue,
                numberValue: entry.numberValue,
                dateValue: entry.dateValue,
                boolValue: entry.boolValue,
                unit: entry.unit,
                sourceText: entry.sourceText
            )
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()
}

enum ExtractionProcessingError: LocalizedError, Equatable {
    case invalidJSON(String)
    case schemaValidationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message), .schemaValidationFailed(let message):
            message
        }
    }
}

private extension ExtractionWarning {
    static func validation(_ message: String) -> ExtractionWarning {
        ExtractionWarning(code: "validation_failed", message: message)
    }
}
