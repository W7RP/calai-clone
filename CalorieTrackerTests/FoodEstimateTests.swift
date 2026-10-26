import Foundation
import Testing
@testable import CalorieTracker

struct FoodEstimateParserTests {
    @Test func parsesItemsAndNote() throws {
        let estimate = try FoodEstimateParser.parse("""
        {"items":[{"name":"Scrambled eggs","grams":120,"kcal":180,"protein_g":12.5,"carbs_g":1,"fat_g":13,
          "confidence":"medium","source":"estimate"},
         {"name":"Yogourt","grams":175,"kcal":170,"protein_g":16,"carbs_g":7,"fat_g":8.4,"confidence":"high","source":"label"}],
         "note":"Butter amount guessed"}
        """)
        #expect(estimate.items.count == 2)
        #expect(estimate.items[0].macros == Macros(kcal: 180, protein: 12.5, carbs: 1, fat: 13))
        #expect(estimate.items[0].confidence == .medium)
        #expect(!estimate.items[0].fromLabel)
        #expect(estimate.items[1].fromLabel)
        #expect(estimate.note == "Butter amount guessed")
    }

    @Test func toleratesCodeFence() throws {
        let estimate = try FoodEstimateParser.parse("""
        ```json
        {"items":[{"name":"Apple","grams":180,"kcal":95}],"note":null}
        ```
        """)
        #expect(estimate.items.first?.macros == Macros(kcal: 95, protein: 0, carbs: 0, fat: 0))
        #expect(estimate.items.first?.confidence == .low)
        #expect(estimate.note == nil)
    }

    @Test func readsAnalysisAndTreatsEmptyNoteAsNone() throws {
        let estimate = try FoodEstimateParser.parse("""
        {"analysis":"One banana on a counter.","items":[{"name":"Banana","grams":118,"kcal":105,"protein_g":1.3,
          "carbs_g":27,"fat_g":0.4,"confidence":"high","source":"estimate"}],"note":""}
        """)
        #expect(estimate.analysis == "One banana on a counter.")
        #expect(estimate.note == nil)
        #expect(estimate.items.first?.confidence == .high)
    }

    @Test func readsVolumeAndIgnoresZero() throws {
        let estimate = try FoodEstimateParser.parse("""
        {"items":[{"name":"Milk","grams":258,"ml":250,"kcal":130},{"name":"Toast","grams":30,"ml":0,"kcal":80}]}
        """)
        #expect(estimate.items[0].milliliters == 250)
        #expect(abs((estimate.items[0].gramsPerMilliliter ?? 0) - 1.032) < 0.001)
        #expect(estimate.items[1].milliliters == nil)
        #expect(estimate.items[1].gramsPerMilliliter == nil)
    }

    @Test func emptyItemsKeepNote() throws {
        let estimate = try FoodEstimateParser.parse(#"{"items":[],"note":"No food visible"}"#)
        #expect(estimate.items.isEmpty)
        #expect(estimate.note == "No food visible")
    }

    @Test func rejectsTruncatedOrInvalidJSON() {
        #expect(throws: AIError.unreadable) { try FoodEstimateParser.parse(#"{"items":[{"name":"Apple","grams":18"#) }
        #expect(throws: AIError.unreadable) { try FoodEstimateParser.parse("Sorry, I can't help with that.") }
    }

    @Test func rejectsNegativeNumbersAndBlankNames() {
        #expect(throws: AIError.unreadable) {
            try FoodEstimateParser.parse(#"{"items":[{"name":"X","grams":-5,"kcal":10}]}"#)
        }
        #expect(throws: AIError.unreadable) {
            try FoodEstimateParser.parse(#"{"items":[{"name":"  ","grams":5,"kcal":10}]}"#)
        }
    }
}

struct AIErrorMappingTests {
    @Test func structuredCodes() {
        #expect(AIError.fromCode("subscription_sharing_usage_limit_exceeded") == .usageLimit)
        #expect(AIError.fromCode("subscription_sharing_user_not_eligible") == .notEligible)
        #expect(AIError.fromCode("subscription_sharing_usage_unavailable") == .temporarilyUnavailable(.chatGPT))
        #expect(AIError.fromCode("subscription_sharing_unsupported_capability", param: "text.format")
                == .unsupported(param: "text.format"))
    }

    @Test func httpBodies() {
        let structured = #"{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"cap"}}"#
        #expect(AIError.fromHTTP(status: 429, body: structured) == .usageLimit)
        #expect(AIError.fromHTTP(status: 503, body: #"{"detail":"routing unavailable"}"#) == .temporarilyUnavailable(.chatGPT))
        #expect(AIError.fromHTTP(status: 401, body: #"{"detail":"bad identity"}"#) == .rejected(.chatGPT, status: 401, detail: "bad identity"))
    }
}

struct ReviewItemTests {
    private var item: ReviewItem {
        ReviewItem(EstimatedItem(name: "Rice", grams: 200, macros: Macros(kcal: 260, protein: 5, carbs: 57, fat: 0.6),
                                 confidence: .medium, fromLabel: false))
    }

    @Test func changingAmountScalesNutrition() throws {
        var edited = item
        edited.nutrition.amount.text = "100"
        let parsed = try #require(edited.parsed)
        #expect(abs(parsed.macros.kcal - 130) < 0.5)
        #expect(abs(parsed.macros.carbs - 28.5) < 0.05)
    }

    @Test func partialInputIsInvalidAndNotRescaled() {
        var edited = item
        edited.nutrition.amount.text = ""
        #expect(!edited.isValid)
        #expect(edited.nutrition.kcal == item.nutrition.kcal)
    }

    @Test func estimatedPortionIsOneServing() throws {
        var edited = item
        edited.nutrition.amount.convert(to: .servings)
        #expect(edited.nutrition.amount.text == "1")
        edited.nutrition.amount.set(1.5)
        let parsed = try #require(edited.parsed)
        #expect(parsed.grams == 300)
        #expect(abs(parsed.macros.kcal - 390) < 0.5)
    }

    @Test func drinksOpenInMillilitres() throws {
        let cola = ReviewItem(EstimatedItem(name: "Cola", grams: 370, macros: Macros(kcal: 150, protein: 0, carbs: 39, fat: 0),
                                            confidence: .high, fromLabel: false, milliliters: 355))
        #expect(cola.nutrition.amount.unit == .milliliters)
        #expect(cola.nutrition.amount.text == "355")
        #expect(abs(try #require(cola.parsed).grams - 370) < 0.001)
    }

    /// No cups or spoons are made up for an estimate; only what the model gave.
    @Test func offersOnlyTheEstimatesOwnUnits() {
        #expect(item.nutrition.amount.measure.units == [.grams, .servings])
        let cola = ReviewItem(EstimatedItem(name: "Cola", grams: 370, macros: Macros(kcal: 150, protein: 0, carbs: 39, fat: 0),
                                            confidence: .high, fromLabel: false, milliliters: 355))
        #expect(cola.nutrition.amount.measure.units == [.grams, .servings, .milliliters])
    }
}
