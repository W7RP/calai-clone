import Foundation

/// One item the model identified. Numbers are for the portion, not per 100 g.
struct EstimatedItem: Equatable, Sendable {
    enum Confidence: String, Sendable { case high, medium, low }

    var name: String
    var grams: Double
    var macros: Macros
    var confidence: Confidence
    var fromLabel: Bool

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
            let confidence: String?
            let source: String?
        }
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
                fromLabel: item.source?.lowercased() == "label")
        }
        let note = wire.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodEstimate(items: items, note: note?.isEmpty == false ? note : nil)
    }
}
