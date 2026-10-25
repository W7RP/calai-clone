import Foundation

/// Values for a food before it's saved, from Open Food Facts or typed in.
struct FoodDraft: Equatable, Sendable {
    var name: String
    var brand: String?
    var barcode: String?
    var per100g: Macros
    var servingGrams: Double?
    var source: FoodSource
    /// Grams per mL. 1 for drinks and other liquids, whose values OFF gives per 100 mL.
    var density: Double? = nil
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

    private static let fields = "code,product_name,product_name_en,product_name_fr,brands,nutriments,serving_quantity,serving_quantity_unit,product_quantity_unit"

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

        return FoodDraft(
            name: names.first ?? "Product \(barcode)",
            brand: brand?.isEmpty == false ? brand : nil,
            barcode: barcode,
            per100g: Macros(kcal: kcal,
                            protein: number(nutriments["proteins_100g"]) ?? 0,
                            carbs: number(nutriments["carbohydrates_100g"]) ?? 0,
                            fat: number(nutriments["fat_100g"]) ?? 0),
            servingGrams: number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil },
            source: .off,
            density: isLiquid(product) ? 1 : nil)
    }

    /// Liquids are sold and labelled by volume. OFF keeps their values under the _100g keys but they're
    /// per 100 mL, so 1 g per mL makes a volume come out right.
    private static func isLiquid(_ product: [String: Any]) -> Bool {
        let volumes: Set<String> = ["ml", "cl", "dl", "l", "fl oz"]
        return ["serving_quantity_unit", "product_quantity_unit"].contains { key in
            (product[key] as? String).map { volumes.contains($0.lowercased().trimmingCharacters(in: .whitespaces)) } ?? false
        }
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
