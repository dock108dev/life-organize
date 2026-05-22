import Foundation

enum DeterministicMessageExtractionFixtureLibrary {
    static let fixtures: [DeterministicMessageExtractionFixture] = eventFixtures + ruleNoteAndRecallFixtures

    static func responseText(for text: String, now: Date) -> String {
        let normalized = text.lowercased()
        if normalized.contains("invalid json") {
            return "not json"
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return canonicalResponse()
        }

        for fixture in fixtures {
            if let response = fixture.responseIfMatched(for: text, now: now) {
                return response
            }
        }

        return fallbackResponse(for: now)
    }

    private static func fallbackResponse(for now: Date) -> String {
        canonicalResponse(
            things: [thing("thing_oil", name: "Oil Change", category: "vehicle")],
            events: [
                event("event_oil", title: "Changed oil", thingRef: "thing_oil", occurredAt: dateString(from: now))
            ],
            recallQueries: []
        )
    }
}

func eventFixture(
    id: String,
    match: String,
    thingRef: String,
    thingName: String,
    category: String,
    eventRef: String,
    title: String,
    eventType: String
) -> DeterministicMessageExtractionFixture {
    DeterministicMessageExtractionFixture(
        id: id,
        matches: contains(match),
        responseText: { _, now in
            singleEventResponse(
                thingRef: thingRef,
                thingName: thingName,
                thingCategory: category,
                eventRef: eventRef,
                title: title,
                eventType: eventType,
                occurredAt: dateString(from: now)
            )
        }
    )
}

func containsAll(_ needles: String...) -> @Sendable (String) -> Bool {
    { normalized in needles.allSatisfy { normalized.contains($0) } }
}

func containsAny(_ needles: String...) -> @Sendable (String) -> Bool {
    { normalized in needles.contains { normalized.contains($0) } }
}

func contains(_ needle: String) -> @Sendable (String) -> Bool {
    { normalized in normalized.contains(needle) }
}
