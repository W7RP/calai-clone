import Foundation

/// One item the model identified. Numbers are for the portion, not per 100 g.
struct EstimatedItem: Equatable, Sendable {
    enum Confidence: String, Sendable { case high, medium, low }

    var name: String
    var grams: Double
    var macros: Macros
    var confidence: Confidence
    var fromLabel: Bool
    /// Volume, for drinks and foods usually measured by volume. Gives the density for cups and spoons.
    var milliliters: Double? = nil

    /// Grams per mL, when the volume is known and physically plausible.
    var density: Double? {
        guard let milliliters, milliliters > 0, grams > 0 else { return nil }
        let density = grams / milliliters
        return (0.05...2.5).contains(density) ? density : nil
    }

    /// Stored on LogEntry.aiConfidence.
    var confidenceScore: Double {
        switch confidence {
        case .high: 0.9
        case .medium: 0.6
        case .low: 0.3
        }
    }
}

struct FoodEstimate: Equatable, Sendable {
    var items: [EstimatedItem]
    var note: String?
    /// The model's short account of what it saw and assumed.
    var analysis: String?
    /// Soft problems found by `EstimateValidator`, shown on the review screen.
    var warnings: [String] = []
}

enum FoodEstimateParser {
    private struct Wire: Decodable {
        struct Item: Decodable {
            let name: String
            let grams: Double
            let kcal: Double
            let protein_g: Double?
            let carbs_g: Double?
            let fat_g: Double?
            let ml: Double?
            let confidence: String?
            let source: String?
        }
        let analysis: String?
        let items: [Item]
        let note: String?
    }

    /// Strict decode of the model's JSON. Tolerates a ```json fence or stray text around the object,
    /// but a bad or partial object is an error, never a partial entry.
    static func parse(_ text: String) throws -> FoodEstimate {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw AIError.unreadable
        }
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: Data(text[start...end].utf8))
        } catch {
            throw AIError.unreadable
        }

        let items = try wire.items.map { item -> EstimatedItem in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let numbers = [item.grams, item.kcal, item.protein_g ?? 0, item.carbs_g ?? 0, item.fat_g ?? 0]
            guard !name.isEmpty, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw AIError.unreadable }
            return EstimatedItem(
                name: name,
                grams: item.grams,
                macros: Macros(kcal: item.kcal, protein: item.protein_g ?? 0, carbs: item.carbs_g ?? 0, fat: item.fat_g ?? 0),
                confidence: EstimatedItem.Confidence(rawValue: item.confidence?.lowercased() ?? "") ?? .low,
                fromLabel: item.source?.lowercased() == "label",
                milliliters: item.ml.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
        }
        return FoodEstimate(items: items, note: nonEmpty(wire.note), analysis: nonEmpty(wire.analysis))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// Physical sanity checks on a parsed estimate. Hard problems mean the answer is asked for again;
/// soft ones are passed to the review screen as warnings.
enum EstimateValidator {
    static let maxItems = 30
    static let maxGramsPerItem = 4_000.0
    static let maxKcalPerItem = 6_000.0
    /// Pure fat is 9 kcal/g; allow a little rounding.
    static let maxKcalPerGram = 9.3

    struct Result: Equatable {
        var hardProblems: [String]
        var warnings: [String]
    }

    static func check(_ estimate: FoodEstimate) -> Result {
        var hard: [String] = []
        var soft: [String] = []
        if estimate.items.count > maxItems { hard.append("\(estimate.items.count) items is more than a meal") }

        for item in estimate.items {
            let m = item.macros
            let macroMass = m.protein + m.carbs + m.fat
            if item.grams > maxGramsPerItem { hard.append("\(item.name): \(whole(item.grams)) g is more than one portion") }
            if m.kcal > maxKcalPerItem { hard.append("\(item.name): \(whole(m.kcal)) kcal is more than one portion") }
            if item.grams <= 0, m.kcal > 0 { hard.append("\(item.name) has energy but no weight") }
            if item.grams > 0, m.kcal / item.grams > maxKcalPerGram {
                hard.append("\(item.name) has \(String(format: "%.1f", m.kcal / item.grams)) kcal per gram, more than pure fat")
            }
            if item.grams > 0, macroMass > item.grams * 1.05 + 1 {
                hard.append("\(item.name)'s protein, carbs and fat weigh more than the item")
            }
            // Atwater check, loose because of fibre, polyols and rounding. Skipped when macros are missing.
            // Alcohol (7 kcal/g) isn't in the schema, so drinks can legitimately come out high.
            let fromMacros = Nutrition.kcalFromMacros(protein: m.protein, carbs: m.carbs, fat: m.fat)
            if macroMass > 0, abs(m.kcal - fromMacros) > max(40, 0.25 * max(m.kcal, fromMacros)) {
                soft.append("\(item.name): \(whole(m.kcal)) kcal doesn't match its macros (about \(whole(fromMacros)) kcal). Check before saving.")
            }
        }
        return Result(hardProblems: hard, warnings: soft)
    }

    /// Formats without trapping on absurd values, which is exactly what this check is for.
    private static func whole(_ value: Double) -> String { NumberInput.format(value, maxFractionDigits: 0) }
}
