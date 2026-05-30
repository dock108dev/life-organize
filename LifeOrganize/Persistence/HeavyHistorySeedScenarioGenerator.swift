import Foundation

enum HeavyHistorySeedScenarioGenerator {
    static let fixtureID = "heavy_history"

    private static let historyDays = 180
    private static let futureDays = 44

    static func fixture() -> SeedScenarioFixture {
        let builder = Builder()
        return SeedScenarioFixture(
            fixtureSchemaVersion: SeedScenarioFixture.supportedFixtureSchemaVersion,
            ledgerSchemaVersion: SeedScenarioFixture.supportedLedgerSchemaVersion,
            id: fixtureID,
            title: "Heavy History Scenario",
            description: "A deterministic multi-month ledger history with dense timeline, search, reminders, notes, review, and hidden message coverage.",
            clock: SeedScenarioClock(now: builder.timestamp(builder.baseNow), calendar: "gregorian", timeZone: builder.timeZone.identifier),
            records: builder.records(),
            expectations: builder.expectations()
        )
    }

    static func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(fixture())
    }
}

private struct HeavyHistoryThingSpec {
    let id: String
    let name: String
    let aliases: [String]
    let category: ThingCategory
    let keyword: String
    let createdAt: Date
    let updatedAt: Date
}

private extension HeavyHistorySeedScenarioGenerator {
    final class Builder {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let baseNow: Date
        let baseDay: Date
        let calendar: Calendar

        private let keywords = [
            "filter", "receipt", "permit", "garage", "garden", "medicine", "budget", "registration",
            "battery", "warranty", "inspection", "storage", "routine", "subscription", "repair"
        ]
        private let verbs = ["Changed", "Checked", "Cleaned", "Logged", "Moved", "Paid", "Filed", "Measured", "Replaced", "Scheduled", "Tested", "Updated"]
        private let objects = ["air filter", "storage label", "garden timer", "receipt folder", "garage shelf", "battery pack", "warranty note", "permit copy", "medicine list", "budget line", "registration card", "repair kit"]

        init() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = timeZone
            self.calendar = calendar
            self.baseNow = calendar.date(from: DateComponents(year: 2026, month: 5, day: 21, hour: 12, minute: 0, second: 0))!
            self.baseDay = calendar.startOfDay(for: baseNow)
        }

        func records() -> ExportRecords {
            let specs = thingSpecs()
            let events = eventRecords(things: specs)
            let notes = noteRecords(things: specs)
            let rules = ruleRecords(things: specs)
            let messages = messageRecords(things: specs)
            let reviewItems = reviewItemRecords(messages: messages, rules: rules)
            let links = entityLinkRecords(events: events, notes: notes, rules: rules)
            let things = thingRecords(from: specs, events: events)

            return ExportRecords(
                chatMessages: messages,
                extractionRuns: [],
                things: things,
                events: events,
                rules: rules,
                notes: notes,
                ledgerReviewItems: reviewItems,
                entityLinks: links
            )
        }

        func expectations() -> JSONValue {
            .object([
                "requiredCounts": .object([
                    "chatMessages": .number(208),
                    "extractionRuns": .number(0),
                    "things": .number(48),
                    "events": .number(312),
                    "rules": .number(96),
                    "notes": .number(128),
                    "ledgerReviewItems": .number(12),
                    "entityLinks": .number(120)
                ]),
                "requiredVisibleSurfaces": .array([
                    surface("log", ids: [uuid(.event, 0), uuid(.note, 0), uuid(.rule, 0), uuid(.message, 0)]),
                    surface("search", ids: [uuid(.event, 1), uuid(.note, 1), uuid(.rule, 1)]),
                    surface("reviewQueue", ids: [uuid(.reviewItem, 0)]),
                    surface("timelineReplay", ids: [uuid(.thing, 0), uuid(.event, 0)])
                ]),
                "relationshipChecks": .array([
                    relationship("thingHasEvent", fromType: "thing", from: uuid(.thing, 0), toType: "event", to: uuid(.event, 0)),
                    relationship("thingHasNote", fromType: "thing", from: uuid(.thing, 7), toType: "note", to: uuid(.note, 1)),
                    relationship("thingHasRule", fromType: "thing", from: uuid(.thing, 3), toType: "rule", to: uuid(.rule, 0)),
                    relationship("entityLinkExists", fromType: "event", from: uuid(.event, 0), toType: "thing", to: uuid(.thing, 0))
                ]),
                "searchExpectations": .array([
                    search("filter", targets: [.object(["type": .string("event"), "id": .string(uuid(.event, 0))])]),
                    search("receipt", targets: [.object(["type": .string("note"), "id": .string(uuid(.note, 1))])]),
                    search("garage", targets: [.object(["type": .string("rule"), "id": .string(uuid(.rule, 3))])])
                ]),
                "replayExpectations": .array([
                    .object([
                        "sourceType": .string("thing"),
                        "sourceId": .string(uuid(.thing, 0)),
                        "requiredText": .array(["filter", "Commuter Hatch"].map(JSONValue.string)),
                        "expectedTargets": .array([.object(["type": .string("event"), "id": .string(uuid(.event, 0))])])
                    ])
                ]),
                "reviewQueueExpectations": .array([
                    .object([
                        "kind": .string(LedgerReviewItemKind.extractionReview.rawValue),
                        "state": .string(LedgerReviewItemState.candidate.rawValue),
                        "targetType": .string(LedgerReviewItemTargetType.chatMessage.rawValue),
                        "targetId": .string(uuid(.message, 0)),
                        "requiredEvidenceIds": .array([.string(uuid(.message, 0))])
                    ])
                ])
            ])
        }

        func timestamp(_ date: Date) -> String {
            DateFormatting.string(
                from: date,
                format: "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                calendar: calendar,
                timeZone: timeZone
            )
        }

        private func thingSpecs() -> [HeavyHistoryThingSpec] {
            let names: [(String, ThingCategory)] = [
                ("Commuter Hatch", .vehicle), ("Blue Cargo Van", .vehicle), ("Basement Bike", .vehicle), ("Weekend Trailer", .vehicle),
                ("City Scooter", .vehicle), ("Roof Rack", .vehicle), ("Tool Cart", .vehicle), ("Cargo Bin", .vehicle),
                ("North Hall", .home), ("Garden Shed", .home), ("Utility Closet", .home), ("Laundry Nook", .home),
                ("Pantry Wall", .home), ("Guest Room", .home), ("Back Patio", .home), ("Entry Bench", .home),
                ("Basement Shelf", .home), ("Window Box", .home), ("Washer Unit", .homeMaintenance), ("Kitchen Chiller", .homeMaintenance),
                ("Desk Lamp Array", .homeMaintenance), ("Water Softener", .homeMaintenance), ("Porch Lights", .homeMaintenance), ("Air Handler", .homeMaintenance),
                ("Vacuum Dock", .homeMaintenance), ("Freezer Drawer", .homeMaintenance), ("Sleep Routine", .health), ("Stretch Plan", .health),
                ("Water Habit", .health), ("Medicine Cabinet", .health), ("Walk Loop", .health), ("Meal Prep", .health),
                ("Household Budget", .finance), ("Permit Folder", .finance), ("Receipt Box", .finance), ("Subscription List", .finance),
                ("Tax Drawer", .finance), ("Repair Fund", .finance), ("Porch Feeder", .pet), ("Travel Crate", .pet),
                ("Grooming Kit", .pet), ("Vet Folder", .pet), ("Spring Reset", .project), ("Archive Cleanup", .project),
                ("Garage Sort", .project), ("Garden Map", .project), ("Storage Audit", .project), ("Warranty Sweep", .project)
            ]
            return names.enumerated().map { index, value in
                let createdAt = historicalDate(index, stride: 19, phase: index % 11)
                return HeavyHistoryThingSpec(
                    id: uuid(.thing, index),
                    name: value.0,
                    aliases: ["hh \(value.0.lowercased())", "\(keywords[index % keywords.count]) tracker"],
                    category: value.1,
                    keyword: keywords[index % keywords.count],
                    createdAt: createdAt,
                    updatedAt: index % 4 == 0 ? add(.day, value: 20 + (index % 9), to: createdAt) : createdAt
                )
            }
        }

        private func eventRecords(things: [HeavyHistoryThingSpec]) -> [EventExport] {
            (0..<312).map { index in
                let thing = things[(index * 5) % things.count]
                let occurredAt = historicalDate(index, stride: 7, phase: index % 9)
                let createdAt = add(.minute, value: (index % 5) * 11, to: occurredAt)
                let title = "\(verbs[index % verbs.count]) \(objects[(index * 3) % objects.count])"
                return EventExport(
                    id: uuid(.event, index),
                    thingId: thing.id,
                    title: title,
                    eventType: eventType(index).rawValue,
                    rawText: "\(title) for \(thing.name). Reference code HH-E\(index). \(thing.keyword).",
                    occurredAt: dateOnly(occurredAt),
                    createdAt: timestamp(createdAt),
                    updatedAt: timestamp(index % 4 == 0 ? add(.minute, value: 23, to: createdAt) : createdAt),
                    note: index % 3 == 0 ? "Confirmed during weekly reset." : nil,
                    metadata: metadata(index),
                    source: source("event-\(index)")
                )
            }
        }

        private func noteRecords(things: [HeavyHistoryThingSpec]) -> [NoteExport] {
            (0..<128).map { index in
                let thing = things[(index * 7) % things.count]
                let createdAt = historicalDate(index, stride: 11, phase: index % 13)
                var linkedIDs = [thing.id]
                if index % 10 == 0 {
                    linkedIDs.append(things[(index * 7 + 5) % things.count].id)
                }
                return NoteExport(
                    id: uuid(.note, index),
                    text: "HH note \(index): \(keywords[index % keywords.count]) detail for \(thing.name). \(noteSentence(index))",
                    createdAt: timestamp(createdAt),
                    updatedAt: timestamp(index % 4 == 0 ? add(.hour, value: 2, to: createdAt) : createdAt),
                    linkedThingIds: linkedIDs,
                    source: source("note-\(index)")
                )
            }
        }

        private func ruleRecords(things: [HeavyHistoryThingSpec]) -> [RuleExport] {
            (0..<96).map { index in
                let thing = things[(index * 3) % things.count]
                let startsAt = ruleStartDate(index)
                let expiresAt = (72..<84).contains(index) ? add(.day, value: 14, to: startsAt) : nil
                let deactivatedAt = (48..<72).contains(index) ? add(.hour, value: 24 + (index % 4), to: startsAt) : nil
                return RuleExport(
                    id: uuid(.rule, index),
                    thingId: thing.id,
                    title: ruleTitle(index, thing: thing),
                    ruleType: LedgerRuleType.reminder.rawValue,
                    continuityBehavior: ruleBehavior(index, expiresAt: expiresAt).rawValue,
                    reason: "Keeps the recurring household check visible.",
                    startsAt: dateOnly(startsAt),
                    expiresAt: expiresAt.map(dateOnly),
                    createdAt: timestamp(ruleCreatedDate(index, startsAt: startsAt)),
                    updatedAt: timestamp(deactivatedAt ?? ruleCreatedDate(index, startsAt: startsAt)),
                    isActive: deactivatedAt == nil,
                    lifecycleState: deactivatedAt == nil ? LedgerRuleLifecycleState.open.rawValue : LedgerRuleLifecycleState.deactivated.rawValue,
                    manuallyDeactivatedAt: deactivatedAt.map(timestamp),
                    rawText: "Remind me to review \(keywords[index % keywords.count]) for \(thing.name). HH-R\(index).",
                    source: source("rule-\(index)")
                )
            }
        }

        private func messageRecords(things: [HeavyHistoryThingSpec]) -> [ChatMessageExport] {
            let reviewStatuses: [ExtractionStatus] = [.pending, .extracting, .pendingToken, .pendingRetry, .partiallySucceeded, .failed, .failedNeedsReview, .needsReview]
            let reviewMessages = (0..<72).map { index in
                message(index, role: .user, status: reviewStatuses[index % reviewStatuses.count], text: "HH review \(index): \(keywords[index % keywords.count]) entry for \(things[(index * 2) % things.count].name) needs review.", date: historicalDate(index, stride: 13, phase: index % 8))
            }
            let succeededStart = 72
            let succeeded = (succeededStart..<(succeededStart + 96)).map { index in
                let offset = index - succeededStart
                return message(index, role: .user, status: .succeeded, text: "HH handled \(offset): \(keywords[offset % keywords.count]) saved for \(things[(offset * 2) % things.count].name).", date: historicalDate(offset, stride: 13, phase: offset % 8))
            }
            let backgroundStart = succeededStart + 96
            let background = (backgroundStart..<(backgroundStart + 40)).map { index in
                let offset = index - backgroundStart
                let role: ChatRole = offset % 2 == 0 ? .assistant : .system
                return message(index, role: role, status: .notRequired, text: "HH background \(offset): \(keywords[offset % keywords.count]) archive status for \(things[(offset * 3) % things.count].name).", date: historicalDate(offset, stride: 13, phase: offset % 8))
            }
            return reviewMessages + succeeded + background
        }

        private func reviewItemRecords(messages: [ChatMessageExport], rules: [RuleExport]) -> [LedgerReviewItemExport] {
            (0..<12).map { index in
                let message = messages[index]
                let createdAt = historicalDate(index, stride: 13, phase: 3)
                return LedgerReviewItemExport(
                    id: uuid(.reviewItem, index),
                    kind: index % 2 == 0 ? LedgerReviewItemKind.extractionReview.rawValue : LedgerReviewItemKind.overdueReminderReview.rawValue,
                    state: LedgerReviewItemState.candidate.rawValue,
                    title: "Review heavy history entry \(index)",
                    detail: "Confirm the generated heavy-history reminder or extraction candidate.",
                    actionTitle: "Review",
                    targetType: index % 2 == 0 ? LedgerReviewItemTargetType.chatMessage.rawValue : LedgerReviewItemTargetType.rule.rawValue,
                    targetId: index % 2 == 0 ? message.id : rules[72 + index].id,
                    dedupeKey: "heavy_history_review_\(index)",
                    confidence: 0.82,
                    createdAt: timestamp(createdAt),
                    updatedAt: timestamp(createdAt),
                    presentedAt: nil,
                    resolvedAt: nil,
                    snoozedUntil: nil,
                    expiresAt: nil,
                    failureReason: nil,
                    evidence: [.init(sourceType: LedgerReviewItemTargetType.chatMessage.rawValue, sourceId: message.id, summary: message.text, detail: nil)]
                )
            }
        }

        private func entityLinkRecords(events: [EventExport], notes: [NoteExport], rules: [RuleExport]) -> [EntityLinkExport] {
            let eventLinks = (0..<70).map { link(index: $0, fromType: "event", from: events[$0].id, to: events[$0].thingId!) }
            let noteLinks = (0..<30).map { link(index: 70 + $0, fromType: "note", from: notes[$0].id, to: notes[$0].linkedThingIds[0]) }
            let ruleLinks = (0..<20).map { link(index: 100 + $0, fromType: "rule", from: rules[$0].id, to: rules[$0].thingId!) }
            return eventLinks + noteLinks + ruleLinks
        }

        private func thingRecords(from specs: [HeavyHistoryThingSpec], events: [EventExport]) -> [ThingExport] {
            specs.map { spec in
                let linkedDates = events.filter { $0.thingId == spec.id }.map(\.occurredAt).sorted()
                return ThingExport(
                    id: spec.id,
                    name: spec.name,
                    aliases: spec.aliases,
                    category: spec.category.rawValue,
                    createdAt: timestamp(spec.createdAt),
                    updatedAt: timestamp(spec.updatedAt),
                    lastEventAt: linkedDates.last,
                    eventCount: linkedDates.count,
                    source: ExportSource(kind: "manual")
                )
            }
        }

        private func message(_ index: Int, role: ChatRole, status: ExtractionStatus, text: String, date: Date) -> ChatMessageExport {
            ChatMessageExport(
                id: uuid(.message, index),
                role: role.rawValue,
                text: text,
                createdAt: timestamp(date),
                linkedEntityIds: [],
                extractionRunIds: [],
                latestExtractionRunId: nil,
                successfulExtractionRunIds: [],
                extractionState: .init(status: status.rawValue, errorCode: nil, errorMessage: nil, extractionVersion: 3, attemptCount: 0, lastAttemptAt: nil, nextRetryAt: nil, latestAttemptStatus: nil, latestAttemptErrorCode: nil, recoveryAction: nil)
            )
        }

        private func link(index: Int, fromType: String, from: String, to: String) -> EntityLinkExport {
            EntityLinkExport(id: uuid(.entityLink, index), fromEntityType: fromType, fromEntityId: from, toEntityType: "thing", toEntityId: to, relationship: "linked_to", createdAt: timestamp(baseNow), source: ExportSource(kind: "system"))
        }

        private func historicalDate(_ index: Int, stride: Int, phase: Int) -> Date {
            let dayOffset = -((index * stride + phase) % historyDays)
            let minuteOfDay = 6 * 60 + ((index * 37 + phase * 53) % (16 * 60))
            return add(.minute, value: minuteOfDay, to: add(.day, value: dayOffset, to: baseDay))
        }

        private func ruleStartDate(_ index: Int) -> Date {
            if index < 48 {
                let dayOffset = 1 + ((index * 5) % futureDays)
                let minute = 8 * 60 + ((index * 31) % (10 * 60))
                return add(.minute, value: minute, to: add(.day, value: dayOffset, to: baseDay))
            }
            if index < 72 {
                return historicalDate(index, stride: 17, phase: 2)
            }
            if index < 84 {
                return add(.hour, value: 9, to: add(.day, value: -(50 + index), to: baseDay))
            }
            return add(.hour, value: 10, to: add(.day, value: 46 + (index - 84) * 6, to: baseDay))
        }

        private func ruleCreatedDate(_ index: Int, startsAt: Date) -> Date {
            index < 48 ? add(.hour, value: 9, to: add(.day, value: -((index * 3) % 60), to: baseDay)) : add(.day, value: -14, to: startsAt)
        }

        private func dateOnly(_ date: Date) -> String {
            DateFormatting.dateOnlyString(date, calendar: calendar, timeZone: timeZone)
        }

        private func add(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
            calendar.date(byAdding: component, value: value, to: date)!
        }
    }
}

private extension HeavyHistorySeedScenarioGenerator.Builder {
    enum Namespace: UInt16 {
        case thing = 0x1001
        case event = 0x2001
        case note = 0x3001
        case rule = 0x4001
        case message = 0x5001
        case entityLink = 0x6001
        case reviewItem = 0x7001
    }

    func uuid(_ namespace: Namespace, _ index: Int) -> String {
        String(format: "00000000-0000-%04X-0000-%012X", namespace.rawValue, index)
    }

    func source(_ id: String) -> ExportSource {
        ExportSource(kind: "extracted", sourceClientId: "heavy-history-\(id)")
    }

    func eventType(_ index: Int) -> LedgerEventType {
        [.maintenance, .purchase, .visit, .replacement, .cleaning, .renewal, .appointment, .project, .measurement, .generic][index % 10]
    }

    func ruleBehavior(_ index: Int, expiresAt: Date?) -> LedgerContinuityBehavior {
        if expiresAt != nil { return .timeLimitedWindow }
        return index % 3 == 0 ? .dateBasedReminder : (index % 3 == 1 ? .recurringText : .ongoing)
    }

    func ruleTitle(_ index: Int, thing: HeavyHistoryThingSpec) -> String {
        if index < 48 { return "Review \(keywords[index % keywords.count]) for \(thing.name)" }
        if index < 72 { return "Complete \(keywords[index % keywords.count]) check" }
        if index < 84 { return "Review expired \(keywords[index % keywords.count]) window" }
        return "Future distant \(keywords[index % keywords.count]) check"
    }

    func noteSentence(_ index: Int) -> String {
        [
            "Keep this visible during the next reset.",
            "Stored the backup copy in the labeled folder.",
            "Use this when comparing the next update.",
            "Reviewed and kept the shorter version.",
            "Needs a second look before the next errand."
        ][index % 5]
    }

    func metadata(_ index: Int) -> [EventMetadataExport] {
        var values: [EventMetadataExport] = []
        if index % 4 == 0 {
            values.append(.init(key: LedgerEventMetadataKey.vendor.rawValue, valueKind: LedgerEventMetadataValueKind.string.rawValue, stringValue: "Local log", numberValue: nil, dateValue: nil, boolValue: nil, unit: nil, sourceText: "Local log"))
        }
        if index % 5 == 0 {
            values.append(.init(key: LedgerEventMetadataKey.quantity.rawValue, valueKind: LedgerEventMetadataValueKind.number.rawValue, stringValue: nil, numberValue: Double(10 + index % 90), dateValue: nil, boolValue: nil, unit: "count", sourceText: "\(10 + index % 90) count"))
        }
        if index % 7 == 0 {
            values.append(.init(key: LedgerEventMetadataKey.location.rawValue, valueKind: LedgerEventMetadataValueKind.string.rawValue, stringValue: "Zone \((index % 6) + 1)", numberValue: nil, dateValue: nil, boolValue: nil, unit: nil, sourceText: "Zone \((index % 6) + 1)"))
        }
        return values
    }

    func surface(_ name: String, ids: [String]) -> JSONValue {
        .object(["surface": .string(name), "requiredRecordIds": .array(ids.map(JSONValue.string))])
    }

    func relationship(_ kind: String, fromType: String, from: String, toType: String, to: String) -> JSONValue {
        .object(["kind": .string(kind), "fromType": .string(fromType), "fromId": .string(from), "toType": .string(toType), "toId": .string(to)])
    }

    func search(_ query: String, targets: [JSONValue]) -> JSONValue {
        .object(["query": .string(query), "expectedTargets": .array(targets), "disallowedText": .array([])])
    }
}
