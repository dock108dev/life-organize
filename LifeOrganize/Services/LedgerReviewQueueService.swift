import Foundation
import SwiftData

enum LedgerReviewCorrectionClass: String, Codable, CaseIterable {
    case quickReview = "quick_review"
    case mergeDuplicateThings = "merge_duplicate_things"
    case reassignRecordsToThing = "reassign_records_to_thing"
    case adjustReminderTiming = "adjust_reminder_timing"

    var title: String {
        switch self {
        case .quickReview:
            "Quick Review"
        case .mergeDuplicateThings:
            "Merge Duplicate Things"
        case .reassignRecordsToThing:
            "Reassign Items"
        case .adjustReminderTiming:
            "Adjust Reminder Timing"
        }
    }
}

struct LedgerReviewQueueEntry: Identifiable, Equatable {
    let itemID: UUID
    let title: String
    let detail: String
    let correctionClass: LedgerReviewCorrectionClass
    let primaryActionTitle: String
    let blockedMessage: String?
    let createdRecords: [LedgerReviewCreatedRecord]
    let origin: LedgerReviewOrigin?

    var id: UUID { itemID }
    var isActionBlocked: Bool { blockedMessage != nil }
}

struct LedgerReviewCreatedRecord: Identifiable, Equatable {
    let targetType: LedgerReviewItemTargetType
    let targetID: UUID
    let title: String
    let subtitle: String

    var id: String {
        "\(targetType.rawValue)-\(targetID.uuidString)"
    }
}

struct LedgerReviewOrigin: Equatable {
    let targetType: LedgerReviewItemTargetType
    let targetID: UUID
    let label: String
}

@MainActor
struct LedgerReviewQueueService {
    let modelContext: ModelContext
    let deviceTokenStore: any DeviceTokenStore
    var dateProvider: any DateProvider = AppRuntimeConfiguration.current.dateProvider
    var dataGeneration: UUID?
    var isDataGenerationCurrent: (UUID) -> Bool = { _ in true }
    var extractorFactory: (any DeviceTokenStore) -> any MessageExtractionClient = { deviceTokenStore in
        AppRuntimeConfiguration.current.messageExtractionClient(deviceTokenStore: deviceTokenStore)
    }

    func entries(
        from items: [LedgerReviewItem],
        origin: LedgerReviewOrigin? = nil,
        includeResolved: Bool = false
    ) throws -> [LedgerReviewQueueEntry] {
        try items
            .filter { includeResolved || $0.state.isAmbientlyVisible }
            .filter { item in
                guard let origin else { return true }
                return item.matches(origin: origin)
            }
            .map { try entry(for: $0, origin: origin) }
            .sorted(by: entryPrecedes)
    }

    func entry(for item: LedgerReviewItem, origin: LedgerReviewOrigin? = nil) throws -> LedgerReviewQueueEntry {
        let correctionClass = correctionClass(for: item)
        let blockedMessage = try blockedMessage(for: item, correctionClass: correctionClass)
        return LedgerReviewQueueEntry(
            itemID: item.id,
            title: item.title,
            detail: detail(for: item, correctionClass: correctionClass),
            correctionClass: correctionClass,
            primaryActionTitle: primaryActionTitle(for: item, correctionClass: correctionClass, blockedMessage: blockedMessage),
            blockedMessage: blockedMessage,
            createdRecords: try createdRecords(for: item),
            origin: origin
        )
    }

    func retryEntry(_ item: LedgerReviewItem) async throws {
        try ensureActionable(item)
        guard let message = try targetMessage(for: item) else {
            throw LedgerReviewQueueError.missingTarget
        }
        var service = ManualExtractionRetryService(
            modelContext: modelContext,
            deviceTokenStore: deviceTokenStore,
            dateProvider: dateProvider,
            dataGeneration: dataGeneration,
            isDataGenerationCurrent: isDataGenerationCurrent
        )
        service.extractorFactory = extractorFactory
        let retriedMessage = try await service.retry(message)
        guard (retriedMessage ?? message).extractionStatus.isReviewRetryResolved else {
            throw LedgerReviewQueueError.retryDidNotComplete
        }
        item.accept(at: dateProvider.now)
        try modelContext.save()
    }

    func dismiss(_ item: LedgerReviewItem) throws {
        try ensureActionable(item)
        item.dismiss(at: dateProvider.now)
        try modelContext.save()
    }

    func markReviewed(_ item: LedgerReviewItem) throws {
        try ensureActionable(item)
        item.accept(at: dateProvider.now)
        try modelContext.save()
    }

    func saveAsNote(_ item: LedgerReviewItem, body: String) throws -> LedgerNote {
        try ensureActionable(item)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw LedgerReviewQueueError.noActionableRecords
        }
        let message = try targetMessage(for: item)
        let linkedThings = try linkedNoteThings(for: item)
        let now = dateProvider.now
        let note = LedgerNote(
            text: trimmedBody,
            createdAt: now,
            updatedAt: now,
            sourceMessage: message,
            linkedThings: linkedThings
        )
        try DerivedFieldMaintenanceService(modelContext: modelContext, now: { now }).insertNote(note)
        item.accept(at: now)
        try modelContext.save()
        return note
    }

    func mergeDuplicateThings(for item: LedgerReviewItem, into targetID: UUID) throws {
        try ensureActionable(item)
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        guard let target = things.first(where: { $0.id == targetID }) else {
            throw LedgerReviewQueueError.missingTarget
        }
        let sourceIDs = item.evidence
            .filter { $0.sourceType == .thing && $0.sourceID != targetID }
            .map(\.sourceID)
        let sources = sourceIDs.compactMap { id in things.first { $0.id == id } }
        guard !sources.isEmpty else {
            throw LedgerReviewQueueError.noActionableRecords
        }

        let maintenance = DerivedFieldMaintenanceService(modelContext: modelContext, now: { dateProvider.now })
        for source in sources {
            try maintenance.mergeThing(source, into: target)
        }
        item.accept(at: dateProvider.now)
        try modelContext.save()
    }

    func reassignRecords(from item: LedgerReviewItem, to targetID: UUID) throws {
        try ensureActionable(item)
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        guard let target = things.first(where: { $0.id == targetID }) else {
            throw LedgerReviewQueueError.missingTarget
        }
        let maintenance = DerivedFieldMaintenanceService(modelContext: modelContext, now: { dateProvider.now })
        var changed = false

        let evidenceRecords = item.evidence
        var mergedThingIDs: [UUID] = []
        for evidence in evidenceRecords where evidence.sourceID != targetID {
            switch evidence.sourceType {
            case .event:
                if let event = try fetch(LedgerEvent.self, id: evidence.sourceID) {
                    try maintenance.reassignEvent(event, to: target)
                    changed = true
                }
            case .rule:
                if let rule = try fetch(LedgerRule.self, id: evidence.sourceID) {
                    try maintenance.reassignRule(rule, to: target)
                    changed = true
                }
            case .thing:
                if let source = things.first(where: { $0.id == evidence.sourceID }), source.id != target.id {
                    try maintenance.mergeThing(source, into: target)
                    mergedThingIDs.append(source.id)
                    changed = true
                }
            case .none:
                if let note = try fetch(LedgerNote.self, id: evidence.sourceID) {
                    try maintenance.reassignNote(note, to: target)
                    changed = true
                }
            case .chatMessage:
                break
            }
        }

        guard changed else {
            throw LedgerReviewQueueError.noActionableRecords
        }
        for sourceID in mergedThingIDs {
            retargetReviewReferences(on: item, from: sourceID, to: target.id)
        }
        item.accept(at: dateProvider.now)
        try modelContext.save()
    }

    func adjustReminderTiming(for item: LedgerReviewItem, startsAt: Date, expiresAt: Date? = nil) throws {
        try ensureActionable(item)
        guard let rule = try targetRule(for: item) else {
            throw LedgerReviewQueueError.missingTarget
        }
        let updatedAt = dateProvider.now
        let maintenance = DerivedFieldMaintenanceService(modelContext: modelContext, now: { updatedAt })
        if let expiresAt {
            rule.startsAt = DateFormatting.normalizedDateOnly(startsAt)
            try ReminderRuleLifecycleMutation.setEndDate(rule, to: expiresAt, at: updatedAt, maintenance: maintenance)
        } else {
            try ReminderRuleLifecycleMutation.moveDueDate(rule, to: startsAt, at: updatedAt, maintenance: maintenance)
        }
        item.accept(at: updatedAt)
        try modelContext.save()
    }

    private func correctionClass(for item: LedgerReviewItem) -> LedgerReviewCorrectionClass {
        switch item.kind {
        case .duplicateThing:
            .mergeDuplicateThings
        case .normalizationCandidate:
            .reassignRecordsToThing
        case .overdueReminderReview, .intervalReminder:
            .adjustReminderTiming
        case .localRecovery, .extractionReview, .conflictingDate:
            .quickReview
        }
    }

    private func detail(for item: LedgerReviewItem, correctionClass: LedgerReviewCorrectionClass) -> String {
        switch correctionClass {
        case .quickReview, .mergeDuplicateThings, .reassignRecordsToThing, .adjustReminderTiming:
            item.detail
        }
    }

    private func primaryActionTitle(
        for item: LedgerReviewItem,
        correctionClass: LedgerReviewCorrectionClass,
        blockedMessage: String?
    ) -> String {
        if let actionTitle = item.actionTitle?.nilIfEmpty {
            return actionTitle
        }
        if blockedMessage != nil {
            return "Review Details"
        }
        switch correctionClass {
        case .quickReview:
            return "Mark reviewed"
        case .mergeDuplicateThings:
            return "Merge Things"
        case .reassignRecordsToThing:
            return "Reassign"
        case .adjustReminderTiming:
            return "Adjust Timing"
        }
    }

    private func blockedMessage(
        for item: LedgerReviewItem,
        correctionClass: LedgerReviewCorrectionClass
    ) throws -> String? {
        guard correctionClass == .quickReview, let message = try targetMessage(for: item) else {
            return nil
        }
        if let reason = try ManualExtractionRetryService(modelContext: modelContext, deviceTokenStore: deviceTokenStore).canRetry(message) {
            return reason.message
        }
        if try deviceTokenStore.ensureDeviceToken().isEmpty {
            return ManualExtractionRetryError.missingServiceToken.errorDescription
        }
        return nil
    }

    private func createdRecords(for item: LedgerReviewItem) throws -> [LedgerReviewCreatedRecord] {
        guard let message = try targetMessage(for: item), message.extractionStatus == .partiallySucceeded else {
            return []
        }
        let attempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
            .filter { $0.sourceMessage?.id == message.id }
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
        let notes = try modelContext.fetch(FetchDescriptor<LedgerNote>())

        var records: [LedgerReviewCreatedRecord] = []
        for attempt in attempts {
            records.append(contentsOf: attempt.createdThingIDs.compactMap { id in
                things.first { $0.id == id }.map { record(.thing, id: id, title: $0.name, subtitle: "Thing") }
            })
            records.append(contentsOf: attempt.createdEventIDs.compactMap { id in
                events.first { $0.id == id }.map { record(.event, id: id, title: $0.title, subtitle: "Event") }
            })
            records.append(contentsOf: attempt.createdRuleIDs.compactMap { id in
                rules.first { $0.id == id }.map { record(.rule, id: id, title: $0.title, subtitle: "Reminder") }
            })
            records.append(contentsOf: attempt.createdNoteIDs.compactMap { id in
                notes.first { $0.id == id }.map { record(.none, id: id, title: $0.text, subtitle: "Note") }
            })
        }

        var seen = Set<String>()
        return records.filter { seen.insert($0.id).inserted }
    }

    private func record(
        _ targetType: LedgerReviewItemTargetType,
        id: UUID,
        title: String,
        subtitle: String
    ) -> LedgerReviewCreatedRecord {
        LedgerReviewCreatedRecord(targetType: targetType, targetID: id, title: title, subtitle: subtitle)
    }

    private func retargetReviewReferences(on item: LedgerReviewItem, from sourceID: UUID, to targetID: UUID) {
        if item.targetType == .thing, item.targetID == sourceID {
            item.targetID = targetID
        }
        item.evidence = item.evidence.map { evidence in
            guard evidence.sourceType == .thing, evidence.sourceID == sourceID else { return evidence }
            return LedgerReviewItemEvidence(
                sourceType: evidence.sourceType,
                sourceID: targetID,
                summary: evidence.summary,
                detail: evidence.detail
            )
        }
    }

    private func targetMessage(for item: LedgerReviewItem) throws -> ChatMessage? {
        guard item.targetType == .chatMessage, let targetID = item.targetID else { return nil }
        return try fetch(ChatMessage.self, id: targetID)
    }

    private func linkedNoteThings(for item: LedgerReviewItem) throws -> [Thing] {
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        var ids: [UUID] = []
        if item.targetType == .thing, let targetID = item.targetID {
            ids.append(targetID)
        }
        ids.append(contentsOf: item.evidence.filter { $0.sourceType == .thing }.map(\.sourceID))

        var seen = Set<UUID>()
        return ids
            .filter { seen.insert($0).inserted }
            .compactMap { id in things.first { $0.id == id } }
    }

    func targetRule(for item: LedgerReviewItem) throws -> LedgerRule? {
        if item.targetType == .rule, let targetID = item.targetID {
            return try fetch(LedgerRule.self, id: targetID)
        }
        guard let ruleEvidence = item.evidence.first(where: { $0.sourceType == .rule }) else {
            return nil
        }
        return try fetch(LedgerRule.self, id: ruleEvidence.sourceID)
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, id: UUID) throws -> T? {
        _ = type
        return try modelContext.fetch(FetchDescriptor<T>()).first { model in
            guard let identifiable = model as? any ReviewQueueIdentifiableModel else { return false }
            return identifiable.reviewQueueID == id
        }
    }

    private func entryPrecedes(_ lhs: LedgerReviewQueueEntry, _ rhs: LedgerReviewQueueEntry) -> Bool {
        if lhs.isActionBlocked != rhs.isActionBlocked {
            return !lhs.isActionBlocked
        }
        if lhs.correctionClass != rhs.correctionClass {
            return lhs.correctionClass.sortOrder < rhs.correctionClass.sortOrder
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

enum LedgerReviewQueueError: LocalizedError, Equatable {
    case missingTarget
    case noActionableRecords
    case actionUnavailable
    case unsupportedAction
    case retryDidNotComplete

    var errorDescription: String? {
        switch self {
        case .missingTarget:
            "The saved item could not be found."
        case .noActionableRecords:
            "There are no saved items available for this review action."
        case .actionUnavailable:
            "This review item has already been updated."
        case .unsupportedAction:
            "This review item does not have that action."
        case .retryDidNotComplete:
            "Retry did not finish connecting this entry. The review item is still open."
        }
    }
}

private extension ExtractionStatus {
    var isReviewRetryResolved: Bool {
        switch self {
        case .succeeded, .notRequired:
            return true
        case .pending, .extracting, .pendingToken, .pendingRetry, .partiallySucceeded, .failed, .failedNeedsReview,
             .needsReview:
            return false
        }
    }
}

private protocol ReviewQueueIdentifiableModel {
    var reviewQueueID: UUID { get }
}

extension ChatMessage: ReviewQueueIdentifiableModel {
    var reviewQueueID: UUID { id }
}

extension Thing: ReviewQueueIdentifiableModel {
    var reviewQueueID: UUID { id }
}

extension LedgerEvent: ReviewQueueIdentifiableModel {
    var reviewQueueID: UUID { id }
}

extension LedgerRule: ReviewQueueIdentifiableModel {
    var reviewQueueID: UUID { id }
}

extension LedgerNote: ReviewQueueIdentifiableModel {
    var reviewQueueID: UUID { id }
}

private extension LedgerReviewCorrectionClass {
    var sortOrder: Int {
        switch self {
        case .quickReview:
            0
        case .adjustReminderTiming:
            1
        case .mergeDuplicateThings:
            2
        case .reassignRecordsToThing:
            3
        }
    }
}

private extension LedgerReviewItem {
    func matches(origin: LedgerReviewOrigin) -> Bool {
        if targetType == origin.targetType, targetID == origin.targetID {
            return true
        }
        return evidence.contains { evidence in
            evidence.sourceType == origin.targetType && evidence.sourceID == origin.targetID
        }
    }
}
