import Foundation

enum OpenAIUserPayload {
    static func string(for text: String, now: Date, timeZone: TimeZone) -> String {
        """
        {
          "currentDate": "\(DateFormatting.gregorianDateOnlyString(now, timeZone: timeZone))",
          "currentDateTime": "\(DateFormatting.isoDateTimeString(now, timeZone: timeZone))",
          "timezone": "\(timeZone.identifier)",
          "locale": "en-US",
          "userMessage": \(jsonStringLiteral(text))
        }
        """
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
        return String(data: data, encoding: .utf8) ?? #""""#
    }
}
