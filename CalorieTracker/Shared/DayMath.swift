import Foundation

enum DayMath {
    /// Same clock time on `day`, for copying a past entry forward.
    static func move(_ date: Date, toDay day: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0,
                             of: day) ?? day
    }

    /// kcal per day for the `count` days ending on `lastDay`, oldest first, zero-filled.
    static func dailyTotals(_ entries: [(date: Date, kcal: Double)], endingOn lastDay: Date, count: Int,
                            calendar: Calendar = .current) -> [(day: Date, kcal: Double)] {
        let end = calendar.startOfDay(for: lastDay)
        var sums: [Date: Double] = [:]
        for entry in entries { sums[calendar.startOfDay(for: entry.date), default: 0] += entry.kcal }
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map { ($0, sums[$0] ?? 0) }
        }
    }

    /// Days in a row with something logged, counting back from today. Today not being logged yet
    /// doesn't break the streak until the day is over, so it counts back from yesterday instead.
    static func streak(loggedDays: Set<Date>, today: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(loggedDays.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
