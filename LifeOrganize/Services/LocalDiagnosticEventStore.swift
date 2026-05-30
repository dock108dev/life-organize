import Foundation

struct LocalDiagnosticEvent: Codable, Equatable, Identifiable {
    enum Severity: String, Codable {
        case info
        case warning
        case error
    }

    let id: UUID
    let createdAt: Date
    let severity: Severity
    let category: String
    let operation: String
    let errorKind: String
    let affectedRecordID: UUID?
    let metadata: [String: String]
}

struct LocalDiagnosticEventStore {
    private static let storageKey = "LocalDiagnosticEventStore.events"
    private static let blockedMetadataKeys = Set([
        "apikey",
        "authorization",
        "cookie",
        "devicetoken",
        "input",
        "outputtext",
        "payload",
        "prompt",
        "rawresponse",
        "rawresponsetext",
        "requestjson",
        "response",
        "session",
        "text",
        "token",
        "usertext"
    ])

    var defaults: UserDefaults = .standard
    var now: () -> Date = { Date() }
    var maxEvents: Int = 200

    func record(
        severity: LocalDiagnosticEvent.Severity,
        category: String,
        operation: String,
        error: Error,
        affectedRecordID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        record(
            severity: severity,
            category: category,
            operation: operation,
            errorKind: String(describing: type(of: error)),
            affectedRecordID: affectedRecordID,
            metadata: metadata
        )
    }

    func record(
        severity: LocalDiagnosticEvent.Severity,
        category: String,
        operation: String,
        errorKind: String,
        affectedRecordID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        var events = load()
        events.append(
            LocalDiagnosticEvent(
                id: UUID(),
                createdAt: now(),
                severity: severity,
                category: category,
                operation: operation,
                errorKind: sanitize(errorKind),
                affectedRecordID: affectedRecordID,
                metadata: sanitizedMetadata(metadata)
            )
        )
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        save(events)
    }

    func load() -> [LocalDiagnosticEvent] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let events = try? JSONDecoder().decode([LocalDiagnosticEvent].self, from: data) else {
            return []
        }
        return events
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save(_ events: [LocalDiagnosticEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, pair in
            guard !Self.blockedMetadataKeys.contains(normalizedKey(pair.key)) else {
                result[pair.key] = "[redacted]"
                return
            }
            result[pair.key] = sanitize(pair.value)
        }
    }

    private func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else { return trimmed }
        return "\(trimmed.prefix(150))...[truncated]"
    }

    private func normalizedKey(_ key: String) -> String {
        String(key.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
