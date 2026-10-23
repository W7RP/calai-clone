import Foundation
import SwiftData

enum Meal: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// Default meal for a new entry, so logging at 12:30 doesn't need a tap to pick "Lunch".
    static func suggested(for date: Date, calendar: Calendar = .current) -> Meal {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

enum FoodSource: String, Codable, Sendable {
    case off, ai, manual
}

/// A food that has been logged before, cached so repeat items need no scan or AI call.
@Model
final class FoodItem {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var servingGrams: Double?
    var sourceRaw: String
    var lastUsed: Date

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .manual }
    var per100g: Macros { Macros(kcal: kcalPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g) }

    init(name: String, brand: String? = nil, barcode: String? = nil, per100g: Macros,
         servingGrams: Double? = nil, source: FoodSource, lastUsed: Date = .now) {
        id = UUID()
        self.name = name
        self.brand = brand
        self.barcode = barcode
        kcalPer100g = per100g.kcal
        proteinPer100g = per100g.protein
        carbsPer100g = per100g.carbs
        fatPer100g = per100g.fat
        self.servingGrams = servingGrams
        sourceRaw = source.rawValue
        self.lastUsed = lastUsed
    }
}

/// One logged item. Numbers are a snapshot, so editing a cached FoodItem later doesn't rewrite history.
@Model
final class LogEntry {
    var id: UUID
    var date: Date
    var mealRaw: String
    var foodName: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sourceRaw: String
    var foodItem: FoodItem?
    var aiConfidence: Double?

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .manual }

    var macros: Macros {
        get { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }

    init(date: Date, meal: Meal, foodName: String, grams: Double, macros: Macros,
         source: FoodSource, foodItem: FoodItem? = nil, aiConfidence: Double? = nil) {
        id = UUID()
        self.date = date
        mealRaw = meal.rawValue
        self.foodName = foodName
        self.grams = grams
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
        sourceRaw = source.rawValue
        self.foodItem = foodItem
        self.aiConfidence = aiConfidence
    }
}

/// Goals are never edited in place; a new row takes effect from its date, so past days keep the goal they had.
@Model
final class DailyGoal {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var effectiveFrom: Date

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    init(macros: Macros, effectiveFrom: Date) {
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
        self.effectiveFrom = effectiveFrom
    }
}

/// Optional body weight log for the trend chart. Kilograms.
@Model
final class WeightEntry {
    var date: Date
    var kilograms: Double

    init(date: Date, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}
