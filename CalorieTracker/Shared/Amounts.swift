import Foundation

/// Units an amount can be entered in. Everything is stored as grams; volumes get there through a density.
enum AmountUnit: String, CaseIterable, Identifiable, Sendable {
    case grams = "g"
    case ounces = "oz"
    case servings = "serving"
    case milliliters = "mL"
    case cups = "cup"
    case tablespoons = "tbsp"
    case teaspoons = "tsp"
    case fluidOunces = "fl oz"

    var id: Self { self }

    /// Grams in one unit for weights, millilitres in one unit for volumes. Nil for servings, which depend on the food.
    var size: Double? {
        switch self {
        case .grams, .milliliters: 1
        case .ounces: 28.3495
        case .servings: nil
        // Metric measures, as Canadian labels and recipes use them; US ones are within about 5%.
        case .cups: 250
        case .tablespoons: 15
        case .teaspoons: 5
        case .fluidOunces: 29.5735
        }
    }

    var isVolume: Bool {
        switch self {
        case .milliliters, .cups, .tablespoons, .teaspoons, .fluidOunces: true
        case .grams, .ounces, .servings: false
        }
    }

    /// "cup" or "cups", to follow a number.
    func label(for quantity: Double) -> String {
        guard quantity != 1 else { return rawValue }
        switch self {
        case .cups: return "cups"
        case .servings: return "servings"
        default: return rawValue
        }
    }

    /// Quick picks offered as chips.
    var presets: [Double] {
        switch self {
        case .grams: [50, 100, 150, 200, 250]
        case .ounces: [1, 2, 4, 6, 8]
        case .servings: [0.5, 1, 1.5, 2, 3]
        case .milliliters: [100, 250, 330, 500]
        case .cups: [0.25, 0.5, 1, 1.5, 2]
        case .tablespoons, .teaspoons: [0.5, 1, 2, 3]
        case .fluidOunces: [4, 8, 12, 16]
        }
    }

    /// How far − and + move.
    var step: Double {
        switch self {
        case .grams: 10
        case .milliliters: 25
        case .ounces, .servings, .tablespoons, .teaspoons: 0.5
        case .cups: 0.25
        case .fluidOunces: 1
        }
    }

    /// Decimals worth keeping when an amount is converted into this unit.
    var fractionDigits: Int {
        switch self {
        case .grams, .milliliters: 0
        default: 2
        }
    }
}

/// What turns an amount in any unit into grams of one food.
struct FoodMeasure: Equatable, Sendable {
    /// Grams in one serving: the label's serving, or the portion first logged when there's no label.
    var servingGrams: Double?
    /// Grams per millilitre, when it's known from the label, the AI estimate or the food's name.
    var density: Double?

    /// Water. Volumes use it when nothing better is known.
    static let fallbackDensity = 1.0

    init(servingGrams: Double? = nil, density: Double? = nil) {
        self.servingGrams = servingGrams.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        self.density = density.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }

    var units: [AmountUnit] {
        AmountUnit.allCases.filter { $0 != .servings || servingGrams != nil }
    }

    /// Grams in one of `unit`, nil for servings when there's no serving size.
    func grams(per unit: AmountUnit) -> Double? {
        if unit == .servings { return servingGrams }
        guard let size = unit.size else { return nil }
        return unit.isVolume ? size * (density ?? Self.fallbackDensity) : size
    }

    func grams(_ quantity: Double, in unit: AmountUnit) -> Double? {
        grams(per: unit).map { quantity * $0 }
    }

    func quantity(ofGrams grams: Double, in unit: AmountUnit) -> Double? {
        guard let each = self.grams(per: unit), each > 0 else { return nil }
        return grams / each
    }
}

/// Rough densities for foods often measured with spoons and cups. Only clear name matches; anything else
/// falls back to water, and the amount screen says so.
enum Density {
    /// Grams per millilitre. Earlier entries win, so "peanut butter" is matched before "butter".
    private static let table: [(words: String, density: Double)] = [
        ("peanut butter", 1.08), ("almond butter", 1.08), ("beurre d arachide", 1.08),
        ("butter", 0.96), ("beurre", 0.96),
        ("oil", 0.92), ("huile", 0.92),
        ("honey", 1.42), ("miel", 1.42),
        ("syrup", 1.33), ("sirop", 1.33),
        ("flour", 0.53), ("farine", 0.53),
        ("sugar", 0.85), ("sucre", 0.85),
        ("oats", 0.41), ("granola", 0.45),
        ("milk", 1.03), ("lait", 1.03),
        ("yogurt", 1.05), ("yoghurt", 1.05), ("yogourt", 1.05),
    ]

    static func guess(for name: String) -> Double? {
        let words = name.lowercased().split { !$0.isLetter }
        let padded = " \(words.joined(separator: " ")) "
        return table.first { padded.contains(" \($0.words) ") }?.density
    }
}

/// An amount being typed: the number as text so half-typed values survive, its unit, and the food's measures.
struct AmountInput: Equatable, Sendable {
    var text: String
    private(set) var unit: AmountUnit
    let measure: FoodMeasure

    /// Shows `grams` in `unit`, or the exact quantity first entered when it still matches.
    init(grams: Double, measure: FoodMeasure, unit: AmountUnit = .grams, quantity: Double? = nil) {
        self.measure = measure
        let unit = measure.units.contains(unit) ? unit : .grams
        self.unit = unit
        if let quantity, let back = measure.grams(quantity, in: unit), abs(back - grams) <= max(0.5, grams * 0.005) {
            text = NumberInput.format(quantity, maxFractionDigits: 2)
        } else {
            text = Self.format(measure.quantity(ofGrams: grams, in: unit) ?? grams, in: unit)
        }
    }

    /// Reopens an amount the way it was entered.
    init(grams: Double, entered: EnteredAmount?, servingGrams: Double?, density: Double?) {
        let measure = FoodMeasure(servingGrams: entered?.servingGrams ?? servingGrams,
                                  density: entered?.density ?? density)
        self.init(grams: grams, measure: measure,
                  unit: entered.flatMap { AmountUnit(rawValue: $0.unitRaw) } ?? .grams,
                  quantity: entered?.quantity)
    }

    var quantity: Double? { NumberInput.parse(text) }

    var grams: Double? { quantity.flatMap { measure.grams($0, in: unit) } }

    /// Switches unit and converts the number, so the amount itself doesn't change.
    mutating func convert(to newUnit: AmountUnit) {
        guard newUnit != unit, measure.units.contains(newUnit) else { return }
        if let grams, let converted = measure.quantity(ofGrams: grams, in: newUnit) {
            text = Self.format(converted, in: newUnit)
        }
        unit = newUnit
    }

    mutating func set(_ quantity: Double) {
        text = NumberInput.format(quantity, maxFractionDigits: 2)
    }

    /// Moves to the next whole step up or down: 137 g goes to 140 or 130, ¾ cup to 1 or ½.
    mutating func step(_ direction: Int) {
        let size = unit.step
        let steps = (quantity ?? 0) / size
        let base = direction > 0 ? (steps + 1e-9).rounded(.down) : (steps - 1e-9).rounded(.up)
        set(max(0, (base + Double(direction)) * size))
    }

    /// How this was entered, to store next to the grams.
    var entered: EnteredAmount? {
        guard let quantity else { return nil }
        return EnteredAmount(quantity: quantity, unitRaw: unit.rawValue,
                             servingGrams: measure.servingGrams, density: measure.density)
    }

    /// The grams behind a unit that isn't grams, and what that assumes.
    var hint: String? {
        guard unit != .grams, let grams else { return nil }
        var parts = ["= \(NumberInput.format(grams, maxFractionDigits: 0)) g"]
        if unit == .servings, let serving = measure.servingGrams {
            parts.append("1 serving is \(NumberInput.format(serving, maxFractionDigits: 0)) g")
        } else if unit.isVolume, measure.density == nil {
            parts.append("assumes 1 g per mL, like water")
        }
        return parts.joined(separator: " · ")
    }

    /// "1½ cups", "150 g"
    var summary: String {
        guard let quantity else { return "" }
        return "\(AmountText.quantity(quantity)) \(unit.label(for: quantity))"
    }

    private static func format(_ quantity: Double, in unit: AmountUnit) -> String {
        NumberInput.format(quantity, maxFractionDigits: unit.fractionDigits)
    }
}

enum AmountText {
    /// 0.5 -> "½", 1.25 -> "1¼"; anything else as a plain number.
    static func quantity(_ value: Double) -> String {
        let whole = value.rounded(.down)
        let fraction = value - whole
        let glyphs: [(Double, String)] = [(0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")]
        if fraction > 0.001, let glyph = glyphs.first(where: { abs($0.0 - fraction) < 0.01 })?.1 {
            return whole > 0 ? "\(NumberInput.format(whole, maxFractionDigits: 0))\(glyph)" : glyph
        }
        return NumberInput.format(value, maxFractionDigits: 2)
    }

    /// "1 cup · 250 g", or "150 g" for amounts entered in grams.
    static func describe(grams: Double, entered: EnteredAmount?) -> String {
        let weight = "\(NumberInput.format(grams, maxFractionDigits: 0)) g"
        guard let entered, let unit = AmountUnit(rawValue: entered.unitRaw), unit != .grams else { return weight }
        return "\(quantity(entered.quantity)) \(unit.label(for: entered.quantity)) · \(weight)"
    }
}

/// An amount and the nutrition for it, kept in proportion. Changing the amount rescales the numbers from
/// what they were per gram, so typing "1", "15", "150" lands on the same values as typing 150 at once;
/// typing a number changes what the others scale from.
struct NutritionInput: Equatable, Sendable {
    var amount: AmountInput {
        didSet { if amount.grams != oldValue.grams { rescale() } }
    }

    var kcal: String {
        get { fields.kcal }
        set { fields.kcal = newValue; rebase() }
    }
    var protein: String {
        get { fields.protein }
        set { fields.protein = newValue; rebase() }
    }
    var carbs: String {
        get { fields.carbs }
        set { fields.carbs = newValue; rebase() }
    }
    var fat: String {
        get { fields.fat }
        set { fields.fat = newValue; rebase() }
    }

    private struct Fields: Equatable, Sendable {
        var kcal = ""
        var protein = ""
        var carbs = ""
        var fat = ""
    }

    private var fields = Fields()
    /// Nutrition in one gram. Nil until there's both an amount and an energy value.
    private var perGram: Macros?

    init(amount: AmountInput, macros: Macros?) {
        self.amount = amount
        if let macros { fields = Self.formatted(macros, keepingBlank: nil) }
        rebase()
    }

    /// Empty for a new entry.
    init(amount: AmountInput) {
        self.init(amount: amount, macros: nil)
    }

    /// Energy is required; blank protein, carbs or fat count as 0.
    var macros: Macros? {
        guard let kcal = NumberInput.parse(fields.kcal) else { return nil }
        func optional(_ text: String) -> Double? {
            text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : NumberInput.parse(text)
        }
        guard let protein = optional(fields.protein), let carbs = optional(fields.carbs),
              let fat = optional(fields.fat) else { return nil }
        return Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    var isValid: Bool { macros != nil && (amount.grams ?? 0) > 0 }

    private mutating func rebase() {
        guard let grams = amount.grams, grams > 0, let macros else {
            perGram = nil
            return
        }
        perGram = macros.scaled(by: 1 / grams)
    }

    private mutating func rescale() {
        guard let perGram, let grams = amount.grams else { return }
        fields = Self.formatted(perGram.scaled(by: grams), keepingBlank: fields)
    }

    /// Formats values for the text fields. A macro left blank stays blank while it's zero.
    private static func formatted(_ macros: Macros, keepingBlank old: Fields?) -> Fields {
        func text(_ value: Double, was: String?) -> String {
            if let was, was.trimmingCharacters(in: .whitespaces).isEmpty, value == 0 { return "" }
            return NumberInput.format(value)
        }
        return Fields(kcal: NumberInput.format(macros.kcal, maxFractionDigits: 0),
                      protein: text(macros.protein, was: old?.protein),
                      carbs: text(macros.carbs, was: old?.carbs),
                      fat: text(macros.fat, was: old?.fat))
    }
}
