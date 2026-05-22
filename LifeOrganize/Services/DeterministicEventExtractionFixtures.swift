import Foundation

let eventFixtures: [DeterministicMessageExtractionFixture] = [
    DeterministicMessageExtractionFixture(
        id: "furnace_filter_changed_today_next_due_two_months",
        matches: containsAll("changed furnace filter today", "next one due in 2 months"),
        responseText: { _, now in
            let eventDate = dateString(from: now)
            let reminderDate = dateString(byAddingMonths: 2, to: now)
            return canonicalResponse(
                things: [thing("thing_furnace_filter", name: "Furnace Filter", category: "home_maintenance")],
                events: [
                    event(
                        "event_furnace_filter_changed",
                        title: "Changed furnace filter",
                        thingRef: "thing_furnace_filter",
                        occurredAt: eventDate,
                        eventType: "maintenance"
                    ),
                ],
                rules: [
                    rule(
                        "rule_furnace_filter_next_due",
                        title: "Replace furnace filter",
                        thingRef: "thing_furnace_filter",
                        ruleType: "reminder",
                        startsAt: reminderDate,
                        expiresAt: nil,
                        rawText: "Next one due in 2 months"
                    ),
                ],
                dates: [
                    dateEvidence(
                        "date_furnace_filter_changed",
                        sourceText: "today",
                        date: eventDate,
                        dateRole: "event_occurred_at",
                        ownerRef: "event_furnace_filter_changed",
                        ownerField: "occurredAt"
                    ),
                    dateEvidence(
                        "date_furnace_filter_next_due",
                        sourceText: "in 2 months",
                        date: reminderDate,
                        dateRole: "rule_starts_at",
                        ownerRef: "rule_furnace_filter_next_due",
                        ownerField: "startsAt",
                        confidence: 0.91,
                        resolvedConfidence: 0.93
                    ),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "furnace_filter_tomorrow_reminder",
        matches: containsAny(
            "remind me to replace furnace filter tomorrow",
            "remind me tomorrow to replace furnace filter"
        ),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_furnace_filter", name: "Furnace Filter", category: "home_maintenance")],
                rules: [
                    rule(
                        "rule_furnace_filter_tomorrow",
                        title: "Replace furnace filter",
                        thingRef: "thing_furnace_filter",
                        ruleType: "reminder",
                        startsAt: dateString(byAddingDays: 1, to: now),
                        expiresAt: nil,
                        rawText: "Remind me to replace furnace filter tomorrow"
                    ),
                ]
            )
        }
    ),
    eventFixture(
        id: "furnace_filter_log_request",
        match: "please log that i changed the furnace filter",
        thingRef: "thing_furnace_filter",
        thingName: "Furnace Filter",
        category: "home_maintenance",
        eventRef: "event_furnace_filter_logged",
        title: "Changed furnace filter",
        eventType: "maintenance"
    ),
    DeterministicMessageExtractionFixture(
        id: "furnace_filter_changed_yesterday",
        matches: contains("changed furnace filter yesterday"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_furnace_filter",
                thingName: "Furnace Filter",
                thingCategory: "home_maintenance",
                eventRef: "event_furnace_filter_yesterday",
                title: "Changed furnace filter",
                eventType: "maintenance",
                occurredAt: dateString(byAddingDays: -1, to: now)
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "mixed_oil_log_and_last_time_query",
        matches: contains("and when did i last"),
        responseText: { text, now in
            canonicalResponse(
                messageType: "mixed",
                things: [thing("thing_oil", name: "Oil Change", category: "vehicle")],
                events: [
                    event("event_oil", title: "Changed oil", thingRef: "thing_oil", occurredAt: dateString(from: now)),
                ],
                recallQueries: [
                    recallQuery("query_last_oil", queryType: "last_time", thingName: "Oil Change", rawText: text),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "partial_bad_date_event",
        matches: contains("partial"),
        responseText: { _, now in
            canonicalResponse(
                things: [thing("thing_oil", name: "Oil Change", category: "vehicle")],
                events: [
                    event("event_oil", title: "Changed oil", thingRef: "thing_oil", occurredAt: dateString(from: now)),
                    event("event_bad_date", title: "Checked oil again", thingRef: "thing_oil", occurredAt: "soon"),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "air_filter_every_ninety_days",
        matches: containsAll("air filter", "every 90 days"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_air_filter",
                thingName: "Air Filter",
                thingCategory: "home_maintenance",
                eventRef: "event_air_filter_interval",
                title: "Replaced air filter",
                eventType: "replacement",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(
                        key: "calendar_interval",
                        valueKind: "number",
                        numberValue: 90,
                        unit: "days",
                        sourceText: "every 90 days"
                    ),
                    metadata(
                        key: "service_reset",
                        valueKind: "boolean",
                        boolValue: true,
                        sourceText: "replaced air filter"
                    ),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "oil_every_five_thousand_miles",
        matches: { normalized in
            normalized.contains("oil") &&
                (normalized.contains("every 5,000 miles") || normalized.contains("every 5000 miles"))
        },
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_car",
                thingName: "Car",
                thingCategory: "vehicle",
                eventRef: "event_oil_mileage_interval",
                title: "Changed oil",
                eventType: "maintenance",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(
                        key: "mileage_interval",
                        valueKind: "number",
                        numberValue: 5000,
                        unit: "mi",
                        sourceText: "every 5,000 miles"
                    ),
                    metadata(
                        key: "service_reset",
                        valueKind: "boolean",
                        boolValue: true,
                        sourceText: "changed oil"
                    ),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "oil_next_due_mileage",
        matches: containsAny("next at 55,000 miles", "next at 55000 miles"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_car",
                thingName: "Car",
                thingCategory: "vehicle",
                eventRef: "event_oil_next_mileage",
                title: "Changed oil",
                eventType: "maintenance",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(
                        key: "mileage",
                        valueKind: "number",
                        numberValue: 50000,
                        unit: "mi",
                        sourceText: "50,000 miles"
                    ),
                    metadata(
                        key: "next_due_mileage",
                        valueKind: "number",
                        numberValue: 55000,
                        unit: "mi",
                        sourceText: "next at 55,000 miles"
                    ),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "oil_forty_thousand_mileage",
        matches: containsAny("40k", "40,000"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_car",
                thingName: "Car",
                thingCategory: "vehicle",
                eventRef: "event_oil_mileage",
                title: "Changed oil",
                eventType: "maintenance",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(key: "mileage", valueKind: "number", numberValue: 40000, unit: "mi", sourceText: "40k miles"),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "dog_food_thirty_pound_bag",
        matches: containsAll("bought dog food", "30 lb"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_dog_food",
                thingName: "Dog Food",
                thingCategory: "pet",
                eventRef: "event_dog_food_package",
                title: "Bought dog food",
                eventType: "purchase",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(key: "package_quantity", valueKind: "number", numberValue: 30, unit: "lb", sourceText: "30 lb bag"),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "printer_paper_purchase",
        matches: contains("bought printer paper"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_printer_paper",
                thingName: "Printer Paper",
                thingCategory: "purchase",
                eventRef: "event_printer_paper",
                title: "Bought printer paper",
                eventType: "purchase",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(key: "vendor", valueKind: "string", stringValue: "Staples", sourceText: "Staples"),
                    metadata(key: "amount", valueKind: "number", numberValue: 12.50, unit: "USD", sourceText: "$12.50"),
                    metadata(key: "quantity", valueKind: "number", numberValue: 2, sourceText: "2 reams"),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "air_filter_indicator_red",
        matches: containsAll("air filter", "indicator turns red"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_air_filter",
                thingName: "Air Filter",
                thingCategory: "home_maintenance",
                eventRef: "event_air_filter_indicator",
                title: "Changed air filter",
                eventType: "replacement",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(
                        key: "recurrence_evidence",
                        valueKind: "string",
                        stringValue: "when the indicator turns red",
                        sourceText: "when the indicator turns red"
                    ),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "dog_food_purchase",
        matches: contains("bought dog food"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_dog_food",
                thingName: "Dog Food",
                thingCategory: "pet",
                eventRef: "event_dog_food",
                title: "Bought dog food",
                eventType: "purchase",
                occurredAt: dateString(from: now)
            )
        }
    ),
    eventFixture(id: "garage_cleaning", match: "cleaned garage", thingRef: "thing_garage", thingName: "Garage", category: "home_maintenance", eventRef: "event_garage_cleaning", title: "Cleaned garage", eventType: "cleaning"),
    DeterministicMessageExtractionFixture(
        id: "dentist_visit",
        matches: contains("visited dentist"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_dentist",
                thingName: "Dentist",
                thingCategory: "health",
                eventRef: "event_dentist_visit",
                title: "Visited dentist",
                eventType: "visit",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(key: "location", valueKind: "string", stringValue: "dentist office", sourceText: "dentist office"),
                ]
            )
        }
    ),
    eventFixture(id: "smoke_detector_battery", match: "replaced smoke detector battery", thingRef: "thing_smoke_detector", thingName: "Smoke Detector", category: "home_maintenance", eventRef: "event_smoke_detector_battery", title: "Replaced smoke detector battery", eventType: "replacement"),
    eventFixture(id: "dryer_vent_cleaning", match: "cleaned dryer vent", thingRef: "thing_dryer_vent", thingName: "Dryer Vent", category: "home_maintenance", eventRef: "event_dryer_vent", title: "Cleaned dryer vent", eventType: "cleaning"),
    DeterministicMessageExtractionFixture(
        id: "passport_renewal",
        matches: contains("renewed passport"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_passport",
                thingName: "Passport",
                thingCategory: "admin",
                eventRef: "event_passport_renewal",
                title: "Renewed passport",
                eventType: "renewal",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(key: "identifier", valueKind: "string", stringValue: "passport", sourceText: "passport"),
                ]
            )
        }
    ),
    DeterministicMessageExtractionFixture(
        id: "dentist_appointment",
        matches: contains("dentist appointment"),
        responseText: { _, _ in
            singleEventResponse(
                thingRef: "thing_dentist",
                thingName: "Dentist",
                thingCategory: "health",
                eventRef: "event_dentist_appointment",
                title: "Dentist appointment",
                eventType: "appointment",
                occurredAt: "2027-01-20",
                metadata: [
                    metadata(key: "due_date", valueKind: "date", dateValue: "2027-01-20", sourceText: "Jan 20"),
                ]
            )
        }
    ),
    eventFixture(id: "kitchen_remodel_project", match: "kitchen remodel project", thingRef: "thing_kitchen_remodel", thingName: "Kitchen Remodel", category: "project", eventRef: "event_kitchen_remodel", title: "Started kitchen remodel project", eventType: "project"),
    DeterministicMessageExtractionFixture(
        id: "washer_serial_note_event",
        matches: contains("noted washer serial"),
        responseText: { _, now in
            singleEventResponse(
                thingRef: "thing_washer",
                thingName: "Washer",
                thingCategory: "home_maintenance",
                eventRef: "event_washer_serial",
                title: "Noted washer serial",
                eventType: "note",
                occurredAt: dateString(from: now),
                metadata: [
                    metadata(key: "identifier", valueKind: "string", stringValue: "A123", sourceText: "A123"),
                ]
            )
        }
    ),
]
