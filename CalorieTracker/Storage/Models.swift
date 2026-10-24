import Foundation
import SwiftData

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
    /// Small JPEG of the meal photo, shown on the food card. Only set for photo logs.
    var thumbnail: Data?

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
         source: FoodSource, foodItem: FoodItem? = nil, aiConfidence: Double? = nil, thumbnail: Data? = nil) {
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
        self.thumbnail = thumbnail
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

    // Carb cycling. All nil for a goal typed in by hand or saved with cycling off.
    var trainingKcal: Double?
    var trainingProtein: Double?
    var trainingCarbs: Double?
    var trainingFat: Double?
    var restKcal: Double?
    var restProtein: Double?
    var restCarbs: Double?
    var restFat: Double?
    /// WeekdaySet raw value. Kept on the goal so past days keep the schedule they were planned with.
    var trainingWeekdaysRaw: Int?

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var trainingWeekdays: WeekdaySet { WeekdaySet(rawValue: trainingWeekdaysRaw ?? 0) }

    var training: Macros? {
        guard let trainingKcal, let trainingProtein, let trainingCarbs, let trainingFat else { return nil }
        return Macros(kcal: trainingKcal, protein: trainingProtein, carbs: trainingCarbs, fat: trainingFat)
    }

    var rest: Macros? {
        guard let restKcal, let restProtein, let restCarbs, let restFat else { return nil }
        return Macros(kcal: restKcal, protein: restProtein, carbs: restCarbs, fat: restFat)
    }

    var isCycling: Bool { training != nil && rest != nil }

    /// The target for one day: training or rest numbers when cycling, the plain goal otherwise.
    func target(trainingDay: Bool) -> Macros {
        (trainingDay ? training : rest) ?? macros
    }

    init(macros: Macros, effectiveFrom: Date, training: Macros? = nil, rest: Macros? = nil,
         trainingWeekdays: WeekdaySet? = nil) {
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
        self.effectiveFrom = effectiveFrom
        trainingKcal = training?.kcal
        trainingProtein = training?.protein
        trainingCarbs = training?.carbs
        trainingFat = training?.fat
        restKcal = rest?.kcal
        restProtein = rest?.protein
        restCarbs = rest?.carbs
        restFat = rest?.fat
        trainingWeekdaysRaw = trainingWeekdays?.rawValue
    }
}

/// The answers behind the calculated goal. One row, edited in place; each save also writes a DailyGoal.
@Model
final class GoalPlan {
    var sexRaw: String
    var birthYear: Int
    var heightCm: Double
    var lifestyleRaw: String
    var trainingWeekdaysRaw: Int
    var sessionMinutes: Double
    var cardioMinutesPerWeek: Double
    var cardioIntensityRaw: String
    var targetKg: Double
    var weeklyRateKg: Double
    var cycling: Bool
    var cyclingShift: Double
    var updatedAt: Date

    var sex: Sex { Sex(rawValue: sexRaw) ?? .male }
    var lifestyle: Lifestyle { Lifestyle(rawValue: lifestyleRaw) ?? .desk }
    var cardioIntensity: CardioIntensity { CardioIntensity(rawValue: cardioIntensityRaw) ?? .moderate }
    var trainingWeekdays: WeekdaySet { WeekdaySet(rawValue: trainingWeekdaysRaw) }

    init(inputs: PlanInputs, birthYear: Int, updatedAt: Date = .now) {
        sexRaw = inputs.sex.rawValue
        self.birthYear = birthYear
        heightCm = inputs.heightCm
        lifestyleRaw = inputs.lifestyle.rawValue
        trainingWeekdaysRaw = inputs.trainingDays.rawValue
        sessionMinutes = inputs.sessionMinutes
        cardioMinutesPerWeek = inputs.cardioMinutesPerWeek
        cardioIntensityRaw = inputs.cardioIntensity.rawValue
        targetKg = inputs.targetKg
        weeklyRateKg = inputs.weeklyRateKg
        cycling = inputs.cycling
        cyclingShift = inputs.cyclingShift
        self.updatedAt = updatedAt
    }

    func update(from inputs: PlanInputs, birthYear: Int, at date: Date = .now) {
        sexRaw = inputs.sex.rawValue
        self.birthYear = birthYear
        heightCm = inputs.heightCm
        lifestyleRaw = inputs.lifestyle.rawValue
        trainingWeekdaysRaw = inputs.trainingDays.rawValue
        sessionMinutes = inputs.sessionMinutes
        cardioMinutesPerWeek = inputs.cardioMinutesPerWeek
        cardioIntensityRaw = inputs.cardioIntensity.rawValue
        targetKg = inputs.targetKg
        weeklyRateKg = inputs.weeklyRateKg
        cycling = inputs.cycling
        cyclingShift = inputs.cyclingShift
        updatedAt = date
    }

    /// Inputs at a given body weight, so the estimate follows the latest weigh-in.
    func inputs(weightKg: Double, on date: Date = .now, calendar: Calendar = .current) -> PlanInputs {
        PlanInputs(sex: sex, age: calendar.component(.year, from: date) - birthYear, heightCm: heightCm,
                   weightKg: weightKg, lifestyle: lifestyle, trainingDays: trainingWeekdays,
                   sessionMinutes: sessionMinutes, cardioMinutesPerWeek: cardioMinutesPerWeek,
                   cardioIntensity: cardioIntensity, targetKg: targetKg, weeklyRateKg: weeklyRateKg,
                   cycling: cycling, cyclingShift: cyclingShift)
    }
}

/// A day the user marked as training or rest by hand, overriding the weekly schedule.
@Model
final class TrainingDayMark {
    /// Start of the day.
    var day: Date
    var isTraining: Bool

    init(day: Date, isTraining: Bool) {
        self.day = day
        self.isTraining = isTraining
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
