import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

struct WidgetSnapshotTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func pending(_ kcal: Double, at date: Date) -> PendingLog {
        PendingLog(date: date, mealRaw: "lunch",
                   items: [SavedMealItem(foodName: "x", grams: 0, macros: Macros(kcal: kcal, protein: 10, carbs: 0, fat: 0),
                                         sourceRaw: "manual")])
    }

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot(day: date(24), eaten: Macros(kcal: 1000, protein: 50, carbs: 100, fat: 30),
                       targets: [date(24): Macros(kcal: 2000, protein: 150, carbs: 200, fat: 60),
                                 date(25): Macros(kcal: 1800, protein: 150, carbs: 150, fat: 60)],
                       meals: [], updated: date(24, 12))
    }

    @Test func addsTodaysPendingLogs() {
        let day = snapshot.day(at: date(24, 18), pending: [pending(300, at: date(24, 17)), pending(999, at: date(23, 9))],
                               calendar: calendar)
        #expect(day.eaten.kcal == 1300)
        #expect(day.kcalLeft == 700)
    }

    @Test func startsOverAfterMidnight() {
        let day = snapshot.day(at: date(25, 8), pending: [], calendar: calendar)
        #expect(day.eaten == .zero)
        #expect(day.target?.kcal == 1800)
    }

    @Test func survivesAJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded.targets[date(25)]?.kcal == 1800)
        #expect(decoded.eaten == snapshot.eaten)
    }

    @Test func summaryReadsNaturally() {
        let target = Macros(kcal: 2000, protein: 150, carbs: 200, fat: 60)
        #expect(QuickLog.summary(.init(eaten: Macros(kcal: 760, protein: 70, carbs: 0, fat: 0), target: target))
            == "1240 kcal left today, and 80g of protein to go.")
        #expect(QuickLog.summary(.init(eaten: Macros(kcal: 2100, protein: 160, carbs: 0, fat: 0), target: target))
            == "100 kcal over today.")
        #expect(QuickLog.summary(.init(eaten: Macros(kcal: 500, protein: 0, carbs: 0, fat: 0), target: nil))
            == "500 kcal eaten today.")
    }

    @Test func routesFromURLs() {
        #expect(AppRoute(url: URL(string: "easycal://scan")!) == .scan)
        #expect(AppRoute(url: URL(string: "easycal://saved")!) == .saved)
        #expect(AppRoute(url: URL(string: "easycal://nope")!) == nil)
        #expect(AppRoute(url: URL(string: "https://scan")!) == nil)
        #expect(AppRoute.describe.url.absoluteString == "easycal://describe")
    }
}

@MainActor
@Suite(.serialized)
struct PendingLogImporterTests {
    @Test func storesPendingLogsAndBumpsTheSavedMeal() throws {
        let container = try ModelContainer(for: Schema(AppModels.all),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        SharedStore.removePending(ids: Set(SharedStore.pendingLogs().map(\.id)))

        let saved = SavedMeal(name: "Shake", meal: .snack,
                              items: [SavedMealItem(foodName: "Shake", grams: 300, macros: Macros(kcal: 210, protein: 40, carbs: 6, fat: 3),
                                                    sourceRaw: "manual", thumbnail: Data([1, 2, 3]))])
        context.insert(saved)
        let when = Date.now
        SharedStore.add(PendingLog(date: when, mealRaw: "snack",
                                   items: saved.items.map { var item = $0; item.thumbnail = nil; return item },
                                   savedMealID: saved.id))

        #expect(PendingLogImporter.importPending(into: context) == 1)

        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.kcal == 210)
        #expect(entries.first?.meal == .snack)
        #expect(entries.first?.thumbnail == Data([1, 2, 3]))
        #expect(saved.timesLogged == 1)
        #expect(SharedStore.pendingLogs().isEmpty)
    }
}
