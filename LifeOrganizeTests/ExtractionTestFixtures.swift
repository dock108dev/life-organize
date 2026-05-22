import Foundation

func canonicalExtractionJSON(
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

func canonicalThing(_ ref: String, name: String, category: String = "other", mentionedText: String? = nil) -> String {
    #"{"ref":"\#(ref)","name":"\#(name)","category":"\#(category)","mentionedText":"\#(mentionedText ?? name)","confidence":0.97}"#
}

func canonicalEvent(
    _ ref: String,
    title: String,
    thingRef: String?,
    occurredAt: String?,
    eventType: String = "generic",
    metadata: [String] = [],
    sourceText: String? = nil,
    rawText: String? = nil
) -> String {
    #"{"ref":"\#(ref)","thingRef":\#(jsonLiteral(thingRef)),"title":"\#(title)","eventType":"\#(eventType)","rawText":"\#(rawText ?? title)","occurredAt":\#(resolvedDate(occurredAt, sourceText: sourceText)),"note":null,"metadata":[\#(metadata.joined(separator: ","))],"confidence":0.96}"#
}

func canonicalEventMetadata(
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

func canonicalRule(
    _ ref: String,
    title: String,
    thingRef: String?,
    startsAt: String?,
    expiresAt: String?,
    ruleType: String = "restriction",
    sourceText: String? = nil,
    rawText: String? = nil
) -> String {
    #"{"ref":"\#(ref)","thingRef":\#(jsonLiteral(thingRef)),"title":"\#(title)","ruleType":"\#(ruleType)","rawText":"\#(rawText ?? title)","reason":null,"startsAt":\#(resolvedDate(startsAt)),"expiresAt":\#(resolvedDate(expiresAt, sourceText: sourceText)),"isActiveOnCreatedDate":true,"confidence":0.96}"#
}

func canonicalNote(_ ref: String, text: String, linkedThingRefs: [String] = []) -> String {
    let refs = linkedThingRefs.map(jsonLiteral).joined(separator: ",")
    return #"{"ref":"\#(ref)","text":"\#(text)","rawText":"\#(text)","linkedThingRefs":[\#(refs)],"confidence":0.96}"#
}

func canonicalAlias(_ thingRef: String, alias: String, sourceText: String? = nil) -> String {
    #"{"thingRef":"\#(thingRef)","alias":"\#(alias)","sourceText":"\#(sourceText ?? alias)","confidence":0.95}"#
}

func canonicalRecallQuery(_ ref: String, queryType: String, thingName: String?, rawText: String) -> String {
    #"{"ref":"\#(ref)","queryType":"\#(queryType)","thingName":\#(jsonLiteral(thingName)),"thingRef":null,"rawText":\#(jsonLiteral(rawText)),"confidence":0.95}"#
}

func canonicalDate(
    _ ref: String,
    sourceText: String,
    resolvedDateValue: String?,
    dateRole: String,
    ownerRef: String? = nil,
    ownerField: String = "unknown",
    isInferred: Bool = true,
    confidence: Double = 0.95,
    resolvedConfidence: Double = 0.95,
    resolvedSourceText: String? = nil
) -> String {
    """
    {"ref":"\(ref)","sourceText":\(jsonLiteral(sourceText)),"resolved":\(resolvedDate(resolvedDateValue, sourceText: resolvedSourceText, isInferred: isInferred, confidence: resolvedConfidence)),"dateRole":"\(dateRole)","ownerRef":\(jsonLiteral(ownerRef)),"ownerField":"\(ownerField)","confidence":\(confidence)}
    """
}

func resolvedDate(
    _ date: String?,
    sourceText: String? = nil,
    isInferred: Bool = true,
    confidence: Double = 0.95
) -> String {
    #"{"date":\#(jsonLiteral(date)),"precision":"day","isInferred":\#(jsonBoolLiteral(isInferred)),"sourceText":\#(jsonLiteral(sourceText)),"confidence":\#(confidence)}"#
}

func jsonLiteral(_ value: String?) -> String {
    guard let value else { return "null" }
    let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
    return String(data: data, encoding: .utf8) ?? #""""#
}

func jsonNumberLiteral(_ value: Double?) -> String {
    guard let value else { return "null" }
    return String(value)
}

func jsonBoolLiteral(_ value: Bool?) -> String {
    guard let value else { return "null" }
    return value ? "true" : "false"
}
