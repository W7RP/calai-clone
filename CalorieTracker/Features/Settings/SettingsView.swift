import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Goals") {
                    NavigationLink("Daily goal") { GoalsView() }
                }
                Section("AI logging") {
                    NavigationLink("ChatGPT") { ChatGPTSettingsView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyGoal.effectiveFrom, order: .reverse) private var goals: [DailyGoal]

    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        Form {
            Section {
                NumberField(label: "Energy", unit: "kcal", text: $kcal)
                NumberField(label: "Protein", unit: "g", text: $protein)
                NumberField(label: "Carbs", unit: "g", text: $carbs)
                NumberField(label: "Fat", unit: "g", text: $fat)
            } footer: {
                if let estimate {
                    Text("Your macros add up to about \(NumberInput.format(estimate, maxFractionDigits: 0)) kcal (4 kcal/g protein and carbs, 9 kcal/g fat).")
                }
            }
        }
        .navigationTitle("Daily goal")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(NumberInput.parse(kcal) == nil)
            }
        }
        .onAppear {
            guard let current = GoalSelection.active(goals, on: .now, effectiveFrom: \.effectiveFrom) else { return }
            kcal = NumberInput.format(current.kcal, maxFractionDigits: 0)
            protein = NumberInput.format(current.protein, maxFractionDigits: 0)
            carbs = NumberInput.format(current.carbs, maxFractionDigits: 0)
            fat = NumberInput.format(current.fat, maxFractionDigits: 0)
        }
    }

    private var estimate: Double? {
        guard let p = NumberInput.parse(protein), let c = NumberInput.parse(carbs), let f = NumberInput.parse(fat) else { return nil }
        return Nutrition.kcalFromMacros(protein: p, carbs: c, fat: f)
    }

    private func save() {
        guard let energy = NumberInput.parse(kcal) else { return }
        let macros = Macros(kcal: energy, protein: NumberInput.parse(protein) ?? 0,
                            carbs: NumberInput.parse(carbs) ?? 0, fat: NumberInput.parse(fat) ?? 0)
        let today = Calendar.current.startOfDay(for: .now)
        // Changing the goal twice in one day replaces today's row instead of stacking them.
        for goal in goals where Calendar.current.isDate(goal.effectiveFrom, inSameDayAs: today) {
            context.delete(goal)
        }
        context.insert(DailyGoal(macros: macros, effectiveFrom: today))
        dismiss()
    }
}
