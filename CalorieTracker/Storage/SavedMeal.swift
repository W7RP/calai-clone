import Foundation
import SwiftData

extension SavedMealItem {
    init(foodName: String, grams: Double, macros: Macros, source: FoodSource, thumbnail: Data? = nil) {
        self.init(foodName: foodName, grams: grams, macros: macros, sourceRaw: source.rawValue, thumbnail: thumbnail)
    }

    init(entry: LogEntry) {
        self.init(foodName: entry.foodName, grams: entry.grams, macros: entry.macros, source: entry.source,
                  thumbnail: entry.thumbnail)
    }
}

/// A group of foods eaten together, re-logged with one tap.
@Model
final class SavedMeal {
    var id: UUID
    var name: String
    /// The meal it was saved from, used when it's logged again.
    var mealRaw: String
    /// JSON array of SavedMealItem. Stored whole so editing a meal never touches past log entries.
    var itemsData: Data
    var createdAt: Date
    var lastUsed: Date
    var timesLogged: Int

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var items: [SavedMealItem] {
        get { (try? JSONDecoder().decode([SavedMealItem].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var totals: Macros { Macros.total(items.map(\.macros)) }

    /// The first photo among the items, for the list.
    var thumbnail: Data? { items.lazy.compactMap(\.thumbnail).first }

    init(name: String, meal: Meal, items: [SavedMealItem], createdAt: Date = .now) {
        id = UUID()
        self.name = name
        mealRaw = meal.rawValue
        itemsData = (try? JSONEncoder().encode(items)) ?? Data()
        self.createdAt = createdAt
        lastUsed = createdAt
        timesLogged = 0
    }
}

/// Everything the store holds, in one place for the app, previews and the shared container.
enum AppModels {
    static var all: [any PersistentModel.Type] {
        [FoodItem.self, LogEntry.self, DailyGoal.self, WeightEntry.self, GoalPlan.self, TrainingDayMark.self,
         SavedMeal.self]
    }
}
