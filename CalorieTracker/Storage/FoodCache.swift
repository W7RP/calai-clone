import Foundation
import SwiftData

enum FoodCache {
    /// Updates the cached food with the same barcode, or the same name and source, instead of adding duplicates.
    @MainActor
    @discardableResult
    static func upsert(in context: ModelContext, name: String, barcode: String? = nil, per100g: Macros,
                       servingGrams: Double?, source: FoodSource) -> FoodItem {
        let raw = source.rawValue
        let sameSource = (try? context.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.sourceRaw == raw }))) ?? []
        let match = sameSource.first { food in
            if let barcode, food.barcode == barcode { return true }
            return food.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        let item = match ?? FoodItem(name: name, per100g: per100g, source: source)
        if match == nil { context.insert(item) }
        item.name = name
        item.kcalPer100g = per100g.kcal
        item.proteinPer100g = per100g.protein
        item.carbsPer100g = per100g.carbs
        item.fatPer100g = per100g.fat
        item.servingGrams = servingGrams
        item.barcode = barcode ?? item.barcode
        item.lastUsed = .now
        return item
    }
}
