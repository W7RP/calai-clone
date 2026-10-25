import SwiftData
import SwiftUI

/// Manual add and edit. Numbers are typed for the amount eaten, not per 100 g, and follow the amount when it changes.
struct EntryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let editor: EntryEditor

    @State private var name = ""
    @State private var nutrition = NutritionInput(amount: AmountInput(grams: 100, measure: FoodMeasure()))
    @State private var meal = Meal.snack
    @State private var date = Date.now
    @State private var loaded = false
    @State private var barcode: String?

    var body: some View {
        NavigationStack {
            Form {
                if let barcode {
                    Section {
                        Label("Barcode \(barcode) isn't in Open Food Facts. Enter it from the label and it'll be remembered for next time.",
                              systemImage: "barcode")
                            .font(.footnote)
                    }
                }

                Section {
                    TextField("Food", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Amount") {
                    AmountControl(amount: $nutrition.amount)
                }

                Section {
                    NumberField(label: "Energy", unit: "kcal", text: $nutrition.kcal)
                    NumberField(label: "Protein", unit: "g", text: $nutrition.protein, optional: true)
                    NumberField(label: "Carbs", unit: "g", text: $nutrition.carbs, optional: true)
                    NumberField(label: "Fat", unit: "g", text: $nutrition.fat, optional: true)
                } header: {
                    Text("Nutrition for this amount")
                } footer: {
                    Text("Change the amount and these scale with it.")
                }

                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Time", selection: $date)
                }

                if case .edit(let entry) = editor {
                    Section {
                        Button("Delete entry", role: .destructive) {
                            context.delete(entry)
                            dismiss()
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle(isEditing ? "Edit entry" : "Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var isEditing: Bool {
        if case .edit = editor { true } else { false }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && nutrition.isValid
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch editor {
        case .new(let day, let barcode):
            date = Self.combine(day: day, timeFrom: .now)
            meal = Meal.suggested(for: date)
            self.barcode = barcode
            nutrition = NutritionInput(amount: AmountInput(grams: 0, measure: FoodMeasure()))
            nutrition.amount.text = ""
        case .edit(let entry):
            name = entry.foodName
            nutrition = NutritionInput(amount: entry.amountInput, macros: entry.macros)
            meal = entry.meal
            date = entry.date
        }
    }

    private func save() {
        guard let amount = nutrition.amount.grams, let macros = nutrition.macros else { return }
        let foodName = name.trimmingCharacters(in: .whitespaces)
        let entered = nutrition.amount.entered

        switch editor {
        case .new:
            var food: FoodItem?
            if let per100g = macros.per100g(fromGrams: amount) {
                food = FoodCache.upsert(in: context, name: foodName, barcode: barcode, per100g: per100g,
                                        servingGrams: amount, density: nutrition.amount.measure.density, source: .manual)
            }
            context.insert(LogEntry(date: date, meal: meal, foodName: foodName, grams: amount,
                                    macros: macros, source: .manual, foodItem: food, entered: entered))
        case .edit(let entry):
            entry.foodName = foodName
            entry.grams = amount
            entry.macros = macros
            entry.entered = entered
            entry.meal = meal
            entry.date = date
        }
        dismiss()
    }

    /// The day's date with the current clock time, so back-filling yesterday still lands on yesterday.
    static func combine(day: Date, timeFrom time: Date, calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }
}

struct NumberField: View {
    let label: String
    let unit: String
    @Binding var text: String
    var optional = false

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(optional ? "optional" : "0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
