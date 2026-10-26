import Foundation

/// Units an amount can be entered in. Everything is stored as grams (mL for drinks); each food says which it offers.
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

/// The units one food can be measured in, and the grams in one of each. Only what the food's own data gives:
/// grams (millilitres for drinks), its serving, and any cup or spoon the label names next to a weight, like
/// "1 cup (118 g)". Nothing is guessed, so a unit the label doesn't give isn't offered.
struct FoodMeasure: Equatable, Sendable {
    /// Grams in one serving: the label's serving, or the portion first logged when there's no label.
    var servingGrams: Double?
    /// Drinks are measured in mL. Their values are per 100 mL, so a "gram" of one is a millilitre.
    private(set) var isLiquid: Bool
    /// Grams in one of each other unit, like 118 for a cup of granola.
    private(set) var unitGrams: [AmountUnit: Double]

    init(servingGrams: Double? = nil, isLiquid: Bool = false, unitGrams: [AmountUnit: Double] = [:]) {
        self.servingGrams = servingGrams.flatMap(Self.valid)
        self.isLiquid = isLiquid
        let base: AmountUnit = isLiquid ? .milliliters : .grams
        self.unitGrams = unitGrams.compactMapValues(Self.valid).filter { $0.key != base && $0.key != .servings }
    }

    /// What the amount is stored in: grams, or millilitres for a drink.
    var baseUnit: AmountUnit { isLiquid ? .milliliters : .grams }

    /// The base unit, the serving, then the label's own units.
    var units: [AmountUnit] {
        var units = [baseUnit]
        if servingGrams != nil { units.append(.servings) }
        return units + AmountUnit.allCases.filter { unitGrams[$0] != nil }
    }

    /// Grams in one of `unit`, nil when this food doesn't offer it.
    func grams(per unit: AmountUnit) -> Double? {
        if unit == baseUnit { return 1 }
        if unit == .servings { return servingGrams }
        return unitGrams[unit]
    }

    func grams(_ quantity: Double, in unit: AmountUnit) -> Double? {
        grams(per: unit).map { quantity * $0 }
    }

    func quantity(ofGrams grams: Double, in unit: AmountUnit) -> Double? {
        guard let each = self.grams(per: unit), each > 0 else { return nil }
        return grams / each
    }

    /// Adds `unit` at `grams` each, so an amount entered in it reopens exactly as it was.
    func including(_ unit: AmountUnit, gramsEach grams: Double) -> FoodMeasure {
        guard unit != baseUnit, let grams = Self.valid(grams) else { return self }
        var copy = self
        if unit == .servings { copy.servingGrams = grams } else { copy.unitGrams[unit] = grams }
        return copy
    }

    /// The label's units for storing on a food, as "cup=118;tbsp=15".
    var unitsText: String? {
        guard !unitGrams.isEmpty else { return nil }
        return AmountUnit.allCases.compactMap { unit in
            unitGrams[unit].map { "\(unit.rawValue)=\($0)" }
        }.joined(separator: ";")
    }

    static func unitGrams(from text: String?) -> [AmountUnit: Double] {
        var result: [AmountUnit: Double] = [:]
        for pair in (text ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let unit = AmountUnit(rawValue: parts[0]),
                  let grams = NumberInput.parse(parts[1]) else { continue }
            result[unit] = grams
        }
        return result
    }

    private static func valid(_ value: Double) -> Double? { value > 0 && value.isFinite ? value : nil }
}

/// An amount being typed: the number as text so half-typed values survive, its unit, and the food's measures.
struct AmountInput: Equatable, Sendable {
    var text: String
    private(set) var unit: AmountUnit
    private(set) var measure: FoodMeasure

    /// Shows `grams` in `unit`, or the exact quantity first entered when it still matches.
    init(grams: Double, measure: FoodMeasure, unit: AmountUnit? = nil, quantity: Double? = nil) {
        self.measure = measure
        let unit = unit.flatMap { measure.units.contains($0) ? $0 : nil } ?? measure.baseUnit
        self.unit = unit
        if let quantity, let back = measure.grams(quantity, in: unit), abs(back - grams) <= max(0.5, grams * 0.005) {
            text = NumberInput.format(quantity, maxFractionDigits: 2)
        } else {
            text = Self.format(measure.quantity(ofGrams: grams, in: unit) ?? grams, in: unit)
        }
    }

    /// Reopens an amount the way it was entered. The unit it was entered in is kept at what it weighed then,
    /// even if the food no longer lists it.
    init(grams: Double, entered: EnteredAmount?, measure: FoodMeasure) {
        var measure = measure
        if let servingGrams = entered?.servingGrams, measure.servingGrams == nil { measure.servingGrams = servingGrams }
        guard let entered, entered.quantity > 0, let unit = AmountUnit(rawValue: entered.unitRaw) else {
            self.init(grams: grams, measure: measure)
            return
        }
        self.init(grams: grams, measure: measure.including(unit, gramsEach: grams / entered.quantity),
                  unit: unit, quantity: entered.quantity)
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
        return EnteredAmount(quantity: quantity, unitRaw: unit.rawValue, servingGrams: measure.servingGrams)
    }

    /// The grams (or mL, for a drink) behind any other unit.
    var hint: String? {
        guard unit != measure.baseUnit, let grams else { return nil }
        return "= \(NumberInput.format(grams, maxFractionDigits: 0)) \(measure.baseUnit.rawValue)"
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

    /// "1 cup · 118 g", or "150 g" for amounts entered in grams. Drinks read in mL.
    static func describe(grams: Double, entered: EnteredAmount?, liquid: Bool = false) -> String {
        let base: AmountUnit = liquid ? .milliliters : .grams
        let weight = "\(NumberInput.format(grams, maxFractionDigits: 0)) \(base.rawValue)"
        guard let entered, let unit = AmountUnit(rawValue: entered.unitRaw), unit != base else { return weight }
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

/// Reads a label's serving text, like "1 cup (29 g)", "3/4 tasse (175 mL)" or "2 c. à soupe (30 g)".
enum ServingSize {
    struct Parsed: Equatable {
        var grams: Double?
        var milliliters: Double?
        /// A cup, spoon or fl oz was named, so this is how the label itself measures a serving.
        var household = false
        /// How many of each volume unit the serving is: "3/4 cup (175 mL)" is ¾ cup and 175 mL.
        var volumes: [AmountUnit: Double] = [:]
    }

    // Longer spellings first so "fl oz" isn't read as "oz" and "tbsp" isn't cut short.
    /// `metric` volumes are exact and win over household measures: "8 fl oz (240 mL)" is 240 mL.
    private static let units: [(pattern: String, grams: Double?, milliliters: Double?, metric: Bool, unit: AmountUnit?)] = [
        (#"fl\.?\s*oz"#, nil, 29.5735, false, .fluidOunces),
        (#"millilit(?:re|er)s?|ml"#, nil, 1, true, .milliliters),
        (#"cl"#, nil, 10, true, .milliliters),
        (#"lit(?:re|er)s?|l"#, nil, 1000, true, .milliliters),
        (#"cups?|tasses?"#, nil, 250, false, .cups),
        (#"tablespoons?|tbsps?|c\.\s*à\s*(?:soupe|s\.)"#, nil, 15, false, .tablespoons),
        (#"teaspoons?|tsps?|c\.\s*à\s*(?:thé|café|c\.|t\.)"#, nil, 5, false, .teaspoons),
        (#"kg"#, 1000, nil, false, nil),
        (#"grams?|grammes?|gr|g"#, 1, nil, false, nil),
        (#"oz"#, 28.3495, nil, false, nil),
    ]

    private static var pattern: String {
        let number = #"(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"#
        let unit = "(" + units.map { "(?:\($0.pattern))" }.joined(separator: "|") + ")"
        return number + #"\s*"# + unit + #"(?![\p{L}])"#
    }

    static func parse(_ text: String) -> Parsed {
        var cleaned = text.lowercased().replacingOccurrences(of: ",", with: ".")
        for (glyph, fraction) in [("¼", " 1/4"), ("½", " 1/2"), ("¾", " 3/4"), ("⅓", " 1/3"), ("⅔", " 2/3")] {
            cleaned = cleaned.replacingOccurrences(of: glyph, with: fraction)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        var result = Parsed()
        var household: Double?
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return result }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        for match in regex.matches(in: cleaned, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: cleaned),
                  let unitRange = Range(match.range(at: 2), in: cleaned),
                  let quantity = number(String(cleaned[numberRange])), quantity > 0,
                  let unit = units.first(where: { matches($0.pattern, String(cleaned[unitRange])) }) else { continue }
            if let grams = unit.grams, result.grams == nil { result.grams = quantity * grams }
            if let volume = unit.unit, let milliliters = unit.milliliters, result.volumes[volume] == nil {
                result.volumes[volume] = unit.metric ? quantity * milliliters : quantity
            }
            if let milliliters = unit.milliliters {
                if unit.metric {
                    if result.milliliters == nil { result.milliliters = quantity * milliliters }
                } else if household == nil {
                    household = quantity * milliliters
                }
            }
        }
        if result.milliliters == nil { result.milliliters = household }
        result.household = household != nil
        return result
    }

    /// "1 1/2" -> 1.5, "3/4" -> 0.75, "30" -> 30.
    private static func number(_ text: String) -> Double? {
        let parts = text.split(separator: " ")
        var total = 0.0
        for part in parts {
            let fraction = part.split(separator: "/")
            if fraction.count == 2, let top = Double(fraction[0]), let bottom = Double(fraction[1]), bottom > 0 {
                total += top / bottom
            } else if let value = Double(part) {
                total += value
            } else {
                return nil
            }
        }
        return total
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: "^(?:\(pattern))$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
