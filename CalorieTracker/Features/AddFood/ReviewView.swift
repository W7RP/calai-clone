import SwiftData
import SwiftUI

/// Every AI-proposed item is shown and editable here before anything is saved.
struct ReviewView: View {
    @Environment(\.modelContext) private var context

    let day: Date
    let note: String?
    let analysis: String?
    let warnings: [String]
    let onSaved: () -> Void

    @State private var items: [ReviewItem]
    @State private var meal = Meal.suggested(for: .now)

    init(estimate: FoodEstimate, day: Date, onSaved: @escaping () -> Void) {
        self.day = day
        note = estimate.note
        analysis = estimate.analysis
        warnings = estimate.warnings
        self.onSaved = onSaved
        _items = State(initialValue: estimate.items.map(ReviewItem.init))
    }

    var body: some View {
        Form {
            Section {
                Label("These are estimates. Check the amounts before saving.", systemImage: "info.circle")
                    .font(.footnote)
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let analysis {
                    DisclosureGroup("How this was estimated") {
                        Text(analysis).font(.footnote).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }

            ForEach($items) { $item in
                Section {
                    TextField("Food", text: $item.name)
                    NumberField(label: "Amount", unit: "g", text: $item.grams)
                        .onChange(of: item.grams) { old, new in item.rescale(fromGrams: old, toGrams: new) }
                    NumberField(label: "Energy", unit: "kcal", text: $item.kcal)
                    NumberField(label: "Protein", unit: "g", text: $item.protein)
                    NumberField(label: "Carbs", unit: "g", text: $item.carbs)
                    NumberField(label: "Fat", unit: "g", text: $item.fat)
                    Button("Remove", role: .destructive) {
                        items.removeAll { $0.id == item.id }
                    }
                } header: {
                    HStack {
                        Text(item.fromLabel ? "From label" : "Estimate")
                        Spacer()
                        Text("\(item.confidence.rawValue) confidence")
                            .foregroundStyle(item.confidence == .low ? .orange : .secondary)
                    }
                }
            }

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Total", value: "\(NumberInput.format(total.kcal, maxFractionDigits: 0)) kcal")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(items.isEmpty || !items.allSatisfy(\.isValid))
            }
        }
    }

    private var total: Macros {
        Macros.total(items.compactMap(\.parsed).map(\.macros))
    }

    private func save() {
        let date = EntryFormView.combine(day: day, timeFrom: .now)
        for item in items {
            guard let parsed = item.parsed else { continue }
            var food: FoodItem?
            if let per100g = parsed.macros.per100g(fromGrams: parsed.grams) {
                food = FoodCache.upsert(in: context, name: parsed.name, per100g: per100g,
                                        servingGrams: parsed.grams, source: .ai)
            }
            context.insert(LogEntry(date: date, meal: meal, foodName: parsed.name, grams: parsed.grams,
                                    macros: parsed.macros, source: .ai, foodItem: food,
                                    aiConfidence: parsed.confidenceScore))
        }
        onSaved()
    }
}

/// Editable copy of one estimated item; fields are strings so partially typed numbers survive.
struct ReviewItem: Identifiable {
    let id = UUID()
    var name: String
    var grams: String
    var kcal: String
    var protein: String
    var carbs: String
    var fat: String
    let confidence: EstimatedItem.Confidence
    let fromLabel: Bool

    init(_ item: EstimatedItem) {
        name = item.name
        grams = NumberInput.format(item.grams)
        kcal = NumberInput.format(item.macros.kcal, maxFractionDigits: 0)
        protein = NumberInput.format(item.macros.protein)
        carbs = NumberInput.format(item.macros.carbs)
        fat = NumberInput.format(item.macros.fat)
        confidence = item.confidence
        fromLabel = item.fromLabel
    }

    var parsed: EstimatedItem? {
        guard let g = NumberInput.parse(grams), let k = NumberInput.parse(kcal),
              let p = NumberInput.parse(protein), let c = NumberInput.parse(carbs), let f = NumberInput.parse(fat),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return EstimatedItem(name: name.trimmingCharacters(in: .whitespaces), grams: g,
                             macros: Macros(kcal: k, protein: p, carbs: c, fat: f),
                             confidence: confidence, fromLabel: fromLabel)
    }

    var isValid: Bool { parsed != nil }

    /// Changing the amount scales the nutrition with it, which is almost always what's meant.
    mutating func rescale(fromGrams old: String, toGrams new: String) {
        guard let from = NumberInput.parse(old), let to = NumberInput.parse(new), from > 0, to > 0, from != to,
              let current = parsed else { return }
        let scaled = current.macros.scaled(by: to / from)
        kcal = NumberInput.format(scaled.kcal, maxFractionDigits: 0)
        protein = NumberInput.format(scaled.protein)
        carbs = NumberInput.format(scaled.carbs)
        fat = NumberInput.format(scaled.fat)
    }
}
