import Foundation

/// One food inside a saved meal. Numbers are for the amount eaten, like a LogEntry.
struct SavedMealItem: Codable, Equatable, Sendable {
    var foodName: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sourceRaw: String
    var thumbnail: Data?

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    init(foodName: String, grams: Double, macros: Macros, sourceRaw: String, thumbnail: Data? = nil) {
        self.foodName = foodName
        self.grams = grams
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
        self.sourceRaw = sourceRaw
        self.thumbnail = thumbnail
    }
}
