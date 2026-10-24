import Foundation

/// Smooths noisy daily weigh-ins into a trend, the way a moving average hides water swings.
///
/// Each day's weight pulls the trend 10% of the way towards it. Missed days count as the trend
/// staying put, so a gap of n days pulls by 1 - 0.9^n when the next weigh-in arrives.
enum WeightTrend {
    struct Point: Equatable, Sendable {
        /// Start of the day.
        var day: Date
        /// That day's weigh-in, averaged when there were several.
        var weight: Double
        var trend: Double
    }

    static let smoothing = 0.1

    static func points(_ weighIns: [(date: Date, kilograms: Double)], calendar: Calendar = .current) -> [Point] {
        var byDay: [Date: (sum: Double, count: Int)] = [:]
        for weighIn in weighIns where weighIn.kilograms > 0 {
            let day = calendar.startOfDay(for: weighIn.date)
            byDay[day, default: (0, 0)].sum += weighIn.kilograms
            byDay[day, default: (0, 0)].count += 1
        }
        var result: [Point] = []
        for day in byDay.keys.sorted() {
            guard let entry = byDay[day] else { continue }
            let weight = entry.sum / Double(entry.count)
            guard let last = result.last else {
                result.append(Point(day: day, weight: weight, trend: weight))
                continue
            }
            let gap = max(calendar.dateComponents([.day], from: last.day, to: day).day ?? 1, 1)
            let pull = 1 - pow(1 - smoothing, Double(gap))
            result.append(Point(day: day, weight: weight, trend: last.trend + pull * (weight - last.trend)))
        }
        return result
    }

    /// kg per week from a least-squares line through the trend over the last `days` days.
    /// Nil with fewer than two points or less than a week of data in that window.
    static func weeklyRate(_ points: [Point], days: Int = 28, calendar: Calendar = .current) -> Double? {
        guard let lastDay = points.last?.day,
              let start = calendar.date(byAdding: .day, value: -days, to: lastDay) else { return nil }
        let window = points.filter { $0.day >= start }
        guard window.count >= 2, let first = window.first?.day,
              lastDay.timeIntervalSince(first) >= 6 * 86_400 else { return nil }
        let xs = window.map { $0.day.timeIntervalSince(first) / 86_400 }
        let ys = window.map(\.trend)
        let n = Double(window.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let numerator = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominator = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard denominator > 0 else { return nil }
        return numerator / denominator * 7
    }
}
