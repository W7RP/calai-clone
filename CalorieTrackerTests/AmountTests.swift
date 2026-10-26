import Foundation
import Testing
@testable import CalorieTracker

struct FoodMeasureTests {
    private let granola = FoodMeasure(servingGrams: 118, unitGrams: [.cups: 118])

    @Test func offersOnlyTheUnitsItWasGiven() {
        #expect(FoodMeasure().units == [.grams])
        #expect(FoodMeasure(servingGrams: 30).units == [.grams, .servings])
        #expect(granola.units == [.grams, .servings, .cups])
        #expect(FoodMeasure().grams(per: .cups) == nil)
        #expect(FoodMeasure().grams(per: .ounces) == nil)
    }

    @Test func convertsWithTheLabelsOwnWeights() throws {
        #expect(granola.grams(0.5, in: .cups) == 59)
        #expect(granola.grams(1, in: .servings) == 118)
        #expect(granola.quantity(ofGrams: 236, in: .cups) == 2)
        let butter = FoodMeasure(servingGrams: 30, unitGrams: [.tablespoons: 15])
        #expect(butter.grams(1, in: .tablespoons) == 15)
        #expect(butter.grams(1, in: .teaspoons) == nil)
    }

    @Test func drinksAreMeasuredInMillilitres() {
        let milk = FoodMeasure(servingGrams: 250, isLiquid: true, unitGrams: [.cups: 250])
        #expect(milk.baseUnit == .milliliters)
        #expect(milk.units == [.milliliters, .servings, .cups])
        #expect(milk.grams(250, in: .milliliters) == 250)
        #expect(milk.quantity(ofGrams: 250, in: .servings) == 1)
        #expect(!milk.units.contains(.grams))
    }

    @Test func servingsNeedAServingSize() {
        #expect(!FoodMeasure(servingGrams: 0).units.contains(.servings))
        #expect(FoodMeasure(servingGrams: 30).grams(1.5, in: .servings) == 45)
    }

    @Test func unitsSurviveStorage() {
        let text = FoodMeasure(unitGrams: [.cups: 118, .tablespoons: 7.375]).unitsText
        #expect(text == "cup=118.0;tbsp=7.375")
        #expect(FoodMeasure.unitGrams(from: text) == [.cups: 118, .tablespoons: 7.375])
        #expect(FoodMeasure().unitsText == nil)
        #expect(FoodMeasure.unitGrams(from: "nonsense;cup=x").isEmpty)
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
        let cup = EnteredAmount(quantity: 1.5, unitRaw: "cup", servingGrams: nil)
        #expect(AmountText.describe(grams: 177, entered: cup) == "1½ cups · 177 g")
        #expect(AmountText.describe(grams: 250, entered: cup, liquid: true) == "1½ cups · 250 mL")
        let millilitres = EnteredAmount(quantity: 250, unitRaw: "mL", servingGrams: nil)
        #expect(AmountText.describe(grams: 250, entered: millilitres, liquid: true) == "250 mL")
    }
}

struct AmountInputTests {
    private let granola = FoodMeasure(servingGrams: 118, unitGrams: [.cups: 118])

    @Test func changingUnitKeepsTheAmount() {
        var amount = AmountInput(grams: 236, measure: granola)
        amount.convert(to: .cups)
        #expect(amount.text == "2")
        #expect(amount.grams == 236)
        amount.convert(to: .servings)
        #expect(amount.text == "2")
    }

    @Test func unitsTheFoodDoesntOfferAreRefused() {
        var amount = AmountInput(grams: 118, measure: FoodMeasure(servingGrams: 118))
        amount.convert(to: .cups)
        #expect(amount.unit == .grams)
        #expect(amount.text == "118")
        #expect(AmountInput(grams: 118, measure: FoodMeasure(), unit: .cups).unit == .grams)
    }

    @Test func reopensInTheUnitItWasEnteredIn() {
        let entered = EnteredAmount(quantity: 0.75, unitRaw: "cup", servingGrams: 118)
        let amount = AmountInput(grams: 88.5, entered: entered, measure: granola)
        #expect(amount.unit == .cups)
        #expect(amount.text == "0.75")
    }

    /// An entry from before the label's units were read still opens in its unit, at what it weighed then.
    @Test func reopensAUnitTheFoodNoLongerLists() {
        let entered = EnteredAmount(quantity: 2, unitRaw: "tbsp", servingGrams: nil)
        var amount = AmountInput(grams: 32, entered: entered, measure: FoodMeasure(servingGrams: 30))
        #expect(amount.unit == .tablespoons)
        #expect(amount.text == "2")
        amount.set(1)
        #expect(amount.grams == 16)
    }

    @Test func missingServingFallsBackToTheBaseUnit() {
        let amount = AmountInput(grams: 80, measure: FoodMeasure(), unit: .servings, quantity: 1)
        #expect(amount.unit == .grams)
        #expect(amount.text == "80")
        let juice = AmountInput(grams: 330, measure: FoodMeasure(isLiquid: true))
        #expect(juice.unit == .milliliters)
        #expect(juice.text == "330")
    }

    @Test func stepsSnapToTheGrid() {
        var amount = AmountInput(grams: 137, measure: FoodMeasure())
        amount.step(1)
        #expect(amount.text == "140")
        amount.step(-1)
        #expect(amount.text == "130")

        var cups = AmountInput(grams: 88.5, measure: granola, unit: .cups)
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

    @Test func hintGivesTheBaseAmount() {
        #expect(AmountInput(grams: 100, measure: FoodMeasure()).hint == nil)
        #expect(AmountInput(grams: 118, measure: granola, unit: .cups).hint == "= 118 g")
        let milk = FoodMeasure(servingGrams: 250, isLiquid: true, unitGrams: [.cups: 250])
        #expect(AmountInput(grams: 500, measure: milk, unit: .cups).hint == "= 500 mL")
        #expect(AmountInput(grams: 500, measure: milk).hint == nil)
    }

    /// The bugs that started this: 250 mL of milk read as 2.5 servings, a cup of cereal as 11 servings.
    @Test func labelServingsLineUp() {
        let milk = FoodMeasure(servingGrams: 250, isLiquid: true, unitGrams: [.cups: 250])
        var amount = AmountInput(grams: 250, measure: milk)
        amount.convert(to: .servings)
        #expect(amount.text == "1")
        amount.convert(to: .cups)
        #expect(amount.text == "1")

        let cereal = FoodMeasure(servingGrams: 29, unitGrams: [.cups: 29])
        var bowl = NutritionInput(amount: AmountInput(grams: 29, measure: cereal, unit: .servings, quantity: 1),
                                  macros: Macros(kcal: 110, protein: 2, carbs: 24, fat: 1))
        bowl.amount.convert(to: .cups)
        #expect(bowl.amount.text == "1")
        bowl.amount.set(2)
        #expect(bowl.kcal == "220")
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

    @Test func labelUnitsScaleNutrition() {
        let oil = FoodMeasure(servingGrams: 14, unitGrams: [.tablespoons: 14])
        var nutrition = NutritionInput(amount: AmountInput(grams: 14, measure: oil, unit: .tablespoons),
                                       macros: Macros(kcal: 124, protein: 0, carbs: 0, fat: 14))
        #expect(nutrition.amount.text == "1")
        nutrition.amount.set(2)
        #expect(nutrition.kcal == "248")
        #expect(nutrition.fat == "28")
    }
}

struct ServingSizeTests {
    @Test func readsHouseholdMeasureAndWeight() {
        #expect(ServingSize.parse("1 cup (29 g)") == .init(grams: 29, milliliters: 250, household: true, volumes: [.cups: 1]))
        #expect(ServingSize.parse("3/4 cup (30g)") == .init(grams: 30, milliliters: 187.5, household: true, volumes: [.cups: 0.75]))
        #expect(ServingSize.parse("1 1/2 cups (45 g)") == .init(grams: 45, milliliters: 375, household: true, volumes: [.cups: 1.5]))
        #expect(ServingSize.parse("¾ tasse (28 g)") == .init(grams: 28, milliliters: 187.5, household: true, volumes: [.cups: 0.75]))
        #expect(ServingSize.parse("2 c. à soupe (30 g)") == .init(grams: 30, milliliters: 30, household: true, volumes: [.tablespoons: 2]))
    }

    @Test func metricVolumeWinsOverHouseholdMeasure() {
        #expect(ServingSize.parse("1 tasse (250 mL)").milliliters == 250)
        #expect(ServingSize.parse("8 fl oz (240 mL)").milliliters == 240)
        #expect(ServingSize.parse("250,5 ml").milliliters == 250.5)
        #expect(ServingSize.parse("8 fl oz (240 mL)").volumes == [.fluidOunces: 8, .milliliters: 240])
        #expect(ServingSize.parse("33 cl").volumes == [.milliliters: 330])
    }

    @Test func ignoresWordsThatStartLikeUnits() {
        #expect(ServingSize.parse("1 large egg (50 g)") == .init(grams: 50, milliliters: nil))
        #expect(ServingSize.parse("1 portion") == .init())
        #expect(ServingSize.parse("") == .init())
    }
}
