import SwiftData
import SwiftUI
import WidgetKit

/// Keeps the widgets' copy of today in step with the log, and stores food logged from widgets and Shortcuts.
struct WidgetSync: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LogEntry]
    @Query private var goals: [DailyGoal]
    @Query private var marks: [TrainingDayMark]
    @Query(sort: \SavedMeal.lastUsed, order: .reverse) private var meals: [SavedMeal]

    let day: Date

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(filter: #Predicate<LogEntry> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        Color.clear
            .onAppear(perform: write)
            .onChange(of: signature) { write() }
    }

    private struct Signature: Equatable {
        var eaten: Macros
        var goals: [Date]
        var marks: [Date: Bool]
        var meals: [String]
    }

    private var signature: Signature {
        Signature(eaten: Macros.total(entries.map(\.macros)),
                  goals: goals.map(\.effectiveFrom),
                  marks: Dictionary(marks.map { ($0.day, $0.isTraining) }, uniquingKeysWith: { $1 }),
                  meals: meals.prefix(WidgetSnapshotBuilder.mealLimit).map { "\($0.id)|\($0.name)|\($0.itemsData.count)" })
    }

    private func write() {
        let snapshot = WidgetSnapshotBuilder.snapshot(day: day, entries: entries, targets: DayTargets(goals: goals, marks: marks),
                                                      meals: meals)
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        EasyCalShortcuts.updateAppShortcutParameters()
    }
}

enum WidgetSnapshotBuilder {
    static let mealLimit = 8

    static func snapshot(day: Date, entries: [LogEntry], targets: DayTargets, meals: [SavedMeal],
                         now: Date = .now) -> WidgetSnapshot {
        let calendar = targets.calendar
        let start = calendar.startOfDay(for: day)
        var upcoming: [Date: Macros] = [:]
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            upcoming[date] = targets.target(on: date)
        }
        let shared = meals.prefix(mealLimit).map { meal in
            SharedMeal(id: meal.id, name: meal.name, mealRaw: meal.mealRaw,
                       items: meal.items.map { item in
                           var item = item
                           item.thumbnail = nil
                           return item
                       })
        }
        return WidgetSnapshot(day: start, eaten: Macros.total(entries.map(\.macros)), targets: upcoming,
                              meals: Array(shared), updated: now)
    }
}

/// Moves food logged from widgets and Shortcuts into the database.
@MainActor
enum PendingLogImporter {
    @discardableResult
    static func importPending(into context: ModelContext) -> Int {
        let pending = SharedStore.pendingLogs()
        guard !pending.isEmpty else { return 0 }
        for log in pending {
            let meal = Meal(rawValue: log.mealRaw) ?? Meal.suggested(for: log.date)
            let saved = log.savedMealID.flatMap { id in
                try? context.fetch(FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.id == id })).first
            }
            // The widget's copy has no photos, so take them from the saved meal when it still matches.
            let photos = saved.map { $0.items.map(\.thumbnail) }
            for (index, item) in log.items.enumerated() {
                let photo = photos.flatMap { $0.count == log.items.count ? $0[index] : nil } ?? item.thumbnail
                context.insert(LogEntry(date: log.date, meal: meal, foodName: item.foodName, grams: item.grams,
                                        macros: item.macros, source: FoodSource(rawValue: item.sourceRaw) ?? .manual,
                                        thumbnail: photo, entered: item.entered))
            }
            if let saved {
                saved.lastUsed = max(saved.lastUsed, log.date)
                saved.timesLogged += 1
            }
        }
        try? context.save()
        SharedStore.removePending(ids: Set(pending.map(\.id)))
        return pending.count
    }
}
