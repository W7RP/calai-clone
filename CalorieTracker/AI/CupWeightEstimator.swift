import Foundation

/// Asks the user's own model what a cup of a packaged food weighs, for products whose data gives only a
/// weight per serving. A short text request; nothing is sent when no provider is set up.
struct CupWeightEstimator: Sendable {
    let client: any LLMClient
    var timeout: Duration = .seconds(8)

    static func current() -> CupWeightEstimator? {
        guard let client = try? LLMClientFactory.make(AIProviderSettings.config(for: AIProviderSettings.activeProvider)) else {
            return nil
        }
        return CupWeightEstimator(client: client)
    }

    static let schema = OutputSchema(name: "cup_weight", root: .object([
        ("grams_per_cup", .number(description: "Grams in one level 250 mL cup of this product as sold.")),
    ]))

    static let system = """
    You know typical food densities. Given a packaged food, reply with the weight in grams of one level \
    250 mL cup of it as sold (dry cereal as poured, not cooked; liquids as they are). Use the label serving if \
    one is given. Reply with one JSON object and nothing else: {"grams_per_cup":number}
    """

    static func prompt(name: String, brand: String?, categories: [String], servingText: String?) -> String {
        var lines = ["Product: \(name)"]
        if let brand { lines.append("Brand: \(brand)") }
        let kinds = categories.map { $0.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ") }
        if !kinds.isEmpty { lines.append("Categories: \(kinds.suffix(4).joined(separator: ", "))") }
        if let servingText, !servingText.isEmpty { lines.append("Label serving: \(servingText)") }
        return lines.joined(separator: "\n")
    }

    /// Grams per mL, or nil when the model can't be reached in time or answers something implausible.
    func gramsPerMilliliter(name: String, brand: String?, categories: [String], servingText: String?) async -> Double? {
        let request = LLMRequest(system: Self.system,
                                 messages: [.user(.text(Self.prompt(name: name, brand: brand, categories: categories,
                                                                    servingText: servingText)))],
                                 schema: Self.schema, maxOutputTokens: 4_000)
        let client = client
        let timeout = timeout
        let reply: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await client.complete(request) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return reply.flatMap(Self.parse)
    }

    static func parse(_ text: String) -> Double? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let json = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let grams = (json["grams_per_cup"] as? NSNumber)?.doubleValue else { return nil }
        let density = grams / 250
        return (0.03...2.0).contains(density) ? density : nil
    }
}
