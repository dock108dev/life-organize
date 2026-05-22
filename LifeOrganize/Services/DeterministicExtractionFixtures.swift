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
    #"{"ref":"\#(ref)","thingRef":\#(jsonLiteral(thingRef)),"title":"\#(title)","eventType":"\#(eventType)","rawText":"\#(title)","occurredAt":\#(resolvedDate(occurredAt)),"note":\#(jsonLiteral(note)),"metadata":[\#(metadata.joined(separator: ","))],"confidence":0.96}"#
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
            thing(thingRef, name: thingName, category: thingCategory),
        ],
        events: [
            event(eventRef, title: title, thingRef: thingRef, occurredAt: occurredAt, eventType: eventType, metadata: metadata),
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
    #"{"key":"\#(key)","valueKind":"\#(valueKind)","stringValue":\#(jsonLiteral(stringValue)),"numberValue":\#(jsonNumberLiteral(numberValue)),"dateValue":\#(jsonLiteral(dateValue)),"boolValue":\#(jsonBoolLiteral(boolValue)),"unit":\#(jsonLiteral(unit)),"sourceText":\#(jsonLiteral(sourceText))}"#
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
    #"{"ref":"\#(ref)","thingRef":\#(jsonLiteral(thingRef)),"title":"\#(title)","ruleType":"\#(ruleType)","rawText":"\#(rawText ?? title)","reason":null,"startsAt":\#(resolvedDate(startsAt)),"expiresAt":\#(resolvedDate(expiresAt)),"isActiveOnCreatedDate":true,"confidence":0.96}"#
}

func note(_ ref: String, text: String, linkedThingRefs: [String]) -> String {
    let refs = linkedThingRefs.map(jsonLiteral).joined(separator: ",")
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
    """
    {"ref":"\(ref)","sourceText":\(jsonLiteral(sourceText)),"resolved":\(resolvedDate(date, sourceText: sourceText, confidence: resolvedConfidence)),"dateRole":"\(dateRole)","ownerRef":\(jsonLiteral(ownerRef)),"ownerField":"\(ownerField)","confidence":\(confidence)}
    """
}

func recallQuery(_ ref: String, queryType: String, thingName: String?, rawText: String) -> String {
    #"{"ref":"\#(ref)","queryType":"\#(queryType)","thingName":\#(jsonLiteral(thingName)),"thingRef":null,"rawText":\#(jsonLiteral(rawText)),"confidence":0.95}"#
}

func extractionError(_ code: String, message: String, severity: String, sourceText: String?) -> String {
    #"{"code":"\#(code)","message":"\#(message)","severity":"\#(severity)","sourceText":\#(jsonLiteral(sourceText))}"#
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

private func resolvedDate(_ date: String?) -> String {
    resolvedDate(date, sourceText: date, confidence: 0.95)
}

private func resolvedDate(_ date: String?, sourceText: String?, confidence: Double) -> String {
    #"{"date":\#(jsonLiteral(date)),"precision":"day","isInferred":true,"sourceText":\#(jsonLiteral(sourceText)),"confidence":\#(confidence)}"#
}

private func jsonLiteral(_ value: String?) -> String {
    guard let value else { return "null" }
    let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
    return String(decoding: data, as: UTF8.self)
}

private func jsonNumberLiteral(_ value: Double?) -> String {
    guard let value else { return "null" }
    return String(value)
}

private func jsonBoolLiteral(_ value: Bool?) -> String {
    guard let value else { return "null" }
    return value ? "true" : "false"
}
