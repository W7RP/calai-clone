import Foundation

/// Fills in what a serving is and what a cup weighs when Open Food Facts doesn't say: USDA's household
/// serving for the same barcode first, then the user's AI model. Category guesses stay as the last resort.
struct ServingLookup: Sendable {
    var usda: @Sendable (String) async -> FoodDataCentralClient.Serving? = { await FoodDataCentralClient().serving(barcode: $0) }
    var estimator: @Sendable () -> CupWeightEstimator? = { CupWeightEstimator.current() }

    func complete(_ draft: FoodDraft) async -> FoodDraft {
        let isLiquid = draft.densitySource == .liquid
        var needsServing = !draft.servingFromLabel
        var needsDensity = !isLiquid && !(draft.densitySource?.isReliable ?? false)
        guard needsServing || needsDensity else { return draft }
        var result = draft

        if let barcode = draft.barcode, let serving = await usda(barcode) {
            if needsServing, ServingSize.parse(serving.text).household {
                // A barcode's own serving weight is never replaced; USDA only fills one that's missing,
                // or a drink's bare "100 ml" with the label's cup.
                if isLiquid {
                    result.servingGrams = serving.milliliters ?? result.servingGrams
                    result.servingText = serving.text
                } else if let own = result.servingGrams {
                    // Same serving described better ("29 g" -> "1 cup (29 g)"): take the description only.
                    if let grams = serving.grams, abs(grams - own) <= own * 0.02 { result.servingText = serving.text }
                } else {
                    result.servingGrams = serving.grams
                    result.servingText = serving.text
                }
                result.servingFromLabel = true
                needsServing = false
            }
            if needsDensity, let grams = serving.grams, let milliliters = serving.milliliters, milliliters > 0,
               (0.03...2.5).contains(grams / milliliters) {
                result.density = grams / milliliters
                result.densitySource = .usda
                needsDensity = false
            }
        }

        if needsDensity, let estimator = estimator(),
           let density = await estimator.gramsPerMilliliter(name: result.name, brand: result.brand,
                                                            categories: result.categories, servingText: result.servingText) {
            result.density = density
            result.densitySource = .ai
        }
        return result
    }
}
