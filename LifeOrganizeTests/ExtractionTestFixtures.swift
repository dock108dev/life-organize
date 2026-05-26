import Foundation
@testable import LifeOrganize

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
    let thingRefJSON = DeterministicFixtureJSON.literal(thingRef)
    let occurredAtJSON = DeterministicFixtureJSON.resolvedDate(occurredAt, sourceText: sourceText)
    return #"{"ref":"\#(ref)","thingRef":\#(thingRefJSON),"title":"\#(title)","eventType":"\#(eventType)","rawText":"\#(rawText ?? title)","occurredAt":\#(occurredAtJSON),"note":null,"metadata":[\#(metadata.joined(separator: ","))],"confidence":0.96}"#
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
    let stringJSON = DeterministicFixtureJSON.literal(stringValue)
    let numberJSON = DeterministicFixtureJSON.numberLiteral(numberValue)
    let dateJSON = DeterministicFixtureJSON.literal(dateValue)
    let boolJSON = DeterministicFixtureJSON.boolLiteral(boolValue)
    let unitJSON = DeterministicFixtureJSON.literal(unit)
    let sourceTextJSON = DeterministicFixtureJSON.literal(sourceText)
    return #"{"key":"\#(key)","valueKind":"\#(valueKind)","stringValue":\#(stringJSON),"numberValue":\#(numberJSON),"dateValue":\#(dateJSON),"boolValue":\#(boolJSON),"unit":\#(unitJSON),"sourceText":\#(sourceTextJSON)}"#
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
    let thingRefJSON = DeterministicFixtureJSON.literal(thingRef)
    let startsAtJSON = DeterministicFixtureJSON.resolvedDate(startsAt)
    let expiresAtJSON = DeterministicFixtureJSON.resolvedDate(expiresAt, sourceText: sourceText)
    return #"{"ref":"\#(ref)","thingRef":\#(thingRefJSON),"title":"\#(title)","ruleType":"\#(ruleType)","rawText":"\#(rawText ?? title)","reason":null,"startsAt":\#(startsAtJSON),"expiresAt":\#(expiresAtJSON),"isActiveOnCreatedDate":true,"confidence":0.96}"#
}

func canonicalNote(_ ref: String, text: String, linkedThingRefs: [String] = []) -> String {
    let refs = linkedThingRefs.map(DeterministicFixtureJSON.literal).joined(separator: ",")
    return #"{"ref":"\#(ref)","text":"\#(text)","rawText":"\#(text)","linkedThingRefs":[\#(refs)],"confidence":0.96}"#
}

func canonicalAlias(_ thingRef: String, alias: String, sourceText: String? = nil) -> String {
    #"{"thingRef":"\#(thingRef)","alias":"\#(alias)","sourceText":"\#(sourceText ?? alias)","confidence":0.95}"#
}

func canonicalRecallQuery(_ ref: String, queryType: String, thingName: String?, rawText: String) -> String {
    #"{"ref":"\#(ref)","queryType":"\#(queryType)","thingName":\#(DeterministicFixtureJSON.literal(thingName)),"thingRef":null,"rawText":\#(DeterministicFixtureJSON.literal(rawText)),"confidence":0.95}"#
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
    let sourceTextJSON = DeterministicFixtureJSON.literal(sourceText)
    let resolvedDateJSON = DeterministicFixtureJSON.resolvedDate(
        resolvedDateValue,
        sourceText: resolvedSourceText,
        isInferred: isInferred,
        confidence: resolvedConfidence
    )
    let ownerRefJSON = DeterministicFixtureJSON.literal(ownerRef)
    return """
    {"ref":"\(ref)","sourceText":\(sourceTextJSON),"resolved":\(resolvedDateJSON),"dateRole":"\(dateRole)","ownerRef":\(ownerRefJSON),"ownerField":"\(ownerField)","confidence":\(confidence)}
    """
}
