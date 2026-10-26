import Foundation
import Testing
@testable import CalorieTracker

struct OpenFoodFactsMappingTests {
    private func map(_ json: String, barcode: String = "0055577420034") -> FoodDraft? {
        OpenFoodFactsClient.map(Data(json.utf8), barcode: barcode)
    }

    @Test func mapsTypicalProduct() throws {
        let draft = try #require(map("""
        {"status":1,"product":{"product_name":"Yogourt grec nature","brands":"Liberté, Danone",
         "serving_quantity":"175",
         "nutriments":{"energy-kcal_100g":97,"proteins_100g":"9.5","carbohydrates_100g":4.1,"fat_100g":4.8}}}
        """))
        #expect(draft.name == "Yogourt grec nature")
        #expect(draft.brand == "Liberté")
        #expect(draft.per100g == Macros(kcal: 97, protein: 9.5, carbs: 4.1, fat: 4.8))
        #expect(draft.servingGrams == 175)
        #expect(draft.source == .off)
        #expect(draft.barcode == "0055577420034")
    }

    @Test func liquidsAreMeasuredInMillilitres() throws {
        let juice = try #require(map(#"{"status":1,"product":{"product_name":"Jus","product_quantity_unit":"mL","serving_quantity":"250","serving_quantity_unit":"ml","nutriments":{"energy-kcal_100g":45}}}"#))
        #expect(juice.isLiquid)
        #expect(juice.measure.units == [.milliliters, .servings])
        let cheese = try #require(map(#"{"status":1,"product":{"product_name":"Fromage","product_quantity_unit":"g","nutriments":{"energy-kcal_100g":350}}}"#))
        #expect(!cheese.isLiquid)
        #expect(cheese.measure.units == [.grams])
    }

    @Test func cerealCupComesFromTheLabel() throws {
        let cereal = try #require(map(#"{"status":1,"product":{"product_name":"Cereal","serving_size":"1 cup (29 g)","serving_quantity":29,"serving_quantity_unit":"g","quantity":"400 g","nutriments":{"energy-kcal_100g":380}}}"#))
        #expect(cereal.servingGrams == 29)
        #expect(cereal.measure.units == [.grams, .servings, .cups])
        #expect(cereal.measure.grams(per: .cups) == 29)
        #expect(cereal.servingText == "1 cup (29 g)")
    }

    /// Vector granola: "1 cup (118 g)" gives grams, the serving and a 118 g cup, and nothing else.
    @Test func granolaOffersOnlyItsLabelUnits() throws {
        let label = try #require(map(#"{"status":1,"product":{"product_name":"Vector granola","serving_size":"1 cup (118 g)","serving_quantity":118,"serving_quantity_unit":"g","product_quantity_unit":"g","quantity":"500 g","nutriments":{"energy-kcal_100g":420}}}"#))
        #expect(label.servingGrams == 118)
        #expect(label.measure.units == [.grams, .servings, .cups])
        #expect(label.measure.grams(per: .cups) == 118)

        // A stray volume elsewhere in the entry doesn't turn a serving printed in grams into millilitres.
        let messy = try #require(map(#"{"status":1,"product":{"product_name":"Vector granola","serving_size":"1 cup (118 g)","serving_quantity":118,"product_quantity_unit":"ml","quantity":"1 L","nutriments":{"energy-kcal_100g":420}}}"#))
        #expect(messy.servingGrams == 118)
        #expect(messy.measure.units == [.grams, .servings, .cups])
    }

    /// With only a weight on the label there's no cup to offer, so none is made up.
    @Test func weightOnlyServingOffersNoVolumes() throws {
        let granola = try #require(map(#"{"status":1,"product":{"product_name":"Vector granola","serving_size":"118 g","serving_quantity":"118","nutriments":{"energy-kcal_100g":420}}}"#))
        #expect(granola.servingGrams == 118)
        #expect(granola.measure.units == [.grams, .servings])
    }

    @Test func fractionsOfACupGiveAWholeCup() throws {
        let oats = try #require(map(#"{"status":1,"product":{"product_name":"Oats","serving_size":"1/2 cup (40 g)","nutriments":{"energy-kcal_100g":380}}}"#))
        #expect(oats.servingGrams == 40)
        #expect(oats.measure.grams(per: .cups) == 80)
        let butter = try #require(map(#"{"status":1,"product":{"product_name":"Peanut butter","serving_size":"2 tbsp (32 g)","serving_quantity":32,"nutriments":{"energy-kcal_100g":600}}}"#))
        #expect(butter.measure.units == [.grams, .servings, .tablespoons])
        #expect(butter.measure.grams(per: .tablespoons) == 16)
    }

    @Test func milkServingIsItsVolume() throws {
        let milk = try #require(map(#"{"status":1,"product":{"product_name":"Lait 2%","serving_size":"1 tasse (250 mL)","quantity":"2 L","nutriments":{"energy-kcal_100g":50}}}"#))
        #expect(milk.isLiquid)
        #expect(milk.servingGrams == 250)
        #expect(milk.measure.units == [.milliliters, .servings, .cups])
        #expect(milk.measure.grams(per: .cups) == 250)
        // 250 mL is one serving and one cup.
        #expect(milk.measure.quantity(ofGrams: 250, in: .servings) == 1)
    }

    @Test func fallsBackToKilojoules() throws {
        let draft = try #require(map(#"{"status":1,"product":{"product_name":"X","nutriments":{"energy_100g":418.4}}}"#))
        #expect(abs(draft.per100g.kcal - 100) < 0.001)
        #expect(draft.per100g.protein == 0)
    }

    @Test func usesFrenchNameWhenMainNameMissing() throws {
        let draft = try #require(map(#"{"status":1,"product":{"product_name":"","product_name_fr":"Fromage","nutriments":{"energy-kcal_100g":350}}}"#))
        #expect(draft.name == "Fromage")
    }

    @Test func commaDecimalStrings() throws {
        let draft = try #require(map(#"{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":"52,5"}}}"#))
        #expect(draft.per100g.kcal == 52.5)
    }

    @Test func notFoundOrNoEnergyIsNil() {
        #expect(map(#"{"status":0,"status_verbose":"product not found"}"#) == nil)
        #expect(map(#"{"status":1,"product":{"product_name":"X","nutriments":{}}}"#) == nil)
        #expect(map("not json") == nil)
    }
}

struct BarcodeNormalizerTests {
    @Test func padsUPCAToEAN13() {
        #expect(BarcodeNormalizer.normalize("055577420034") == "0055577420034")
    }

    @Test func keepsEAN13AndEAN8() {
        #expect(BarcodeNormalizer.normalize("3017620422003") == "3017620422003")
        #expect(BarcodeNormalizer.normalize("96385074") == "96385074")
    }

    @Test func rejectsShortOrJunk() {
        #expect(BarcodeNormalizer.normalize("123") == nil)
        #expect(BarcodeNormalizer.normalize("hello") == nil)
    }
}
