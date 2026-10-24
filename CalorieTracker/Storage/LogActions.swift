import Foundation
import SwiftData

/// Logging shortcuts that copy food that's already known: saved meals, single entries and yesterday's meals.
@MainActor
enum LogActions {
    /// Logs every item of a saved meal on `day`, at the current clock time. Returns the new entries.
    @discardableResult
    static func log(_ saved: SavedMeal, on day: Date, meal: Meal? = nil, now: Date = .now,
                    in context: ModelContext) -> [LogEntry] {
        let date = EntryFormView.combine(day: day, timeFrom: now)
        let entries = saved.items.map { item in
            LogEntry(date: date, meal: meal ?? saved.meal, foodName: item.foodName, grams: item.grams,
                     macros: item.macros, source: FoodSource(rawValue: item.sourceRaw) ?? .manual,
                     thumbnail: item.thumbnail)
        }
        for entry in entries { context.insert(entry) }
        saved.lastUsed = now
        saved.timesLogged += 1
        return entries
    }

    /// Logs one entry again on `day`, at the current clock time.
    @discardableResult
    static func relog(_ entry: LogEntry, on day: Date, now: Date = .now, in context: ModelContext) -> LogEntry {
        let copy = LogEntry(date: EntryFormView.combine(day: day, timeFrom: now), meal: Meal.suggested(for: now),
                            foodName: entry.foodName, grams: entry.grams, macros: entry.macros, source: entry.source,
                            foodItem: entry.foodItem, aiConfidence: entry.aiConfidence, thumbnail: entry.thumbnail)
        context.insert(copy)
        entry.foodItem?.lastUsed = now
        return copy
    }

    /// Copies the previous day's entries onto `day`, keeping their clock times. `meal` nil copies the whole day.
    /// Returns how many entries were copied.
    @discardableResult
    static func copyPreviousDay(to day: Date, meal: Meal?, in context: ModelContext,
                                calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: day)
        guard let previous = calendar.date(byAdding: .day, value: -1, to: start) else { return 0 }
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.date >= previous && $0.date < start },
            sortBy: [SortDescriptor(\.date)])
        let entries = ((try? context.fetch(descriptor)) ?? []).filter { meal == nil || $0.meal == meal }
        for entry in entries {
            context.insert(LogEntry(date: DayMath.move(entry.date, toDay: day, calendar: calendar), meal: entry.meal,
                                    foodName: entry.foodName, grams: entry.grams, macros: entry.macros,
                                    source: entry.source, foodItem: entry.foodItem, aiConfidence: entry.aiConfidence,
                                    thumbnail: entry.thumbnail))
        }
        return entries.count
    }

    /// Saves entries as a meal that can be logged again later.
    @discardableResult
    static func saveMeal(named name: String, meal: Meal, entries: [LogEntry], in context: ModelContext) -> SavedMeal {
        let saved = SavedMeal(name: name, meal: meal, items: entries.sorted { $0.date < $1.date }.map(SavedMealItem.init))
        context.insert(saved)
        return saved
    }
}

enum SavedMealNaming {
    /// A starting name for a meal saved from these foods: "Eggs", "Eggs & toast", "Eggs, toast + 2 more".
    static func suggestion(for names: [String]) -> String {
        let names = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch names.count {
        case 0: return "My meal"
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1].lowercasedFirst)"
        default: return "\(names[0]), \(names[1].lowercasedFirst) + \(names.count - 2) more"
        }
    }
}

private extension String {
    /// "Toast" -> "toast", but "BBQ chips" stays as it is.
    var lowercasedFirst: String {
        guard let first, first.isUppercase, dropFirst().first?.isUppercase != true else { return self }
        return first.lowercased() + dropFirst()
    }
}
