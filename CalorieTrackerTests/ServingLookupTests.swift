import Foundation
import Testing
@testable import CalorieTracker

private struct FixedReply: LLMClient {
    let reply: String
    var provider: ProviderKind { .anthropic }
    func complete(_ request: LLMRequest) async throws -> String { reply }
    func listModels() async throws -> [LLMModel] { [] }
}

struct FoodDataCentralMappingTests {
    @Test func readsHouseholdServingForTheSameBarcode() throws {
        let json = #"{"foods":[{"gtinUpc":"012345678905","servingSize":2,"servingSizeUnit":"g","householdServingFullText":"1 tsp"},{"gtinUpc":"068200148540","servingSize":29,"servingSizeUnit":"g","householdServingFullText":"1 cup"}]}"#
        let serving = try #require(FoodDataCentralClient.map(Data(json.utf8), barcode: "0068200148540"))
        #expect(serving.grams == 29)
        #expect(serving.milliliters == 250)
        #expect(serving.text == "1 cup (29 g)")
    }

    @Test func drinksComeInMillilitres() throws {
        let json = #"{"foods":[{"gtinUpc":"068200148540","servingSize":250,"servingSizeUnit":"MLT","householdServingFullText":"1 cup"}]}"#
        let serving = try #require(FoodDataCentralClient.map(Data(json.utf8), barcode: "068200148540"))
        #expect(serving.grams == nil)
        #expect(serving.milliliters == 250)
    }

    @Test func otherBarcodesDontCount() {
        let json = #"{"foods":[{"gtinUpc":"099999999999","servingSize":29,"servingSizeUnit":"g","householdServingFullText":"1 cup"}]}"#
        #expect(FoodDataCentralClient.map(Data(json.utf8), barcode: "068200148540") == nil)
    }
}

struct CupWeightEstimatorTests {
    @Test func readsGramsPerCup() {
        #expect(CupWeightEstimator.parse(#"{"grams_per_cup":30}"#) == 0.12)
        #expect(CupWeightEstimator.parse("```json\n{\"grams_per_cup\": 250}\n```") == 1)
        #expect(CupWeightEstimator.parse(#"{"grams_per_cup":0}"#) == nil)
        #expect(CupWeightEstimator.parse("about 30 g") == nil)
    }

    @Test func describesTheProduct() {
        let text = CupWeightEstimator.prompt(name: "Corn Flakes", brand: "Kellogg's",
                                             categories: ["en:cereals-and-their-products", "en:breakfast-cereals"],
                                             servingText: "29 g")
        #expect(text.contains("Corn Flakes"))
        #expect(text.contains("breakfast cereals"))
        #expect(text.contains("Label serving: 29 g"))
    }
}

struct ServingLookupTests {
    private func cereal(servingText: String = "29 g") -> FoodDraft {
        FoodDraft(name: "Flakes", barcode: "0068200148540", per100g: Macros(kcal: 380, protein: 7, carbs: 84, fat: 1),
                  servingGrams: 29, source: .off, density: 0.13, servingText: servingText, densitySource: .category,
                  categories: ["en:breakfast-cereals"])
    }

    @Test func usdaFillsInTheCup() async {
        let lookup = ServingLookup(usda: { _ in .init(text: "1 cup (29 g)", grams: 29, milliliters: 250) },
                                   estimator: { nil })
        let done = await lookup.complete(cereal())
        #expect(done.densitySource == .usda)
        #expect(abs((done.density ?? 0) - 0.116) < 0.001)
        #expect(done.servingText == "1 cup (29 g)")
        #expect(done.servingFromLabel)
    }

    @Test func aiFillsInWhenUSDAHasNothing() async {
        let lookup = ServingLookup(usda: { _ in nil },
                                   estimator: { CupWeightEstimator(client: FixedReply(reply: #"{"grams_per_cup":30}"#)) })
        let done = await lookup.complete(cereal())
        #expect(done.densitySource == .ai)
        #expect(done.density == 0.12)
    }

    @Test func categoryStaysWhenNothingElseAnswers() async {
        let lookup = ServingLookup(usda: { _ in nil }, estimator: { nil })
        let done = await lookup.complete(cereal())
        #expect(done.densitySource == .category)
        #expect(done.density == 0.13)
    }

    @Test func labelAnswersAreLeftAlone() async {
        var draft = cereal(servingText: "1 cup (29 g)")
        draft.densitySource = .label
        draft.servingFromLabel = true
        let lookup = ServingLookup(usda: { _ in Issue.record("shouldn't look up"); return nil }, estimator: { nil })
        #expect(await lookup.complete(draft) == draft)
    }

    /// A drink whose OFF serving is a bare "100 ml" takes the label's real serving from USDA.
    @Test func milkTakesTheServingFromUSDA() async {
        let milk = FoodDraft(name: "Milk", barcode: "0068200148540", per100g: Macros(kcal: 50, protein: 3.4, carbs: 4.8, fat: 2),
                             servingGrams: 100, source: .off, density: 1, servingText: "100 ml", densitySource: .liquid)
        let lookup = ServingLookup(usda: { _ in .init(text: "1 cup (250 mL)", grams: nil, milliliters: 250) },
                                   estimator: { Issue.record("liquids don't need the AI"); return nil })
        let done = await lookup.complete(milk)
        #expect(done.servingGrams == 250)
        #expect(done.density == 1)
    }
}
