import Foundation

func canonicalResponse(
    messageType: String = "log",
    things: [String] = [],
    events: [String] = [],
    rules: [String] = [],
    notes: [String] = [],
    dates: [String] = [],
    aliases: [String] = [],
    recallQueries: [String] = [],
    confidence: String = #"{"overall":0.95,"requiresReview":false,"reasons":[]}"#,
    errors: [String] = []
) -> String {
    """
    {
      "schemaVersion": "1.0",
      "messageType": "\(messageType)",
      "language": "en",
      "summary": "",
      "things": [\(things.joined(separator: ","))],
      "events": [\(events.joined(separator: ","))],
      "rules": [\(rules.joined(separator: ","))],
      "notes": [\(notes.joined(separator: ","))],
      "dates": [\(dates.joined(separator: ","))],
      "aliases": [\(aliases.joined(separator: ","))],
      "recallQueries": [\(recallQueries.joined(separator: ","))],
      "confidence": \(confidence),
      "errors": [\(errors.joined(separator: ","))]
    }
    """
}

func thing(_ ref: String, name: String, category: String) -> String {
    #"{"ref":"\#(ref)","name":"\#(name)","category":"\#(category)","mentionedText":"\#(name)","confidence":0.97}"#
}

func event(
    _ ref: String,
    title: String,
    thingRef: String?,
    occurredAt: String?,
    note: String? = nil,
    eventType: String = "generic",
    metadata: [String] = []
) -> String {
    let thingRefJSON = DeterministicFixtureJSON.literal(thingRef)
    let occurredAtJSON = DeterministicFixtureJSON.resolvedDate(occurredAt, sourceText: occurredAt)
    let noteJSON = DeterministicFixtureJSON.literal(note)
    return #"{"ref":"\#(ref)","thingRef":\#(thingRefJSON),"title":"\#(title)","eventType":"\#(eventType)","rawText":"\#(title)","occurredAt":\#(occurredAtJSON),"note":\#(noteJSON),"metadata":[\#(metadata.joined(separator: ","))],"confidence":0.96}"#
}

func singleEventResponse(
    thingRef: String,
    thingName: String,
    thingCategory: String,
    eventRef: String,
    title: String,
    eventType: String,
    occurredAt: String?,
    metadata: [String] = []
) -> String {
    canonicalResponse(
        things: [
            thing(thingRef, name: thingName, category: thingCategory)
        ],
        events: [
            event(eventRef, title: title, thingRef: thingRef, occurredAt: occurredAt, eventType: eventType, metadata: metadata)
        ]
    )
}

func metadata(
    key: String,
    valueKind: String,
    stringValue: String? = nil,
    numberValue: Double? = nil,
    dateValue: String? = nil,
    boolValue: Bool? = nil,
    unit: String? = nil,
    sourceText: String? = nil
) -> String {
    let stringJSON = DeterministicFixtureJSON.literal(stringValue)
    let numberJSON = DeterministicFixtureJSON.numberLiteral(numberValue)
    let dateJSON = DeterministicFixtureJSON.literal(dateValue)
    let boolJSON = DeterministicFixtureJSON.boolLiteral(boolValue)
    let unitJSON = DeterministicFixtureJSON.literal(unit)
    let sourceTextJSON = DeterministicFixtureJSON.literal(sourceText)
    return #"{"key":"\#(key)","valueKind":"\#(valueKind)","stringValue":\#(stringJSON),"numberValue":\#(numberJSON),"dateValue":\#(dateJSON),"boolValue":\#(boolJSON),"unit":\#(unitJSON),"sourceText":\#(sourceTextJSON)}"#
}

func rule(
    _ ref: String,
    title: String,
    thingRef: String?,
    ruleType: String = "restriction",
    startsAt: String?,
    expiresAt: String?,
    rawText: String? = nil
) -> String {
    let thingRefJSON = DeterministicFixtureJSON.literal(thingRef)
    let startsAtJSON = DeterministicFixtureJSON.resolvedDate(startsAt, sourceText: startsAt)
    let expiresAtJSON = DeterministicFixtureJSON.resolvedDate(expiresAt, sourceText: expiresAt)
    return #"{"ref":"\#(ref)","thingRef":\#(thingRefJSON),"title":"\#(title)","ruleType":"\#(ruleType)","rawText":"\#(rawText ?? title)","reason":null,"startsAt":\#(startsAtJSON),"expiresAt":\#(expiresAtJSON),"isActiveOnCreatedDate":true,"confidence":0.96}"#
}

func note(_ ref: String, text: String, linkedThingRefs: [String]) -> String {
    let refs = linkedThingRefs.map(DeterministicFixtureJSON.literal).joined(separator: ",")
    return #"{"ref":"\#(ref)","text":"\#(text)","rawText":"\#(text)","linkedThingRefs":[\#(refs)],"confidence":0.96}"#
}

func dateEvidence(
    _ ref: String,
    sourceText: String,
    date: String?,
    dateRole: String,
    ownerRef: String?,
    ownerField: String,
    confidence: Double = 0.95,
    resolvedConfidence: Double = 0.95
) -> String {
    let sourceTextJSON = DeterministicFixtureJSON.literal(sourceText)
    let resolvedDateJSON = DeterministicFixtureJSON.resolvedDate(
        date,
        sourceText: sourceText,
        confidence: resolvedConfidence
    )
    let ownerRefJSON = DeterministicFixtureJSON.literal(ownerRef)
    return """
    {"ref":"\(ref)","sourceText":\(sourceTextJSON),"resolved":\(resolvedDateJSON),"dateRole":"\(dateRole)","ownerRef":\(ownerRefJSON),"ownerField":"\(ownerField)","confidence":\(confidence)}
    """
}

func recallQuery(_ ref: String, queryType: String, thingName: String?, rawText: String) -> String {
    #"{"ref":"\#(ref)","queryType":"\#(queryType)","thingName":\#(DeterministicFixtureJSON.literal(thingName)),"thingRef":null,"rawText":\#(DeterministicFixtureJSON.literal(rawText)),"confidence":0.95}"#
}

func extractionError(_ code: String, message: String, severity: String, sourceText: String?) -> String {
    #"{"code":"\#(code)","message":"\#(message)","severity":"\#(severity)","sourceText":\#(DeterministicFixtureJSON.literal(sourceText))}"#
}

func dateString(from date: Date) -> String {
    DateFormatting.dateOnlyString(date, calendar: Calendar(identifier: .gregorian), timeZone: .current)
}

func dateString(byAddingMonths months: Int, to date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let resolvedDate = calendar.date(byAdding: .month, value: months, to: date) ?? date
    return dateString(from: resolvedDate)
}

func dateString(byAddingDays days: Int, to date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let resolvedDate = calendar.date(byAdding: .day, value: days, to: date) ?? date
    return dateString(from: resolvedDate)
}

enum DeterministicFixtureJSON {
    static func resolvedDate(
        _ date: String?,
        sourceText: String? = nil,
        isInferred: Bool = true,
        confidence: Double = 0.95
    ) -> String {
        #"{"date":\#(literal(date)),"precision":"day","isInferred":\#(boolLiteral(isInferred)),"sourceText":\#(literal(sourceText)),"confidence":\#(confidence)}"#
    }

    static func literal(_ value: String?) -> String {
        guard let value else { return "null" }
        let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
        return String(data: data, encoding: .utf8) ?? #""""#
    }

    static func numberLiteral(_ value: Double?) -> String {
        guard let value else { return "null" }
        return String(value)
    }

    static func boolLiteral(_ value: Bool?) -> String {
        guard let value else { return "null" }
        return value ? "true" : "false"
    }
}
