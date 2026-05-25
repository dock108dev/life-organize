import Foundation

enum SecretRedactor {
    static let replacement = "[REDACTED_SECRET]"

    static func redact(_ value: String?) -> String? {
        value.map(redact)
    }

    static func redact(_ value: String) -> String {
        var redacted = value
        for pattern in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern.expression,
                with: pattern.replacement,
                options: .regularExpression
            )
        }
        return redacted
    }

    private static let patterns: [(expression: String, replacement: String)] = [
        (#"(?i)"authorization"\s*:\s*"[^"]*""#, #""redactedSecret":"\#(replacement)""#),
        (#"(?i)"x-lifeorganize-device-token"\s*:\s*"[^"]*""#, #""redactedSecret":"\#(replacement)""#),
        (#"(?i)"api[_ -]?key"\s*:\s*"[^"]*""#, #""redactedSecret":"\#(replacement)""#),
        (#"(?i)authorization:\s*bearer\s+[A-Za-z0-9._\-]+"#, replacement),
        (#"(?i)x-lifeorganize-device-token:\s*[A-Za-z0-9._\-]+"#, replacement),
        (#"(?i)bearer\s+[A-Za-z0-9._\-]+"#, replacement),
        (#"sk-[A-Za-z0-9_\-]{8,}"#, replacement),
        (#"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, replacement)
    ]
}
