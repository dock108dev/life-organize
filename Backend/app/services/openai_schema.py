from __future__ import annotations


def _enum(values: list[str]) -> dict:
    return {"type": "string", "enum": values}


def _array(item: dict) -> dict:
    return {"type": "array", "items": item}


def _ref(name: str) -> dict:
    return {"$ref": f"#/$defs/{name}"}


def _nullable_string(pattern: str | None = None, description: str | None = None) -> dict:
    value: dict = {"type": ["string", "null"]}
    if pattern:
        value["pattern"] = pattern
    if description:
        value["description"] = description
    return value


def _object(required: list[str], properties: dict, description: str | None = None) -> dict:
    value = {
        "type": "object",
        "additionalProperties": False,
        "required": required,
        "properties": properties,
    }
    if description:
        value["description"] = description
    return value


def _resolved_date() -> dict:
    return _object(
        ["date", "precision", "isInferred", "sourceText", "confidence"],
        {
            "date": _nullable_string(),
            "precision": _enum(["day", "month", "year", "approximate", "duration", "unknown"]),
            "isInferred": {"type": "boolean"},
            "sourceText": _nullable_string(),
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        },
    )


EXTRACTION_SCHEMA_NAME = "life_ledger_extraction_v1"

EXTRACTION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "schemaVersion",
        "messageType",
        "language",
        "summary",
        "things",
        "events",
        "rules",
        "notes",
        "dates",
        "aliases",
        "recallQueries",
        "confidence",
        "errors",
    ],
    "properties": {
        "schemaVersion": _enum(["1.0"]),
        "messageType": _enum(["log", "recall_query", "mixed", "empty", "unclear"]),
        "language": {"type": "string"},
        "summary": {"type": "string"},
        "things": _array(_ref("ThingExtraction")),
        "events": _array(_ref("EventExtraction")),
        "rules": _array(_ref("RuleExtraction")),
        "notes": _array(_ref("NoteExtraction")),
        "dates": _array(_ref("DateExtraction")),
        "aliases": _array(_ref("AliasExtraction")),
        "recallQueries": _array(_ref("RecallQueryExtraction")),
        "confidence": _ref("OverallConfidence"),
        "errors": _array(_ref("ExtractionError")),
    },
    "$defs": {
        "ThingExtraction": _object(
            ["ref", "name", "category", "mentionedText", "confidence"],
            {
                "ref": {"type": "string", "pattern": "^thing_[0-9]+$"},
                "name": {"type": "string"},
                "category": _enum(
                    [
                        "home_maintenance",
                        "vehicle",
                        "health",
                        "work",
                        "finance",
                        "purchase",
                        "subscription",
                        "project",
                        "place",
                        "person",
                        "pet",
                        "admin",
                        "food",
                        "travel",
                        "rule_topic",
                        "other",
                        "unknown",
                    ]
                ),
                "mentionedText": {"type": "string"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "EventExtraction": _object(
            [
                "ref",
                "thingRef",
                "title",
                "eventType",
                "rawText",
                "occurredAt",
                "note",
                "metadata",
                "confidence",
            ],
            {
                "ref": {"type": "string", "pattern": "^event_[0-9]+$"},
                "thingRef": _nullable_string("^thing_[0-9]+$"),
                "title": {"type": "string"},
                "eventType": _enum(
                    [
                        "generic",
                        "maintenance",
                        "purchase",
                        "visit",
                        "replacement",
                        "cleaning",
                        "renewal",
                        "appointment",
                        "project",
                        "note",
                        "reminder",
                        "measurement",
                        "status_change",
                        "other",
                    ]
                ),
                "rawText": {"type": "string"},
                "occurredAt": _ref("ResolvedDate"),
                "note": _nullable_string(),
                "metadata": _array(_ref("EventMetadataExtraction")),
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "EventMetadataExtraction": _object(
            [
                "key",
                "valueKind",
                "stringValue",
                "numberValue",
                "dateValue",
                "boolValue",
                "unit",
                "sourceText",
            ],
            {
                "key": _enum(
                    [
                        "mileage",
                        "amount",
                        "quantity",
                        "unit",
                        "vendor",
                        "location",
                        "subtype",
                        "identifier",
                        "due_date",
                        "calendar_interval",
                        "mileage_interval",
                        "next_due_date",
                        "next_due_mileage",
                        "package_quantity",
                        "service_reset",
                        "recurrence_evidence",
                        "source_text",
                        "other",
                    ]
                ),
                "valueKind": _enum(["string", "number", "date", "boolean"]),
                "stringValue": _nullable_string(),
                "numberValue": {"type": ["number", "null"]},
                "dateValue": _nullable_string(),
                "boolValue": {"type": ["boolean", "null"]},
                "unit": _nullable_string(),
                "sourceText": _nullable_string(),
            },
        ),
        "RuleExtraction": _object(
            [
                "ref",
                "thingRef",
                "title",
                "ruleType",
                "rawText",
                "reason",
                "startsAt",
                "expiresAt",
                "isActiveOnCreatedDate",
                "confidence",
            ],
            {
                "ref": {"type": "string", "pattern": "^rule_[0-9]+$"},
                "thingRef": _nullable_string("^thing_[0-9]+$"),
                "title": {"type": "string"},
                "ruleType": _enum(
                    ["restriction", "reminder", "preference", "deadline", "waiting_period", "other"]
                ),
                "rawText": {"type": "string"},
                "reason": _nullable_string(),
                "startsAt": _ref("ResolvedDate"),
                "expiresAt": _ref("NullableResolvedDate"),
                "isActiveOnCreatedDate": {"type": "boolean"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "NoteExtraction": _object(
            ["ref", "text", "rawText", "linkedThingRefs", "confidence"],
            {
                "ref": {"type": "string", "pattern": "^note_[0-9]+$"},
                "text": {"type": "string"},
                "rawText": {"type": "string"},
                "linkedThingRefs": _array({"type": "string", "pattern": "^thing_[0-9]+$"}),
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "DateExtraction": _object(
            ["ref", "sourceText", "resolved", "dateRole", "ownerRef", "ownerField", "confidence"],
            {
                "ref": {"type": "string", "pattern": "^date_[0-9]+$"},
                "sourceText": {"type": "string"},
                "resolved": _ref("ResolvedDate"),
                "dateRole": _enum(
                    [
                        "event_occurred_at",
                        "rule_starts_at",
                        "rule_expires_at",
                        "note_date",
                        "query_target",
                        "duration",
                        "unknown",
                    ]
                ),
                "ownerRef": _nullable_string("^(event|rule|note|query)_[0-9]+$"),
                "ownerField": _enum(
                    [
                        "occurredAt",
                        "startsAt",
                        "expiresAt",
                        "noteDate",
                        "queryTarget",
                        "duration",
                        "context",
                        "unknown",
                    ]
                ),
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "AliasExtraction": _object(
            ["thingRef", "alias", "sourceText", "confidence"],
            {
                "thingRef": {"type": "string", "pattern": "^thing_[0-9]+$"},
                "alias": {"type": "string"},
                "sourceText": {"type": "string"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "RecallQueryExtraction": _object(
            ["ref", "queryType", "thingName", "thingRef", "rawText", "confidence"],
            {
                "ref": {"type": "string", "pattern": "^query_[0-9]+$"},
                "queryType": _enum(["last_time", "rule_check", "note_lookup", "search", "unknown"]),
                "thingName": _nullable_string(),
                "thingRef": _nullable_string("^thing_[0-9]+$"),
                "rawText": {"type": "string"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
        ),
        "ResolvedDate": _resolved_date(),
        "NullableResolvedDate": _resolved_date(),
        "OverallConfidence": _object(
            ["overall", "requiresReview", "reasons"],
            {
                "overall": {"type": "number", "minimum": 0, "maximum": 1},
                "requiresReview": {"type": "boolean"},
                "reasons": _array(
                    _enum(
                        [
                            "ambiguous_date",
                            "ambiguous_thing",
                            "ambiguous_rule_duration",
                            "multiple_possible_entities",
                            "low_information_message",
                            "conflicting_instruction",
                            "unresolved_reference",
                            "possible_duplicate",
                            "none",
                        ]
                    )
                ),
            },
        ),
        "ExtractionError": _object(
            ["code", "message", "severity", "sourceText"],
            {
                "code": _enum(
                    [
                        "no_extractable_content",
                        "date_unresolved",
                        "thing_unresolved",
                        "rule_unresolved",
                        "unsupported_request",
                        "schema_uncertain",
                    ]
                ),
                "message": {"type": "string"},
                "severity": _enum(["info", "warning", "blocking"]),
                "sourceText": _nullable_string(),
            },
        ),
    },
}
