enum OpenAIExtractionSchema {
    static let name = "life_ledger_extraction_v1"
    static let value: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array(requiredTopLevel.map(JSONValue.string)),
        "properties": .object([
            "schemaVersion": enumString(["1.0"]),
            "messageType": enumString(["log", "recall_query", "mixed", "empty", "unclear"]),
            "language": .object(["type": .string("string")]),
            "summary": .object(["type": .string("string")]),
            "things": array(ref("ThingExtraction")),
            "events": array(ref("EventExtraction")),
            "rules": array(ref("RuleExtraction")),
            "notes": array(ref("NoteExtraction")),
            "dates": array(ref("DateExtraction")),
            "aliases": array(ref("AliasExtraction")),
            "recallQueries": array(ref("RecallQueryExtraction")),
            "confidence": ref("OverallConfidence"),
            "errors": array(ref("ExtractionError")),
        ]),
        "$defs": .object([
            "ThingExtraction": object(
                required: ["ref", "name", "category", "mentionedText", "confidence"],
                properties: [
                    "ref": stringPattern("^thing_[0-9]+$"),
                    "name": string(),
                    "category": enumString([
                        "home_maintenance", "vehicle", "health", "work", "finance", "purchase",
                        "subscription", "project", "place", "person", "pet", "admin", "food",
                        "travel", "rule_topic", "other", "unknown",
                    ]),
                    "mentionedText": string(),
                    "confidence": confidence(),
                ]
            ),
            "EventExtraction": object(
                description: "A dated ledger action or occurrence. Use for purchases, maintenance, visits, cleaning, renewals, appointments, projects, measurements, status changes, and action-like records instead of standalone notes.",
                required: ["ref", "thingRef", "title", "eventType", "rawText", "occurredAt", "note", "metadata", "confidence"],
                properties: [
                    "ref": stringPattern("^event_[0-9]+$"),
                    "thingRef": nullableString("^thing_[0-9]+$"),
                    "title": string(),
                    "eventType": enumString([
                        "generic", "maintenance", "purchase", "visit", "replacement", "cleaning",
                        "renewal", "appointment", "project", "note", "reminder", "measurement",
                        "status_change", "other",
                    ]),
                    "rawText": string(),
                    "occurredAt": ref("ResolvedDate"),
                    "note": nullableString(description: "Short annotation about this event only. Do not use this field for broader freeform context that belongs in a standalone note."),
                    "metadata": array(ref("EventMetadataExtraction")),
                    "confidence": confidence(),
                ]
            ),
            "EventMetadataExtraction": object(
                required: [
                    "key", "valueKind", "stringValue", "numberValue", "dateValue", "boolValue",
                    "unit", "sourceText",
                ],
                properties: [
                    "key": enumString([
                        "mileage", "amount", "quantity", "unit", "vendor", "location", "subtype",
                        "identifier", "due_date", "calendar_interval", "mileage_interval",
                        "next_due_date", "next_due_mileage", "package_quantity", "service_reset",
                        "recurrence_evidence", "source_text", "other",
                    ]),
                    "valueKind": enumString(["string", "number", "date", "boolean"]),
                    "stringValue": nullableString(),
                    "numberValue": nullableNumber(),
                    "dateValue": nullableString(),
                    "boolValue": nullableBoolean(),
                    "unit": nullableString(),
                    "sourceText": nullableString(),
                ]
            ),
            "RuleExtraction": object(
                description: "A future or standing obligation, reminder, restriction, deadline, waiting period, or preference. Use reminder for due-in-the-future tasks. Explicit reevaluate, revisit, check again, review later, remind me, or follow-up language outranks long-term context such as next year: put the actionable review date in startsAt and leave expiresAt null unless the user clearly says until or describes a window.",
                required: [
                    "ref", "thingRef", "title", "ruleType", "rawText", "reason", "startsAt",
                    "expiresAt", "isActiveOnCreatedDate", "confidence",
                ],
                properties: [
                    "ref": stringPattern("^rule_[0-9]+$"),
                    "thingRef": nullableString("^thing_[0-9]+$"),
                    "title": string(),
                    "ruleType": enumString(["restriction", "reminder", "preference", "deadline", "waiting_period", "other"]),
                    "rawText": string(),
                    "reason": nullableString(),
                    "startsAt": ref("ResolvedDate"),
                    "expiresAt": ref("NullableResolvedDate"),
                    "isActiveOnCreatedDate": .object(["type": .string("boolean")]),
                    "confidence": confidence(),
                ]
            ),
            "NoteExtraction": object(
                description: "Sparse freeform fallback for durable facts that are not actions, purchases, maintenance, visits, cleaning, renewals, appointments, projects, or reminder-like input. Examples include gate codes, storage locations, identifiers, and plain memory facts.",
                required: ["ref", "text", "rawText", "linkedThingRefs", "confidence"],
                properties: [
                    "ref": stringPattern("^note_[0-9]+$"),
                    "text": string(),
                    "rawText": string(),
                    "linkedThingRefs": array(.object(["type": .string("string"), "pattern": .string("^thing_[0-9]+$")])),
                    "confidence": confidence(),
                ]
            ),
            "DateExtraction": object(
                description: "A non-authoritative date evidence ledger entry. Do not use this by itself to attach, override, or arbitrate a rule, event, note, or query date without later deterministic logic.",
                required: ["ref", "sourceText", "resolved", "dateRole", "ownerRef", "ownerField", "confidence"],
                properties: [
                    "ref": stringPattern("^date_[0-9]+$"),
                    "sourceText": string(),
                    "resolved": ref("ResolvedDate"),
                    "dateRole": enumString([
                        "event_occurred_at", "rule_starts_at", "rule_expires_at",
                        "note_date", "query_target", "duration", "unknown",
                    ]),
                    "ownerRef": nullableString("^(event|rule|note|query)_[0-9]+$"),
                    "ownerField": enumString([
                        "occurredAt", "startsAt", "expiresAt", "noteDate",
                        "queryTarget", "duration", "context", "unknown",
                    ]),
                    "confidence": confidence(),
                ]
            ),
            "AliasExtraction": object(
                required: ["thingRef", "alias", "sourceText", "confidence"],
                properties: [
                    "thingRef": stringPattern("^thing_[0-9]+$"),
                    "alias": string(),
                    "sourceText": string(),
                    "confidence": confidence(),
                ]
            ),
            "RecallQueryExtraction": object(
                required: ["ref", "queryType", "thingName", "thingRef", "rawText", "confidence"],
                properties: [
                    "ref": stringPattern("^query_[0-9]+$"),
                    "queryType": enumString(["last_time", "rule_check", "note_lookup", "search", "unknown"]),
                    "thingName": nullableString(),
                    "thingRef": nullableString("^thing_[0-9]+$"),
                    "rawText": string(),
                    "confidence": confidence(),
                ]
            ),
            "ResolvedDate": resolvedDate(),
            "NullableResolvedDate": resolvedDate(),
            "OverallConfidence": object(
                required: ["overall", "requiresReview", "reasons"],
                properties: [
                    "overall": confidence(),
                    "requiresReview": .object(["type": .string("boolean")]),
                    "reasons": array(enumString([
                        "ambiguous_date", "ambiguous_thing", "ambiguous_rule_duration",
                        "multiple_possible_entities", "low_information_message",
                        "conflicting_instruction", "unresolved_reference", "possible_duplicate", "none",
                    ])),
                ]
            ),
            "ExtractionError": object(
                required: ["code", "message", "severity", "sourceText"],
                properties: [
                    "code": enumString([
                        "no_extractable_content", "date_unresolved", "thing_unresolved",
                        "rule_unresolved", "unsupported_request", "schema_uncertain",
                    ]),
                    "message": string(),
                    "severity": enumString(["info", "warning", "blocking"]),
                    "sourceText": nullableString(),
                ]
            ),
        ]),
    ])

    private static let requiredTopLevel = [
        "schemaVersion", "messageType", "language", "summary", "things", "events",
        "rules", "notes", "dates", "aliases", "recallQueries", "confidence", "errors",
    ]

    private static func object(
        description: String? = nil,
        required: [String],
        properties: [String: JSONValue]
    ) -> JSONValue {
        var values: [String: JSONValue] = [
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array(required.map(JSONValue.string)),
            "properties": .object(properties),
        ]
        if let description {
            values["description"] = .string(description)
        }
        return .object(values)
    }

    private static func string() -> JSONValue {
        .object(["type": .string("string")])
    }

    private static func stringPattern(_ pattern: String) -> JSONValue {
        .object(["type": .string("string"), "pattern": .string(pattern)])
    }

    private static func nullableString(_ pattern: String? = nil, description: String? = nil) -> JSONValue {
        var values: [String: JSONValue] = ["type": .array([.string("string"), .string("null")])]
        if let pattern {
            values["pattern"] = .string(pattern)
        }
        if let description {
            values["description"] = .string(description)
        }
        return .object(values)
    }

    private static func nullableNumber() -> JSONValue {
        .object(["type": .array([.string("number"), .string("null")])])
    }

    private static func nullableBoolean() -> JSONValue {
        .object(["type": .array([.string("boolean"), .string("null")])])
    }

    private static func enumString(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))])
    }

    private static func confidence() -> JSONValue {
        .object(["type": .string("number"), "minimum": .number(0), "maximum": .number(1)])
    }

    private static func array(_ item: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": item])
    }

    private static func ref(_ name: String) -> JSONValue {
        .object(["$ref": .string("#/$defs/\(name)")])
    }

    private static func resolvedDate() -> JSONValue {
        object(
            required: ["date", "precision", "isInferred", "sourceText", "confidence"],
            properties: [
                "date": nullableString(),
                "precision": enumString(["day", "month", "year", "approximate", "duration", "unknown"]),
                "isInferred": .object(["type": .string("boolean")]),
                "sourceText": nullableString(),
                "confidence": confidence(),
            ]
        )
    }
}
