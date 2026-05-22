import Foundation

let ruleNoteAndRecallFixtures: [DeterministicMessageExtractionFixture] = [
    DeterministicMessageExtractionFixture(
        id: "call_dentist_reminder",
        matches: contains("remind me to call dentist"),
        responseText: { _, _ in
            canonicalResponse(
                things: [thing("thing_dentist", name: "Dentist", category: "health")],
                rules: [
                    rule("rule_call_dentist", title: "Call dentist", thingRef: "thing_dentist", ruleType: "reminder", startsAt: "2027-01-20", expiresAt: nil, rawText: "Remind me to call dentist Jan 20")
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "ambiguous_note_only",
        matches: contains("ambiguous note only"),
        responseText: { _, _ in
            canonicalResponse(notes: [note("note_ambiguous", text: "Ambiguous note only.", linkedThingRefs: [])])
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "gate_code_note",
        matches: contains("gate code is 4821"),
        responseText: { _, _ in
            canonicalResponse(
                things: [thing("thing_gate", name: "Gate", category: "place")],
                notes: [note("note_gate_code", text: "Gate code is 4821.", linkedThingRefs: ["thing_gate"])]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "domains_long_term_with_reevaluation",
        matches: containsAll("no buying domains", "reevaluate", "90 days"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_domains", name: "Domains", category: "purchase")],
                rules: [
                    rule("rule_domains", title: "No buying domains", thingRef: "thing_domains", ruleType: "restriction", startsAt: dateString(from: now), expiresAt: nil, rawText: "No buying domains long term, reevaluate in 90 days"),
                    rule("rule_domains_review", title: "Reevaluate buying domains", thingRef: "thing_domains", ruleType: "reminder", startsAt: dateString(byAddingDays: 90, to: now), expiresAt: nil, rawText: "Reevaluate buying domains in 90 days")
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "domains_reevaluate_ninety_days",
        matches: contains("reevaluate buying domains in 90 days"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_domains", name: "Domains", category: "purchase")],
                rules: [
                    rule("rule_domains_review", title: "Reevaluate buying domains", thingRef: "thing_domains", ruleType: "reminder", startsAt: dateString(byAddingDays: 90, to: now), expiresAt: nil, rawText: "Reevaluate buying domains in 90 days")
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "domains_thirty_day_restriction",
        matches: contains("no buying domains"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_domains", name: "Domains", category: "purchase")],
                rules: [
                    rule("rule_domains", title: "No buying domains", thingRef: "thing_domains", ruleType: "restriction", startsAt: dateString(from: now), expiresAt: dateString(from: now.addingTimeInterval(30 * 24 * 60 * 60)))
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "home_air_filter_two_month_reminder",
        matches: containsAny("replace air filter in 2 months", "replace air filters in 2 months"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_air_filters", name: "Air Filters", category: "home_maintenance")],
                rules: [
                    rule("rule_air_filters", title: "Replace air filters", thingRef: "thing_air_filters", ruleType: "reminder", startsAt: dateString(byAddingMonths: 2, to: now), expiresAt: nil, rawText: "Replace air filters in 2 months")
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "generic_filter_two_month_reminder",
        matches: contains("replace filter in 2 months"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_filter", name: "Filter", category: "home_maintenance")],
                rules: [
                    rule("rule_filter", title: "Replace filter", thingRef: "thing_filter", ruleType: "reminder", startsAt: dateString(byAddingMonths: 2, to: now), expiresAt: nil, rawText: "Replace filter in 2 months")
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "bogey_ambiguous_grooming",
        matches: containsAll("bogey", "haircut", "week or two"),
        responseText: { text, _ in
            canonicalResponse(
                things: [thing("thing_bogey", name: "Bogey", category: "pet")],
                dates: [
                    dateEvidence(
                        "date_bogey_haircut_window",
                        sourceText: "in a week or two",
                        date: nil,
                        dateRole: "rule_starts_at",
                        ownerRef: nil,
                        ownerField: "unknown",
                        confidence: 0.42,
                        resolvedConfidence: 0.42
                    )
                ],
                confidence: #"{"overall":0.58,"requiresReview":true,"reasons":["tentative_language","ambiguous_due_window"]}"#,
                errors: [
                    extractionError(
                        "ambiguous_due_window",
                        message: "Haircut for Bogey has an ambiguous due window; choose a date before saving a reminder.",
                        severity: "warning",
                        sourceText: text
                    )
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "garage_filter_note",
        matches: containsAny("garage filter", "remember"),
        responseText: { _, _ in
            canonicalResponse(
                things: [thing("thing_garage_filter", name: "Garage Filter", category: "home_maintenance")],
                notes: [
                    note(
                        "note_garage_filter",
                        text: "Garage filter is in the cabinet.",
                        linkedThingRefs: ["thing_garage_filter"]
                    )
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "claims_repo_work_continuity",
        matches: contains("claims repo"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_claims_repo", name: "Claims Repo", category: "work")],
                events: [
                    event(
                        "event_claims_repo",
                        title: "Started migration work",
                        thingRef: "thing_claims_repo",
                        occurredAt: dateString(from: now),
                        note: "Migration work started."
                    )
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "oil_last_time_query",
        matches: contains("when did i last"),
        responseText: { text, _ in
            canonicalResponse(
                messageType: "recall_query",
                recallQueries: [
                    recallQuery("query_last_oil", queryType: "last_time", thingName: "Oil Change", rawText: text)
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "hvac_filter_event",
        matches: contains("hvac filter"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_hvac_filter", name: "HVAC Filter", category: "home_maintenance")],
                events: [
                    event("event_hvac_filter", title: "Replaced HVAC filter", thingRef: "thing_hvac_filter", occurredAt: dateString(from: now))
                ]
            )
        }
    )
]
