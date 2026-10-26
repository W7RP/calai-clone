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
    /// The label's serving as printed, e.g. "1 cup (29 g)".
    var servingText: String? = nil
    /// Where the density came from, so weaker guesses can be improved and the amount screen can say so.
    var densitySource: DensitySource? = nil
    /// True when the printed serving names a cup, spoon or fl oz, so it's the label's own serving.
    var servingFromLabel = false
    /// Open Food Facts category tags, for describing the product to the AI when nothing else gives a cup weight.
    var categories: [String] = []
}

/// Where a food's grams-per-mL came from, best first.
enum DensitySource: String, Sendable {
    /// The serving text gave both a volume and a weight, like "1 cup (29 g)".
    case label
    /// A drink or other liquid, whose values are per 100 mL.
    case liquid
    /// USDA FoodData Central's household serving for the same barcode.
    case usda
    /// The user's AI model, asked what a cup of this product weighs.
    case ai
    /// A typical value for the product's category.
    case category
    /// Typed in on the amount screen.
    case user

    /// Finishes "1 cup weighs 29 g, …".
    var note: String {
        switch self {
        case .label: "from the label"
        case .liquid: "as a liquid"
        case .usda: "from USDA's data for this barcode"
        case .ai: "estimated by your AI model"
        case .category: "typical for this kind of food"
        case .user: "as you set it"
        }
    }

    /// Good enough that nothing else is looked up.
    var isReliable: Bool { self == .label || self == .liquid || self == .usda || self == .user }
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

    private static let fields = "code,product_name,product_name_en,product_name_fr,brands,nutriments,serving_quantity,serving_quantity_unit,serving_size,product_quantity_unit,quantity,categories_tags"

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
        let measures = servingMeasures(product, servingText: servingText)
        let categories = product["categories_tags"] as? [String] ?? []

        return FoodDraft(
            name: names.first ?? "Product \(barcode)",
            brand: brand?.isEmpty == false ? brand : nil,
            barcode: barcode,
            per100g: Macros(kcal: kcal,
                            protein: number(nutriments["proteins_100g"]) ?? 0,
                            carbs: number(nutriments["carbohydrates_100g"]) ?? 0,
                            fat: number(nutriments["fat_100g"]) ?? 0),
            servingGrams: measures.servingGrams,
            source: .off,
            density: measures.density,
            servingText: servingText?.isEmpty == false ? servingText : nil,
            densitySource: measures.densitySource,
            servingFromLabel: measures.servingFromLabel,
            categories: categories)
    }

    /// The serving size and density, from the printed serving ("1 cup (29 g)" gives both) and OFF's own fields.
    struct ServingMeasures: Equatable {
        var servingGrams: Double?
        var density: Double?
        var densitySource: DensitySource?
        var servingFromLabel: Bool
    }

    static func servingMeasures(_ product: [String: Any], servingText: String?) -> ServingMeasures {
        let printed = ServingSize.parse(servingText ?? "")
        let quantity = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let quantityIsVolume = isVolume(product["serving_quantity_unit"])

        // Liquids are sold and labelled by volume, and OFF's _100g values for them are per 100 mL, so they
        // count as 1 g per mL and a serving's "grams" are its millilitres.
        if isLiquid(product) {
            return ServingMeasures(servingGrams: printed.milliliters ?? quantity ?? printed.grams, density: 1,
                                   densitySource: .liquid, servingFromLabel: printed.household)
        }
        let grams = printed.grams ?? (quantityIsVolume ? nil : quantity)
        if let grams, let milliliters = printed.milliliters, milliliters > 0, (0.05...2.5).contains(grams / milliliters) {
            return ServingMeasures(servingGrams: grams, density: grams / milliliters, densitySource: .label,
                                   servingFromLabel: true)
        }
        // Many entries only keep the weight ("29 g") and drop the "1 cup". The category still says roughly
        // what a cup weighs, which beats treating cereal as water, until something better is found.
        let category = Density.guess(categories: product["categories_tags"] as? [String] ?? [])
        return ServingMeasures(servingGrams: grams ?? quantity, density: category,
                               densitySource: category == nil ? nil : .category, servingFromLabel: printed.household)
    }

    private static func isLiquid(_ product: [String: Any]) -> Bool {
        if isVolume(product["serving_quantity_unit"]) || isVolume(product["product_quantity_unit"]) { return true }
        // "2 L" or "473 mL" on the package, with no weight.
        let size = ServingSize.parse(product["quantity"] as? String ?? "")
        return size.milliliters != nil && size.grams == nil
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
