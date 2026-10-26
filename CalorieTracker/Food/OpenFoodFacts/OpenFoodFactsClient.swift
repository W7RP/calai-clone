import Foundation

/// Values for a food before it's saved, from Open Food Facts or typed in.
struct FoodDraft: Equatable, Sendable {
    var name: String
    var brand: String?
    var barcode: String?
    var per100g: Macros
    var servingGrams: Double?
    var source: FoodSource
    /// Drinks, measured in mL. OFF gives their values per 100 mL.
    var isLiquid = false
    /// Grams (mL for drinks) in each cup or spoon the label names, like 118 for "1 cup (118 g)".
    var unitGrams: [AmountUnit: Double] = [:]
    /// The label's serving as printed, e.g. "1 cup (29 g)".
    var servingText: String? = nil

    var measure: FoodMeasure { FoodMeasure(servingGrams: servingGrams, isLiquid: isLiquid, unitGrams: unitGrams) }
}

/// Product lookup by barcode. Free and keyless; asks for a descriptive User-Agent.
struct OpenFoodFactsClient: Sendable {
    enum LookupError: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let status): "Open Food Facts returned HTTP \(status). Try again or enter it manually."
            }
        }
    }

    private static let fields = "code,product_name,product_name_en,product_name_fr,brands,nutriments,serving_quantity,serving_quantity_unit,serving_size,product_quantity_unit,quantity"

    /// Nil when the product isn't in the database or has no usable energy value.
    func product(barcode: String) async throws -> FoodDraft? {
        if let found = try await fetch(barcode) { return found }
        // A UPC-A padded to EAN-13 is sometimes stored under its 12-digit form.
        if barcode.count == 13, barcode.hasPrefix("0") {
            return try await fetch(String(barcode.dropFirst()))
                .map { draft in var d = draft; d.barcode = barcode; return d }
        }
        return nil
    }

    private func fetch(_ barcode: String) async throws -> FoodDraft? {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        var request = URLRequest(url: components.url!)
        request.setValue("EasyCal/0.1 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // OFF answers 404 for unknown barcodes.
        if status == 404 { return nil }
        guard status == 200 else { throw LookupError.http(status) }
        return Self.map(data, barcode: barcode)
    }

    static func map(_ data: Data, barcode: String) -> FoodDraft? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int ?? number(json["status"]).map(Int.init)) == 1,
              let product = json["product"] as? [String: Any],
              let nutriments = product["nutriments"] as? [String: Any] else { return nil }

        // Some products only carry kJ.
        let kcal = number(nutriments["energy-kcal_100g"]) ?? number(nutriments["energy_100g"]).map { $0 / 4.184 }
        guard let kcal else { return nil }

        let names = ["product_name", "product_name_en", "product_name_fr"]
            .compactMap { (product[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let servingText = (product["serving_size"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let units = measure(product, servingText: servingText)

        return FoodDraft(
            name: names.first ?? "Product \(barcode)",
            brand: brand?.isEmpty == false ? brand : nil,
            barcode: barcode,
            per100g: Macros(kcal: kcal,
                            protein: number(nutriments["proteins_100g"]) ?? 0,
                            carbs: number(nutriments["carbohydrates_100g"]) ?? 0,
                            fat: number(nutriments["fat_100g"]) ?? 0),
            servingGrams: units.servingGrams,
            source: .off,
            isLiquid: units.isLiquid,
            unitGrams: units.unitGrams,
            servingText: servingText?.isEmpty == false ? servingText : nil)
    }

    /// The serving and the units the label gives. Only units printed with an amount are offered: "1 cup (118 g)"
    /// gives grams, the serving and a 118 g cup; "118 g" alone gives grams and the serving, never a cup.
    static func measure(_ product: [String: Any], servingText: String?) -> FoodMeasure {
        let printed = ServingSize.parse(servingText ?? "")
        let quantity = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let quantityUnit = (product["serving_quantity_unit"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces)

        // Drinks are measured in mL; a cup or spoon on the label is its share of the serving: "1 cup (250 mL)".
        if isLiquid(product, printed: printed) {
            let serving = quantity ?? printed.milliliters
            var units: [AmountUnit: Double] = [:]
            if let serving {
                for (unit, count) in printed.volumes where unit != .milliliters { units[unit] = serving / count }
            }
            return FoodMeasure(servingGrams: serving, isLiquid: true, unitGrams: units)
        }
        // OFF's own serving weight is right far more often than not; the printed weight fills in when it has none.
        let grams = quantityUnit == nil || quantityUnit == "g" ? (quantity ?? printed.grams) : printed.grams
        var units: [AmountUnit: Double] = [:]
        if let weight = printed.grams ?? grams {
            for (unit, count) in printed.volumes { units[unit] = weight / count }
        }
        return FoodMeasure(servingGrams: grams, unitGrams: units)
    }

    /// Only an explicit volume counts. A serving printed in grams is never a liquid, whatever else says so.
    private static func isLiquid(_ product: [String: Any], printed: ServingSize.Parsed) -> Bool {
        let quantityUnit = product["serving_quantity_unit"]
        if isVolume(quantityUnit) { return true }
        if printed.grams != nil || (quantityUnit as? String)?.lowercased() == "g" { return false }
        if isVolume(product["product_quantity_unit"]) { return true }
        // "2 L" or "473 mL" on the package, with no weight.
        let size = ServingSize.parse(product["quantity"] as? String ?? "")
        return size.milliliters != nil && size.grams == nil && !size.household
    }

    private static func isVolume(_ unit: Any?) -> Bool {
        let volumes: Set<String> = ["ml", "cl", "dl", "l", "fl oz"]
        return (unit as? String).map { volumes.contains($0.lowercased().trimmingCharacters(in: .whitespaces)) } ?? false
    }

    /// OFF sends numbers either as JSON numbers or as strings, sometimes with a comma.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }
}
