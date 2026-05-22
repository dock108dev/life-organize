import Foundation

struct LocalSearchTimingParseResult {
    let dateRange: TimelineSliceDateRange?
    let remainingText: String
    let rangeTitle: String?
}

struct LocalSearchTimingParser {
    let calendar: Calendar
    let now: Date

    func parse(_ rawText: String) -> LocalSearchTimingParseResult {
        let normalized = SearchService.normalizeForLocalSearch(rawText)
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return LocalSearchTimingParseResult(dateRange: nil, remainingText: rawText, rangeTitle: nil)
        }

        if let result = parseSinceMonth(words) {
            return result
        }
        if let result = parseRelativePhrase(words) {
            return result
        }
        if let result = parseMonthYear(words) {
            return result
        }
        if let result = parseYear(words) {
            return result
        }

        return LocalSearchTimingParseResult(dateRange: nil, remainingText: rawText, rangeTitle: nil)
    }

    private func parseSinceMonth(_ words: [String]) -> LocalSearchTimingParseResult? {
        for index in words.indices where words[index] == "since" || words[index] == "from" {
            let monthIndex = words.index(after: index)
            guard monthIndex < words.endIndex, let month = Self.monthNumber(for: words[monthIndex]) else { continue }
            let yearIndex = words.index(after: monthIndex)
            let explicitYear = yearIndex < words.endIndex ? Int(words[yearIndex]) : nil
            let currentYear = calendar.component(.year, from: now)
            var year = explicitYear ?? currentYear
            guard var start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { continue }
            if explicitYear == nil, start > now, let previousYearStart = calendar.date(from: DateComponents(year: year - 1, month: month, day: 1)) {
                year -= 1
                start = previousYearStart
            }

            let endIndex = explicitYear == nil ? yearIndex : words.index(after: yearIndex)
            let remaining = words.removingSubrange(index..<min(endIndex, words.endIndex))
            let title = "Since \(Self.monthName(month, year: year, includeYear: explicitYear != nil))"
            return LocalSearchTimingParseResult(
                dateRange: TimelineSliceDateRange.since(start, through: now, calendar: calendar),
                remainingText: remaining,
                rangeTitle: title
            )
        }
        return nil
    }

    private func parseRelativePhrase(_ words: [String]) -> LocalSearchTimingParseResult? {
        let phrases: [([String], () -> (TimelineSliceDateRange, String)?)] = [
            (["today"], todayRange),
            (["yesterday"], yesterdayRange),
            (["this", "week"], thisWeekRange),
            (["last", "week"], lastWeekRange),
            (["this", "month"], thisMonthRange),
            (["last", "month"], lastMonthRange),
            (["this", "year"], thisYearRange),
            (["last", "year"], lastYearRange),
            (["upcoming"], upcomingRange)
        ]

        for (phrase, builder) in phrases {
            guard let range = words.range(ofSubsequence: phrase), let built = builder() else { continue }
            return LocalSearchTimingParseResult(
                dateRange: built.0,
                remainingText: words.removingSubrange(range),
                rangeTitle: built.1
            )
        }
        return nil
    }

    private func parseMonthYear(_ words: [String]) -> LocalSearchTimingParseResult? {
        for index in words.indices {
            guard let month = Self.monthNumber(for: words[index]) else { continue }
            let next = words.index(after: index)
            guard next < words.endIndex, let year = Int(words[next]), (1900...2100).contains(year),
                  let range = TimelineSliceDateRange.month(year: year, month: month, calendar: calendar)
            else { continue }
            return LocalSearchTimingParseResult(
                dateRange: range,
                remainingText: words.removingSubrange(index..<words.index(after: next)),
                rangeTitle: Self.monthName(month, year: year, includeYear: true)
            )
        }
        return nil
    }

    private func parseYear(_ words: [String]) -> LocalSearchTimingParseResult? {
        for index in words.indices {
            guard let year = Int(words[index]), (1900...2100).contains(year),
                  let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            else { continue }
            return LocalSearchTimingParseResult(
                dateRange: TimelineSliceDateRange(start: calendar.startOfDay(for: start), endExclusive: calendar.startOfDay(for: end)),
                remainingText: words.removingSubrange(index..<words.index(after: index)),
                rangeTitle: "\(year)"
            )
        }
        return nil
    }

    private func todayRange() -> (TimelineSliceDateRange, String)? {
        dayRange(containing: now).map { ($0, "Today") }
    }

    private func yesterdayRange() -> (TimelineSliceDateRange, String)? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return dayRange(containing: yesterday).map { ($0, "Yesterday") }
    }

    private func thisWeekRange() -> (TimelineSliceDateRange, String)? {
        dateIntervalRange(.weekOfYear, containing: now).map { ($0, "This Week") }
    }

    private func lastWeekRange() -> (TimelineSliceDateRange, String)? {
        guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else { return nil }
        return dateIntervalRange(.weekOfYear, containing: lastWeek).map { ($0, "Last Week") }
    }

    private func thisMonthRange() -> (TimelineSliceDateRange, String)? {
        dateIntervalRange(.month, containing: now).map { ($0, "This Month") }
    }

    private func lastMonthRange() -> (TimelineSliceDateRange, String)? {
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        return dateIntervalRange(.month, containing: lastMonth).map { ($0, "Last Month") }
    }

    private func thisYearRange() -> (TimelineSliceDateRange, String)? {
        dateIntervalRange(.year, containing: now).map { ($0, "This Year") }
    }

    private func lastYearRange() -> (TimelineSliceDateRange, String)? {
        guard let lastYear = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }
        return dateIntervalRange(.year, containing: lastYear).map { ($0, "Last Year") }
    }

    private func upcomingRange() -> (TimelineSliceDateRange, String)? {
        (TimelineSliceDateRange(start: now, endExclusive: .distantFuture), "Upcoming")
    }

    private func dayRange(containing date: Date) -> TimelineSliceDateRange? {
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return nil }
        return TimelineSliceDateRange(start: calendar.startOfDay(for: date), endExclusive: end)
    }

    private func dateIntervalRange(_ component: Calendar.Component, containing date: Date) -> TimelineSliceDateRange? {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
        return TimelineSliceDateRange(start: interval.start, endExclusive: interval.end)
    }

    private static func monthNumber(for word: String) -> Int? {
        let months = [
            "january": 1, "jan": 1,
            "february": 2, "feb": 2,
            "march": 3, "mar": 3,
            "april": 4, "apr": 4,
            "may": 5,
            "june": 6, "jun": 6,
            "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sep": 9, "sept": 9,
            "october": 10, "oct": 10,
            "november": 11, "nov": 11,
            "december": 12, "dec": 12
        ]
        return months[word]
    }

    private static func monthName(_ month: Int, year: Int, includeYear: Bool) -> String {
        let names = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        let name = names[month - 1]
        return includeYear ? "\(name) \(year)" : name
    }
}

private extension Array where Element == String {
    func range(ofSubsequence subsequence: [String]) -> Range<Int>? {
        guard !subsequence.isEmpty, subsequence.count <= count else { return nil }
        for start in 0...(count - subsequence.count) {
            let end = start + subsequence.count
            if Array(self[start..<end]) == subsequence {
                return start..<end
            }
        }
        return nil
    }

    func removingSubrange(_ range: Range<Int>) -> String {
        enumerated()
            .filter { !range.contains($0.offset) }
            .map(\.element)
            .joined(separator: " ")
    }
}
