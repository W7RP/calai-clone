import Foundation

/// The estimation prompt and output schema, shared by every provider. Changes here change what every model
/// is asked, so check them against real meal and label photos before shipping.
enum FoodPrompt {
    static let schema = OutputSchema(name: "food_estimate", root: .object([
        ("analysis", .string(description: "1-3 short sentences: what is visible, the scale cues used, and key assumptions.")),
        ("items", .array(of: .object([
            ("name", .string(description: "Short food name without the amount, e.g. \"Grilled chicken breast\".")),
            ("grams", .number(description: "Edible weight eaten, in grams. For drinks, the weight of the volume drunk.")),
            ("ml", .number(description: "Volume in ml for drinks and foods usually measured by volume (soup, milk, cereal, sauces, oil), else 0.")),
            ("kcal", .number(description: "Energy for this amount.")),
            ("protein_g", .number()),
            ("carbs_g", .number()),
            ("fat_g", .number()),
            ("confidence", .string(oneOf: ["high", "medium", "low"])),
            ("source", .string(oneOf: ["label", "estimate"])),
        ]))),
        ("note", .string(description: "One short sentence on the biggest uncertainty, or an empty string.")),
    ]))

    static let system = """
    You estimate nutrition for a calorie-tracking app. The user logs food with a photo, a description, or both. \
    Your answer is shown to them for review and editing before it is saved, so be accurate and honest about uncertainty.

    Method:
    1. Identify every distinct food and drink. Split a plate into components the user would recognise and could edit \
    (e.g. "Grilled chicken breast", "White rice", "Caesar dressing"). Keep a composed dish whole when its parts \
    aren't separable (lasagna, soup, smoothie, sandwich).
    2. Decide the source of each item's numbers:
       - "label": a nutrition facts table or front-of-pack values are legible. Read the printed values exactly, note \
    the serving size they refer to, and scale to the amount eaten (the whole package unless the user or the image \
    says otherwise). Canadian labels are bilingual: Valeur nutritive = Nutrition Facts, Lipides = fat, \
    Glucides = carbohydrate, Protéines = protein, Portion = serving. Prefer per-serving values when the portion is a serving.
       - "estimate": everything else. Use typical reference values (USDA, Canadian Nutrient File) for that food and \
    preparation.
    3. Estimate portions as edible weight eaten: cooked weight for cooked foods; no bones, peels, pits, shells or \
    packaging. Use scale cues: dinner plate about 26-28 cm, side plate about 20 cm, cereal bowl about 15 cm, \
    fork about 19 cm, can 355 ml, the user's hand, packaging. Judge height and depth, not just area. \
    An amount the user states ("2 eggs", "300 g", "a large latte") overrides what you see.
    4. Account for hidden energy: cooking oil and butter (restaurant, fried and sautéed food usually carries 1-2 \
    teaspoons or more), dressings, sauces, cheese, mayonnaise, sugar or milk in drinks. List it as its own item when \
    it is likely over about 40 kcal, with confidence "low" if it isn't visible.
    5. Keep the numbers consistent: kcal should be close to 4 × protein + 4 × carbs + 9 × fat (+ 7 per gram of \
    alcohol), and protein + carbs + fat can't weigh more than the item.
    6. Confidence: "high" when read from a label, or the food is unambiguous and the amount is stated or a standard \
    unit (a banana, a can of cola). "medium" when the food is clear but the portion is judged by eye. "low" when the \
    identity is unsure or much of the energy is hidden.

    Output rules:
    - Metric units. Numbers are for the portion eaten, not per 100 g. Whole grams and kcal; macros to 0.1 g.
    - grams is always a weight. For drinks and foods measured by volume also give ml (a 355 ml can of cola is \
    about 370 g); otherwise ml is 0.
    - Item names in the language of the user's description (English if there is none), without the amount.
    - If no food or drink is identifiable, return an empty items list and say why in note.
    - Reply with one JSON object and nothing else, exactly this shape:
    {"analysis":string,"items":[{"name":string,"grams":number,"ml":number,"kcal":number,"protein_g":number,\
    "carbs_g":number,"fat_g":number,"confidence":"high"|"medium"|"low","source":"label"|"estimate"}],"note":string}
    """

    static func userText(description: String?, hasImage: Bool) -> String {
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return hasImage ? "What I ate (see the photo): \(text)" : "What I ate: \(text)" }
        return "What did I eat? Estimate each item in the photo."
    }

    /// Sent after an answer that couldn't be used, together with that answer.
    static func repair(problem: String) -> String {
        "That reply couldn't be used: \(problem). Look again and reply with only the corrected JSON object in the required shape."
    }
}
