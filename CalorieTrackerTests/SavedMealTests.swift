import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

struct SavedMealNamingTests {
    @Test func namesFromFoods() {
        #expect(SavedMealNaming.suggestion(for: []) == "My meal")
        #expect(SavedMealNaming.suggestion(for: ["Eggs"]) == "Eggs")
        #expect(SavedMealNaming.suggestion(for: ["Eggs", "Toast"]) == "Eggs & toast")
        #expect(SavedMealNaming.suggestion(for: ["Eggs", "Toast", "Coffee", "Juice"]) == "Eggs, toast + 2 more")
    }

    @Test func keepsAcronyms() {
        #expect(SavedMealNaming.suggestion(for: ["Burger", "BBQ chips"]) == "Burger & BBQ chips")
    }
}

@MainActor
struct LogActionsTests {
    private let calendar = Calendar.current

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppModels.all), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func entry(_ name: String, at date: Date, meal: Meal, kcal: Double) -> LogEntry {
        LogEntry(date: date, meal: meal, foodName: name, grams: 100,
                 macros: Macros(kcal: kcal, protein: 10, carbs: 20, fat: 5), source: .manual)
    }

    private func entries(on day: Date, in context: ModelContext) throws -> [LogEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                           sortBy: [SortDescriptor(\.date)]))
    }

    @Test func copiesWholePreviousDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(entry("Oats", at: date(22, 8, 10), meal: .breakfast, kcal: 300))
        context.insert(entry("Rice", at: date(22, 19), meal: .dinner, kcal: 600))
        context.insert(entry("Old", at: date(21, 12), meal: .lunch, kcal: 999))

        let copied = LogActions.copyPreviousDay(to: date(23, 15), meal: nil, in: context, calendar: calendar)

        #expect(copied == 2)
        let today = try entries(on: date(23), in: context)
        #expect(today.map(\.foodName) == ["Oats", "Rice"])
        #expect(today.first?.date == date(23, 8, 10))
        #expect(today.last?.meal == .dinner)
    }

    @Test func copiesOneMeal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(entry("Oats", at: date(22, 8), meal: .breakfast, kcal: 300))
        context.insert(entry("Rice", at: date(22, 19), meal: .dinner, kcal: 600))

        let copied = LogActions.copyPreviousDay(to: date(23), meal: .dinner, in: context, calendar: calendar)

        #expect(copied == 1)
        #expect(try entries(on: date(23), in: context).map(\.foodName) == ["Rice"])
    }

    @Test func savedMealRoundTripsAndLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let eggs = entry("Eggs", at: date(22, 8), meal: .breakfast, kcal: 150)
        let toast = entry("Toast", at: date(22, 8, 5), meal: .breakfast, kcal: 90)
        let saved = LogActions.saveMeal(named: "Breakfast", meal: .breakfast, entries: [toast, eggs], in: context)

        #expect(saved.items.map(\.foodName) == ["Eggs", "Toast"])
        #expect(saved.totals.kcal == 240)

        let logged = LogActions.log(saved, on: date(24), now: date(23, 9, 30), in: context)

        #expect(logged.count == 2)
        #expect(logged.allSatisfy { $0.date == date(24, 9, 30) && $0.meal == .breakfast })
        #expect(saved.timesLogged == 1)
        #expect(try entries(on: date(24), in: context).count == 2)
    }

    @Test func editingItemsDoesNotTouchLoggedEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = LogActions.saveMeal(named: "Lunch", meal: .lunch,
                                        entries: [entry("Soup", at: date(22, 12), meal: .lunch, kcal: 200)], in: context)
        let logged = LogActions.log(saved, on: date(23), now: date(23, 12), in: context)
        saved.items = []

        #expect(saved.items.isEmpty)
        #expect(logged.first?.kcal == 200)
    }
}
