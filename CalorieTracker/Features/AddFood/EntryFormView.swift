import SwiftData
import SwiftUI

/// Manual add and edit. Numbers are typed for the amount eaten, not per 100 g.
struct EntryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let editor: EntryEditor

    @State private var name = ""
    @State private var grams = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
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
                    NumberField(label: "Amount", unit: "g", text: $grams)
                }

                Section("Nutrition for this amount") {
                    NumberField(label: "Energy", unit: "kcal", text: $kcal)
                    NumberField(label: "Protein", unit: "g", text: $protein, optional: true)
                    NumberField(label: "Carbs", unit: "g", text: $carbs, optional: true)
                    NumberField(label: "Fat", unit: "g", text: $fat, optional: true)
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
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && NumberInput.parse(grams) != nil
            && NumberInput.parse(kcal) != nil
            && [protein, carbs, fat].allSatisfy { $0.isEmpty || NumberInput.parse($0) != nil }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch editor {
        case .new(let day, let barcode):
            date = Self.combine(day: day, timeFrom: .now)
            meal = Meal.suggested(for: date)
            self.barcode = barcode
        case .edit(let entry):
            name = entry.foodName
            grams = NumberInput.format(entry.grams)
            kcal = NumberInput.format(entry.kcal)
            protein = NumberInput.format(entry.protein)
            carbs = NumberInput.format(entry.carbs)
            fat = NumberInput.format(entry.fat)
            meal = entry.meal
            date = entry.date
        }
    }

    private func save() {
        guard let amount = NumberInput.parse(grams), let energy = NumberInput.parse(kcal) else { return }
        let macros = Macros(kcal: energy,
                            protein: NumberInput.parse(protein) ?? 0,
                            carbs: NumberInput.parse(carbs) ?? 0,
                            fat: NumberInput.parse(fat) ?? 0)
        let foodName = name.trimmingCharacters(in: .whitespaces)

        switch editor {
        case .new:
            var food: FoodItem?
            if let per100g = macros.per100g(fromGrams: amount) {
                food = FoodCache.upsert(in: context, name: foodName, barcode: barcode, per100g: per100g,
                                        servingGrams: amount, source: .manual)
            }
            context.insert(LogEntry(date: date, meal: meal, foodName: foodName, grams: amount,
                                    macros: macros, source: .manual, foodItem: food))
        case .edit(let entry):
            entry.foodName = foodName
            entry.grams = amount
            entry.macros = macros
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
