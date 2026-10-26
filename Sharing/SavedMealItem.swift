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
    /// The unit it was entered in. Nil on items saved before units existed, which read as grams.
    var entered: EnteredAmount?

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    init(foodName: String, grams: Double, macros: Macros, sourceRaw: String, thumbnail: Data? = nil,
         entered: EnteredAmount? = nil) {
        self.foodName = foodName
        self.grams = grams
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
        self.sourceRaw = sourceRaw
        self.thumbnail = thumbnail
        self.entered = entered
    }
}

/// How an amount was entered (1.5 cups, 2 servings), kept next to its grams so it reopens the same way.
struct EnteredAmount: Codable, Equatable, Sendable {
    var quantity: Double
    /// An AmountUnit raw value: "g", "serving", "cup"...
    var unitRaw: String
    /// Grams in one serving and grams per mL at the time, so the conversion doesn't drift later.
    var servingGrams: Double?
    var density: Double?
}
