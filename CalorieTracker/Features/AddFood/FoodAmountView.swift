import SwiftData
import SwiftUI

/// Pick how much of a known food was eaten. Used for scanned products and recent foods.
struct FoodAmountView: View {
    enum Choice {
        case cached(FoodItem)
        case draft(FoodDraft)
    }

    @Environment(\.modelContext) private var context

    let choice: Choice
    let day: Date
    let onSaved: () -> Void

    @State private var amount = AmountInput(grams: 100, measure: FoodMeasure())
    @State private var meal = Meal.snack
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    if let brand { Text(brand).foregroundStyle(.secondary) }
                }
                LabeledContent("Per 100 \(measure.baseUnit.rawValue)", value: summary(per100g))
                if let serving = servingGrams {
                    LabeledContent("Per serving (\(servingText ?? "\(NumberInput.format(serving)) \(measure.baseUnit.rawValue)"))",
                                   value: summary(per100g.forGrams(serving)))
                }
            }

            Section("Amount") {
                AmountControl(amount: $amount)
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
            }

            if let grams = amount.grams {
                Section("You'll log") {
                    Text(summary(per100g.forGrams(grams)))
                        .monospacedDigit()
                }
            }
        }
        .themedList()
        .navigationTitle("How much?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled((amount.grams ?? 0) <= 0)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let measure = self.measure
            amount = measure.servingGrams.map { AmountInput(grams: $0, measure: measure, unit: .servings, quantity: 1) }
                ?? AmountInput(grams: 100, measure: measure)
            meal = Meal.suggested(for: .now)
        }
    }

    private var name: String {
        switch choice {
        case .cached(let food): food.name
        case .draft(let draft): draft.name
        }
    }

    private var brand: String? {
        switch choice {
        case .cached(let food): food.brand
        case .draft(let draft): draft.brand
        }
    }

    private var per100g: Macros {
        switch choice {
        case .cached(let food): food.per100g
        case .draft(let draft): draft.per100g
        }
    }

    private var servingGrams: Double? {
        switch choice {
        case .cached(let food): food.servingGrams
        case .draft(let draft): draft.servingGrams
        }
    }

    private var servingText: String? {
        switch choice {
        case .cached(let food): food.servingText?.isEmpty == false ? food.servingText : nil
        case .draft(let draft): draft.servingText
        }
    }

    /// Only the units this product's own data gives.
    private var measure: FoodMeasure {
        switch choice {
        case .cached(let food): food.measure
        case .draft(let draft): draft.measure
        }
    }

    private func summary(_ m: Macros) -> String {
        "\(NumberInput.format(m.kcal, maxFractionDigits: 0)) kcal · P \(NumberInput.format(m.protein)) · C \(NumberInput.format(m.carbs)) · F \(NumberInput.format(m.fat))"
    }

    private func save() {
        guard let grams = amount.grams, grams > 0 else { return }
        let food: FoodItem
        switch choice {
        case .cached(let cached):
            food = cached
        case .draft(let draft):
            food = FoodItem(name: draft.name, brand: draft.brand, barcode: draft.barcode, per100g: draft.per100g,
                            measure: draft.measure, servingText: draft.servingText, source: draft.source)
            context.insert(food)
        }
        food.lastUsed = .now
        let date = EntryFormView.combine(day: day, timeFrom: .now)
        context.insert(LogEntry(date: date, meal: meal, foodName: food.name, grams: grams,
                                macros: food.per100g.forGrams(grams), source: food.source, foodItem: food,
                                entered: amount.entered))
        onSaved()
    }
}
