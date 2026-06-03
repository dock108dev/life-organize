import XCTest
@testable import LifeOrganize

extension LedgerFeedProjectionTests {
    static var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    static func timeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

extension LedgerFeedItem {
    var messageText: String? {
        if case .message(let message) = self {
            return message.text
        }
        return nil
    }
}

extension Array where Element == LedgerFeedItem {
    func containsMessage(_ message: ChatMessage) -> Bool {
        contains { item in
            if case .message(let itemMessage) = item {
                return itemMessage.id == message.id
            }
            return false
        }
    }

    func containsEvent(_ event: LedgerEvent) -> Bool {
        contains { item in
            if case .event(let itemEvent) = item {
                return itemEvent.id == event.id
            }
            return false
        }
    }

    func containsReminder(_ reminder: LedgerRule) -> Bool {
        contains { item in
            if case .reminder(let itemReminder) = item {
                return itemReminder.id == reminder.id
            }
            return false
        }
    }

    func containsNote(_ note: LedgerNote) -> Bool {
        contains { item in
            if case .note(let itemNote) = item {
                return itemNote.id == note.id
            }
            return false
        }
    }
}
