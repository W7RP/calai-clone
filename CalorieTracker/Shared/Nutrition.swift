import Foundation

/// kcal plus grams of protein, carbs and fat.
struct Macros: Equatable, Sendable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    func scaled(by factor: Double) -> Macros {
        Macros(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    /// Per-100 g values -> values for `grams`.
    func forGrams(_ grams: Double) -> Macros { scaled(by: grams / 100) }

    /// Values for `grams` -> per-100 g values, for caching a manually entered food. Nil when grams is 0.
    func per100g(fromGrams grams: Double) -> Macros? {
        grams > 0 ? scaled(by: 100 / grams) : nil
    }

    static func total(_ items: some Sequence<Macros>) -> Macros {
        items.reduce(.zero, +)
    }
}

enum GoalSelection {
    /// The goal in force on `day`: the latest one that took effect on or before that day.
    static func active<G>(_ goals: [G], on day: Date, effectiveFrom: (G) -> Date,
                          calendar: Calendar = .current) -> G? {
        let dayStart = calendar.startOfDay(for: day)
        return goals
            .filter { calendar.startOfDay(for: effectiveFrom($0)) <= dayStart }
            .max { effectiveFrom($0) < effectiveFrom($1) }
    }
}

enum NumberInput {
    /// Accepts "12.5" or "12,5" (French-Canadian keyboards). Empty or invalid -> nil.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func format(_ value: Double, maxFractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).grouping(.never))
    }
}

enum Nutrition {
    /// Atwater factors. Used only as a sanity hint next to typed goals.
    static func kcalFromMacros(protein: Double, carbs: Double, fat: Double) -> Double {
        protein * 4 + carbs * 4 + fat * 9
    }
}
