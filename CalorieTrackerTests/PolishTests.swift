import Foundation
import Testing
@testable import CalorieTracker

struct CSVExportTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func writesHeaderAndSortedRows() {
        let rows = [
            CSVExport.Row(date: date(23, 12, 5), meal: "lunch", food: "Soupe, pois", grams: 250,
                          macros: Macros(kcal: 180.04, protein: 9.25, carbs: 24, fat: 4), source: "manual"),
            CSVExport.Row(date: date(23, 7, 30), meal: "breakfast", food: "Toast \"brown\"", grams: 35,
                          macros: Macros(kcal: 90, protein: 3, carbs: 17, fat: 1), source: "ai"),
        ]
        let lines = CSVExport.csv(rows, timeZone: utc).split(separator: "\n").map(String.init)
        #expect(lines[0] == CSVExport.header)
        #expect(lines[1] == #"2026-10-23,07:30,breakfast,"Toast ""brown""",35,90,3,17,1,ai"#)
        #expect(lines[2] == #"2026-10-23,12:05,lunch,"Soupe, pois",250,180,9.3,24,4,manual"#)
    }

    @Test func plainFieldsAreNotQuoted() {
        #expect(CSVExport.escape("Apple") == "Apple")
        #expect(CSVExport.escape("a\nb") == "\"a\nb\"")
    }
}

struct DayMathTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func moveKeepsClockTime() {
        let moved = DayMath.move(date(22, 8, 15), toDay: date(23), calendar: calendar)
        #expect(moved == date(23, 8, 15))
    }

    @Test func dailyTotalsZeroFillsOldestFirst() {
        let entries = [(date: date(21, 9), kcal: 300.0), (date: date(21, 19), kcal: 500.0), (date: date(23, 8), kcal: 200.0)]
        let totals = DayMath.dailyTotals(entries, endingOn: date(23, 22), count: 3, calendar: calendar)
        #expect(totals.map(\.kcal) == [800, 0, 200])
        #expect(totals.first?.day == date(21))
    }

    @Test func streakCountsBackFromToday() {
        let logged: Set<Date> = [date(20, 9), date(21, 13), date(22, 20), date(23, 8)]
        #expect(DayMath.streak(loggedDays: logged, today: date(23, 21), calendar: calendar) == 4)
    }

    @Test func streakSurvivesTodayNotLoggedYet() {
        let logged: Set<Date> = [date(21), date(22)]
        #expect(DayMath.streak(loggedDays: logged, today: date(23, 10), calendar: calendar) == 2)
    }

    @Test func streakBreaksOnAMissedDay() {
        let logged: Set<Date> = [date(19), date(20), date(22), date(23)]
        #expect(DayMath.streak(loggedDays: logged, today: date(23), calendar: calendar) == 2)
        #expect(DayMath.streak(loggedDays: [date(20)], today: date(23), calendar: calendar) == 0)
    }
}
