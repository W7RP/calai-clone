import Foundation

/// USDA FoodData Central's branded foods, used only for what a serving is in household terms ("1 cup")
/// when Open Food Facts doesn't say. Covers most US-labelled products; uses the shared demo key, which
/// allows a few dozen lookups an hour per device.
struct FoodDataCentralClient: Sendable {
    struct Serving: Equatable, Sendable {
        /// "1 cup (29 g)"
        var text: String
        var grams: Double?
        var milliliters: Double?
    }

    var apiKey = "DEMO_KEY"

    func serving(barcode: String) async -> Serving? {
        // USDA keeps 12-digit UPCs; a scanned EAN-13 of a US product has an extra leading zero.
        var codes = [barcode]
        if barcode.count == 13, barcode.hasPrefix("0") { codes.append(String(barcode.dropFirst())) }
        for code in codes {
            if let found = await search(code, barcode: barcode) { return found }
        }
        return nil
    }

    private func search(_ code: String, barcode: String) async -> Serving? {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "query", value: code),
            URLQueryItem(name: "pageSize", value: "5"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.map(data, barcode: barcode)
    }

    static func map(_ data: Data, barcode: String) -> Serving? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { return nil }
        let wanted = digits(barcode)
        // The search is full text, so only an exact barcode match counts.
        guard let food = foods.first(where: { ($0["gtinUpc"] as? String).map(digits) == wanted }) else { return nil }

        let household = (food["householdServingFullText"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let size = (food["servingSize"] as? NSNumber)?.doubleValue
        let unit = (food["servingSizeUnit"] as? String)?.lowercased() ?? ""
        let printed = ServingSize.parse(household)
        var serving = Serving(text: household, grams: nil, milliliters: printed.milliliters)
        if let size, size > 0 {
            if ["g", "grm"].contains(unit) { serving.grams = size }
            if ["ml", "mlt"].contains(unit) { serving.milliliters = serving.milliliters ?? size }
            let shown = "\(NumberInput.format(size)) \(["ml", "mlt"].contains(unit) ? "mL" : "g")"
            serving.text = household.isEmpty ? shown : "\(household) (\(shown))"
        }
        guard serving.grams != nil || serving.milliliters != nil else { return nil }
        return serving
    }

    /// Barcodes are stored with and without leading zeros, so they're compared without them.
    private static func digits(_ code: String) -> String {
        let only = code.filter(\.isNumber)
        let trimmed = only.drop { $0 == "0" }
        return trimmed.isEmpty ? only : String(trimmed)
    }
}
