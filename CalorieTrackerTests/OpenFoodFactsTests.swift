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

    @Test func liquidsAreMeasuredLikeWater() throws {
        let juice = try #require(map(#"{"status":1,"product":{"product_name":"Jus","product_quantity_unit":"mL","serving_quantity":"250","serving_quantity_unit":"ml","nutriments":{"energy-kcal_100g":45}}}"#))
        #expect(juice.density == 1)
        let cheese = try #require(map(#"{"status":1,"product":{"product_name":"Fromage","product_quantity_unit":"g","nutriments":{"energy-kcal_100g":350}}}"#))
        #expect(cheese.density == nil)
    }

    @Test func cerealServingGivesTheDensity() throws {
        let cereal = try #require(map(#"{"status":1,"product":{"product_name":"Cereal","serving_size":"1 cup (29 g)","serving_quantity":29,"serving_quantity_unit":"g","quantity":"400 g","nutriments":{"energy-kcal_100g":380}}}"#))
        #expect(cereal.servingGrams == 29)
        #expect(abs((cereal.density ?? 0) - 0.116) < 0.001)
        #expect(cereal.servingText == "1 cup (29 g)")
    }

    @Test func milkServingIsItsVolume() throws {
        let milk = try #require(map(#"{"status":1,"product":{"product_name":"Lait 2%","serving_size":"1 tasse (250 mL)","quantity":"2 L","nutriments":{"energy-kcal_100g":50}}}"#))
        #expect(milk.density == 1)
        #expect(milk.servingGrams == 250)
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
