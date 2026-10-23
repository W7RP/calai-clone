import Foundation
import Testing
@testable import CalorieTracker

private func close(_ a: Macros, _ b: Macros) -> Bool {
    abs(a.kcal - b.kcal) < 1e-9 && abs(a.protein - b.protein) < 1e-9
        && abs(a.carbs - b.carbs) < 1e-9 && abs(a.fat - b.fat) < 1e-9
}

struct MacrosTests {
    @Test func scalesPer100gToAmount() {
        let per100 = Macros(kcal: 250, protein: 10, carbs: 30, fat: 8)
        #expect(close(per100.forGrams(40), Macros(kcal: 100, protein: 4, carbs: 12, fat: 3.2)))
    }

    @Test func amountToPer100gRoundTrips() throws {
        let eaten = Macros(kcal: 180, protein: 12, carbs: 3, fat: 13.5)
        let per100 = try #require(eaten.per100g(fromGrams: 150))
        #expect(abs(per100.kcal - 120) < 1e-9)
        let back = per100.forGrams(150)
        #expect(abs(back.fat - 13.5) < 0.0001)
    }

    @Test func zeroGramsHasNoPer100g() {
        #expect(Macros(kcal: 50, protein: 0, carbs: 0, fat: 0).per100g(fromGrams: 0) == nil)
    }

    @Test func totals() {
        let total = Macros.total([Macros(kcal: 100, protein: 1, carbs: 2, fat: 3),
                                  Macros(kcal: 50, protein: 4, carbs: 5, fat: 6)])
        #expect(total == Macros(kcal: 150, protein: 5, carbs: 7, fat: 9))
        #expect(Macros.total([Macros]()) == .zero)
    }
}

struct GoalSelectionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func picksLatestGoalStartedOnOrBeforeDay() {
        let goals = [date(1), date(10), date(20)]
        #expect(GoalSelection.active(goals, on: date(15), effectiveFrom: { $0 }, calendar: calendar) == date(10))
        #expect(GoalSelection.active(goals, on: date(20, hour: 7), effectiveFrom: { $0 }, calendar: calendar) == date(20))
    }

    @Test func noGoalBeforeFirstOne() {
        #expect(GoalSelection.active([date(10)], on: date(5), effectiveFrom: { $0 }, calendar: calendar) == nil)
    }
}

struct MealSuggestionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: hour, minute: 30))!
    }

    @Test func byHour() {
        #expect(Meal.suggested(for: at(7), calendar: calendar) == .breakfast)
        #expect(Meal.suggested(for: at(12), calendar: calendar) == .lunch)
        #expect(Meal.suggested(for: at(16), calendar: calendar) == .snack)
        #expect(Meal.suggested(for: at(18), calendar: calendar) == .dinner)
        #expect(Meal.suggested(for: at(23), calendar: calendar) == .snack)
    }
}

struct NumberInputTests {
    @Test func acceptsCommaDecimals() {
        #expect(NumberInput.parse("12,5") == 12.5)
        #expect(NumberInput.parse(" 80 ") == 80)
    }

    @Test func rejectsJunkAndNegatives() {
        #expect(NumberInput.parse("") == nil)
        #expect(NumberInput.parse("abc") == nil)
        #expect(NumberInput.parse("-3") == nil)
    }

    @Test func entryDateKeepsChosenDay() {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 0))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 13, minute: 15))!
        let combined = EntryFormView.combine(day: yesterday, timeFrom: now, calendar: calendar)
        #expect(calendar.component(.day, from: combined) == 22)
        #expect(calendar.component(.hour, from: combined) == 13)
    }
}
