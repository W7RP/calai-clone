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
        #expect(AIError.fromCode("subscription_sharing_usage_unavailable") == .temporarilyUnavailable)
        #expect(AIError.fromCode("subscription_sharing_unsupported_capability", param: "text.format")
                == .unsupported(param: "text.format"))
    }

    @Test func httpBodies() {
        let structured = #"{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"cap"}}"#
        #expect(AIError.fromHTTP(status: 429, body: structured) == .usageLimit)
        #expect(AIError.fromHTTP(status: 503, body: #"{"detail":"routing unavailable"}"#) == .temporarilyUnavailable)
        #expect(AIError.fromHTTP(status: 401, body: #"{"detail":"bad identity"}"#) == .rejected(status: 401, detail: "bad identity"))
    }
}

struct ReviewItemTests {
    private var item: ReviewItem {
        ReviewItem(EstimatedItem(name: "Rice", grams: 200, macros: Macros(kcal: 260, protein: 5, carbs: 57, fat: 0.6),
                                 confidence: .medium, fromLabel: false))
    }

    @Test func changingAmountScalesNutrition() throws {
        var edited = item
        edited.grams = "100"
        edited.rescale(fromGrams: "200", toGrams: "100")
        let parsed = try #require(edited.parsed)
        #expect(abs(parsed.macros.kcal - 130) < 0.5)
        #expect(abs(parsed.macros.carbs - 28.5) < 0.05)
    }

    @Test func partialInputIsInvalidAndNotRescaled() {
        var edited = item
        edited.grams = ""
        edited.rescale(fromGrams: "200", toGrams: "")
        #expect(!edited.isValid)
        #expect(edited.kcal == item.kcal)
    }
}
