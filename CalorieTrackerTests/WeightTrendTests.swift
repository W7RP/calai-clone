import Foundation
import Testing
@testable import CalorieTracker

struct WeightTrendTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func firstWeighInStartsTheTrend() {
        let points = WeightTrend.points([(date(1), 80)], calendar: calendar)
        #expect(points == [WeightTrend.Point(day: date(1, 0), weight: 80, trend: 80)])
    }

    @Test func eachDayPullsTenPercent() {
        let points = WeightTrend.points([(date(1), 80), (date(2), 81)], calendar: calendar)
        #expect(abs(points[1].trend - 80.1) < 0.0001)
    }

    @Test func gapsPullHarder() {
        // Three days later: 1 - 0.9^3 = 0.271 of the way.
        let points = WeightTrend.points([(date(1), 80), (date(4), 81)], calendar: calendar)
        #expect(abs(points[1].trend - 80.271) < 0.0001)
    }

    @Test func sameDayWeighInsAreAveraged() {
        let points = WeightTrend.points([(date(1, 7), 80), (date(1, 21), 81), (date(2), 0)], calendar: calendar)
        #expect(points.count == 1)
        #expect(points[0].weight == 80.5)
    }

    @Test func unsortedInputIsSorted() {
        let points = WeightTrend.points([(date(3), 79), (date(1), 80)], calendar: calendar)
        #expect(points.map(\.day) == [date(1, 0), date(3, 0)])
    }

    @Test func weeklyRateFollowsASteadyLoss() {
        let points = (0..<28).map { WeightTrend.Point(day: date(1 + $0, 0), weight: 0, trend: 90 - Double($0) * 0.1) }
        let rate = WeightTrend.weeklyRate(points, calendar: calendar)
        #expect(rate.map { abs($0 + 0.7) < 0.0001 } == true)
    }

    @Test func weeklyRateNeedsAWeek() {
        let points = (0..<4).map { WeightTrend.Point(day: date(1 + $0, 0), weight: 0, trend: 90) }
        #expect(WeightTrend.weeklyRate(points, calendar: calendar) == nil)
    }
}
