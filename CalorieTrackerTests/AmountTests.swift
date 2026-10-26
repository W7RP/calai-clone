import Foundation
import Testing
@testable import CalorieTracker

struct AmountUnitTests {
    @Test func convertsWeightsAndVolumes() throws {
        let water = FoodMeasure()
        #expect(water.grams(1, in: .cups) == 250)
        #expect(water.grams(2, in: .tablespoons) == 30)
        #expect(abs(try #require(water.grams(1, in: .ounces)) - 28.35) < 0.01)
        #expect(water.grams(1, in: .servings) == nil)

        let oil = FoodMeasure(density: 0.92)
        #expect(abs(try #require(oil.grams(1, in: .tablespoons)) - 13.8) < 0.001)
        #expect(abs(try #require(oil.quantity(ofGrams: 27.6, in: .tablespoons)) - 2) < 0.001)
    }

    @Test func servingsNeedAServingSize() {
        #expect(!FoodMeasure().units.contains(.servings))
        #expect(FoodMeasure(servingGrams: 30).units.contains(.servings))
        #expect(!FoodMeasure(servingGrams: 0).units.contains(.servings))
        #expect(FoodMeasure(servingGrams: 30).grams(1.5, in: .servings) == 45)
    }

    @Test func guessesDensityFromWholeWords() {
        #expect(Density.guess(for: "Olive oil") == 0.92)
        #expect(Density.guess(for: "Peanut butter") == 1.08)
        #expect(Density.guess(for: "Boiled eggs") == nil)
        #expect(Density.guess(for: "Huile d'olive") == 0.92)
        #expect(Density.guess(for: "Grilled chicken") == nil)
    }

    @Test func showsFractionsAsGlyphs() {
        #expect(AmountText.quantity(0.5) == "½")
        #expect(AmountText.quantity(1.5) == "1½")
        #expect(AmountText.quantity(0.25) == "¼")
        #expect(AmountText.quantity(2) == "2")
        #expect(AmountText.quantity(1.2) == "1.2")
    }

    @Test func describesEnteredAmounts() {
        #expect(AmountText.describe(grams: 150, entered: nil) == "150 g")
        let cup = EnteredAmount(quantity: 1.5, unitRaw: "cup", servingGrams: nil, density: nil)
        #expect(AmountText.describe(grams: 375, entered: cup) == "1½ cups · 375 g")
    }
}

struct AmountInputTests {
    @Test func changingUnitKeepsTheAmount() throws {
        var amount = AmountInput(grams: 500, measure: FoodMeasure())
        amount.convert(to: .cups)
        #expect(amount.text == "2")
        #expect(amount.grams == 500)
        amount.convert(to: .milliliters)
        #expect(amount.text == "500")
    }

    @Test func reopensInTheUnitItWasEnteredIn() throws {
        let entered = EnteredAmount(quantity: 0.75, unitRaw: "cup", servingGrams: nil, density: 0.41)
        let amount = AmountInput(grams: 76.875, entered: entered, servingGrams: nil, density: nil)
        #expect(amount.unit == .cups)
        #expect(amount.text == "0.75")
    }

    @Test func entryChangedElsewhereReopensFromItsGrams() {
        let entered = EnteredAmount(quantity: 1, unitRaw: "cup", servingGrams: nil, density: 1)
        let amount = AmountInput(grams: 500, entered: entered, servingGrams: nil, density: nil)
        #expect(amount.text == "2")
    }

    @Test func missingServingFallsBackToGrams() {
        let amount = AmountInput(grams: 80, measure: FoodMeasure(), unit: .servings, quantity: 1)
        #expect(amount.unit == .grams)
        #expect(amount.text == "80")
    }

    @Test func stepsSnapToTheGrid() {
        var amount = AmountInput(grams: 137, measure: FoodMeasure())
        amount.step(1)
        #expect(amount.text == "140")
        amount.step(-1)
        #expect(amount.text == "130")

        var cups = AmountInput(grams: 187.5, measure: FoodMeasure(), unit: .cups)
        #expect(cups.text == "0.75")
        cups.step(1)
        #expect(cups.text == "1")
        cups.step(-1)
        #expect(cups.text == "0.75")
    }

    @Test func stepsStopAtZero() {
        var amount = AmountInput(grams: 5, measure: FoodMeasure())
        amount.step(-1)
        #expect(amount.text == "0")
        amount.step(-1)
        #expect(amount.text == "0")
    }

    @Test func hintGivesTheGrams() {
        #expect(AmountInput(grams: 100, measure: FoodMeasure()).hint == nil)
        let water = AmountInput(grams: 250, measure: FoodMeasure(), unit: .cups)
        #expect(water.hint == "= 250 g")
        #expect(water.assumesWater)
        #expect(!AmountInput(grams: 29, measure: FoodMeasure(density: 0.116), unit: .cups).assumesWater)
    }

    /// The cereal case: a cup isn't 250 g. Saying what it weighs fixes the cup and everything scaled from it.
    @Test func correctingWhatACupWeighs() {
        var cereal = NutritionInput(amount: AmountInput(grams: 29, measure: FoodMeasure(servingGrams: 29), unit: .servings),
                                    macros: Macros(kcal: 110, protein: 2, carbs: 24, fat: 1))
        cereal.amount.convert(to: .cups)
        #expect(cereal.amount.text == "0.12")
        cereal.amount.set(1)
        #expect(cereal.kcal == "948")
        cereal.amount.setGramsPerUnit(29)
        #expect(abs((cereal.amount.grams ?? 0) - 29) < 0.001)
        #expect(cereal.kcal == "110")
        cereal.amount.convert(to: .servings)
        #expect(cereal.amount.text == "1")
    }

    @Test func correctingTheServing() {
        var milk = AmountInput(grams: 250, measure: FoodMeasure(servingGrams: 100, density: 1), unit: .milliliters)
        milk.convert(to: .servings)
        #expect(milk.text == "2.5")
        milk.setServingGrams(250)
        #expect(milk.grams == 625)
        milk.set(1)
        #expect(milk.grams == 250)
    }

    @Test func makingAVolumeOneServing() {
        var cereal = AmountInput(grams: 30, measure: FoodMeasure(density: 0.12), unit: .cups, quantity: 1)
        cereal.makeOneServing()
        #expect(cereal.unit == .servings)
        #expect(cereal.text == "1")
        #expect(abs((cereal.measure.servingGrams ?? 0) - 30) < 0.001)
        #expect(abs((cereal.grams ?? 0) - 30) < 0.001)
    }
}

struct NutritionInputTests {
    private let rice = Macros(kcal: 260, protein: 5, carbs: 57, fat: 0.6)

    private func input(grams: Double = 200, macros: Macros? = nil) -> NutritionInput {
        NutritionInput(amount: AmountInput(grams: grams, measure: FoodMeasure(servingGrams: grams)), macros: macros ?? rice)
    }

    @Test func changingTheAmountScalesEverything() {
        var nutrition = input()
        nutrition.amount.text = "300"
        #expect(nutrition.kcal == "390")
        #expect(nutrition.protein == "7.5")
        #expect(nutrition.carbs == "85.5")
        #expect(nutrition.fat == "0.9")
    }

    /// Typing a new amount goes through half-typed and empty values; the result must match typing it at once.
    @Test func typingDigitByDigitLandsOnTheRightValues() {
        var nutrition = input()
        for text in ["20", "2", "", "1", "15", "150"] { nutrition.amount.text = text }
        #expect(nutrition.kcal == "195")
        #expect(abs((nutrition.macros?.carbs ?? 0) - 42.75) < 0.06)
    }

    @Test func multiplesOfAServing() {
        var nutrition = input()
        nutrition.amount.convert(to: .servings)
        nutrition.amount.set(0.5)
        #expect(nutrition.kcal == "130")
        nutrition.amount.set(2)
        #expect(nutrition.kcal == "520")
        #expect(nutrition.amount.grams == 400)
    }

    @Test func typedNutritionBecomesTheNewBasis() {
        var nutrition = input()
        nutrition.kcal = "300"
        nutrition.amount.text = "100"
        #expect(nutrition.kcal == "150")
    }

    @Test func blankMacrosStayBlankAndCountAsZero() throws {
        var nutrition = NutritionInput(amount: AmountInput(grams: 100, measure: FoodMeasure()))
        nutrition.kcal = "50"
        nutrition.amount.text = "200"
        #expect(nutrition.kcal == "100")
        #expect(nutrition.protein == "")
        #expect(try #require(nutrition.macros) == Macros(kcal: 100, protein: 0, carbs: 0, fat: 0))
    }

    @Test func nutritionTypedBeforeTheAmountIsKept() {
        var nutrition = NutritionInput(amount: AmountInput(grams: 0, measure: FoodMeasure()))
        nutrition.amount.text = ""
        nutrition.kcal = "300"
        for text in ["1", "15", "150"] { nutrition.amount.text = text }
        #expect(nutrition.kcal == "300")
        #expect(nutrition.isValid)
    }

    @Test func volumeUsesTheDensity() {
        var nutrition = NutritionInput(amount: AmountInput(grams: 13.8, measure: FoodMeasure(density: 0.92), unit: .tablespoons),
                                       macros: Macros(kcal: 124, protein: 0, carbs: 0, fat: 13.8))
        #expect(nutrition.amount.text == "1")
        nutrition.amount.set(2)
        #expect(nutrition.kcal == "248")
        #expect(nutrition.fat == "27.6")
    }
}

struct ServingSizeTests {
    @Test func readsHouseholdMeasureAndWeight() {
        #expect(ServingSize.parse("1 cup (29 g)") == .init(grams: 29, milliliters: 250, household: true))
        #expect(ServingSize.parse("3/4 cup (30g)") == .init(grams: 30, milliliters: 187.5, household: true))
        #expect(ServingSize.parse("1 1/2 cups (45 g)") == .init(grams: 45, milliliters: 375, household: true))
        #expect(ServingSize.parse("¾ tasse (28 g)") == .init(grams: 28, milliliters: 187.5, household: true))
        #expect(ServingSize.parse("2 c. à soupe (30 g)") == .init(grams: 30, milliliters: 30, household: true))
    }

    @Test func metricVolumeWinsOverHouseholdMeasure() {
        #expect(ServingSize.parse("1 tasse (250 mL)").milliliters == 250)
        #expect(ServingSize.parse("8 fl oz (240 mL)").milliliters == 240)
        #expect(ServingSize.parse("250,5 ml").milliliters == 250.5)
    }

    @Test func ignoresWordsThatStartLikeUnits() {
        #expect(ServingSize.parse("1 large egg (50 g)") == .init(grams: 50, milliliters: nil))
        #expect(ServingSize.parse("1 portion") == .init())
        #expect(ServingSize.parse("") == .init())
    }
}
