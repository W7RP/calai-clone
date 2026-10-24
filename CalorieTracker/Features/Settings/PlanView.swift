import SwiftData
import SwiftUI

/// Weight goal, activity and carb cycling. Works out a daily goal from them and saves it as the current DailyGoal.
struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [GoalPlan]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var loaded = false
    @State private var sex = Sex.male
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var lifestyle = Lifestyle.desk
    @State private var trainingDays = WeekdaySet.empty
    @State private var sessionMinutes = "60"
    @State private var cardioMinutes = "0"
    @State private var cardioIntensity = CardioIntensity.moderate
    @State private var target = ""
    @State private var rate = 0.5
    @State private var cycling = false
    @State private var cyclingShift = 0.15

    static let rates = [0.25, 0.5, 0.75, 1.0]
    static let shifts = [0.10, 0.15, 0.20, 0.25]

    var body: some View {
        let results = inputs.map(PlanCalculator.targets)

        Form {
            Section("You") {
                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                NumberField(label: "Age", unit: "years", text: $age)
                NumberField(label: "Height", unit: "cm", text: $height)
                NumberField(label: "Current weight", unit: "kg", text: $weight)
            }

            Section {
                Picker("Daily movement", selection: $lifestyle) {
                    ForEach(Lifestyle.allCases) { option in
                        VStack(alignment: .leading) {
                            Text(option.title)
                            Text(option.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Activity")
            } footer: {
                Text("Leave workouts out of this; they're counted below.")
            }

            Section {
                WeekdayPicker(selection: $trainingDays)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                NumberField(label: "Session length", unit: "min", text: $sessionMinutes)
                    .disabled(trainingDays.count == 0)
            } header: {
                Text("Gym days")
            } footer: {
                Text("Days you lift or train. You can switch any single day on the Today screen.")
            }

            Section("Cardio") {
                NumberField(label: "Per week", unit: "min", text: $cardioMinutes)
                Picker("Intensity", selection: $cardioIntensity) {
                    ForEach(CardioIntensity.allCases) { option in
                        VStack(alignment: .leading) {
                            Text(option.title)
                            Text(option.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Goal") {
                NumberField(label: "Goal weight", unit: "kg", text: $target)
                if direction != .maintain {
                    Picker(direction == .lose ? "Lose per week" : "Gain per week", selection: $rate) {
                        ForEach(Self.rates, id: \.self) { Text("\(NumberInput.format($0, maxFractionDigits: 2)) kg").tag($0) }
                    }
                }
            }

            Section {
                Toggle("Carb cycling", isOn: $cycling)
                if cycling {
                    Picker("Extra on gym days", selection: $cyclingShift) {
                        ForEach(Self.shifts, id: \.self) { Text("+\(Int(($0 * 100).rounded()))%").tag($0) }
                    }
                }
            } header: {
                Text("Cycling")
            } footer: {
                Text("Moves carbs from rest days to gym days. The weekly total stays the same.")
            }

            if let results {
                PlanResults(targets: results, currentKg: inputs?.weightKg ?? 0, targetKg: inputs?.targetKg ?? 0)
            } else {
                Section {
                    Text("Fill in age, height, current and goal weight to see your targets.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .themedList()
        .navigationTitle("Weight goal")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(results == nil)
            }
        }
        .onAppear(perform: load)
    }

    private var direction: GoalDirection {
        guard let currentKg = NumberInput.parse(weight), let goalKg = NumberInput.parse(target) else { return .maintain }
        return GoalDirection.between(current: currentKg, target: goalKg)
    }

    private var inputs: PlanInputs? {
        guard let years = NumberInput.parse(age), (14...100).contains(years),
              let heightCm = NumberInput.parse(height), heightCm > 100,
              let currentKg = NumberInput.parse(weight), currentKg > 30,
              let goalKg = NumberInput.parse(target), goalKg > 30 else { return nil }
        return PlanInputs(sex: sex, age: Int(years), heightCm: heightCm, weightKg: currentKg, lifestyle: lifestyle,
                          trainingDays: trainingDays, sessionMinutes: NumberInput.parse(sessionMinutes) ?? 0,
                          cardioMinutesPerWeek: NumberInput.parse(cardioMinutes) ?? 0,
                          cardioIntensity: cardioIntensity, targetKg: goalKg, weeklyRateKg: rate,
                          cycling: cycling, cyclingShift: cyclingShift)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let latest = weights.last { weight = NumberInput.format(latest.kilograms) }
        guard let plan = plans.first else { return }
        let year = Calendar.current.component(.year, from: .now)
        sex = plan.sex
        age = String(year - plan.birthYear)
        height = NumberInput.format(plan.heightCm, maxFractionDigits: 0)
        lifestyle = plan.lifestyle
        trainingDays = plan.trainingWeekdays
        sessionMinutes = NumberInput.format(plan.sessionMinutes, maxFractionDigits: 0)
        cardioMinutes = NumberInput.format(plan.cardioMinutesPerWeek, maxFractionDigits: 0)
        cardioIntensity = plan.cardioIntensity
        target = NumberInput.format(plan.targetKg)
        rate = Self.rates.contains(plan.weeklyRateKg) ? plan.weeklyRateKg : 0.5
        cycling = plan.cycling
        cyclingShift = Self.shifts.contains(plan.cyclingShift) ? plan.cyclingShift : 0.15
    }

    private func save() {
        guard let inputs else { return }
        PlanStore.save(inputs, in: context)
        dismiss()
    }
}

/// Saves a plan: updates the one GoalPlan row, logs a changed weight, and writes today's DailyGoal.
enum PlanStore {
    @MainActor
    static func save(_ inputs: PlanInputs, in context: ModelContext) {
        let results = PlanCalculator.targets(inputs)
        let calendar = Calendar.current
        let birthYear = calendar.component(.year, from: .now) - inputs.age
        let plans = (try? context.fetch(FetchDescriptor<GoalPlan>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<DailyGoal>())) ?? []
        var latestWeight = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latestWeight.fetchLimit = 1
        let lastKg = (try? context.fetch(latestWeight))?.first?.kilograms

        if let plan = plans.first {
            plan.update(from: inputs, birthYear: birthYear)
        } else {
            context.insert(GoalPlan(inputs: inputs, birthYear: birthYear))
        }

        // A new current weight is logged too, so the trend and later estimates use it.
        if abs((lastKg ?? 0) - inputs.weightKg) >= 0.05 {
            context.insert(WeightEntry(date: .now, kilograms: inputs.weightKg))
        }

        let today = calendar.startOfDay(for: .now)
        for goal in goals where calendar.isDate(goal.effectiveFrom, inSameDayAs: today) {
            context.delete(goal)
        }
        context.insert(DailyGoal(macros: results.average, effectiveFrom: today, training: results.training,
                                 rest: results.rest, trainingWeekdays: inputs.trainingDays))
    }
}

private struct PlanResults: View {
    let targets: PlanTargets
    let currentKg: Double
    let targetKg: Double

    var body: some View {
        Section {
            LabeledContent("Resting burn", value: kcal(targets.bmr))
            LabeledContent("Maintenance", value: kcal(targets.maintenance))
            LabeledContent(targets.training == nil ? "Daily target" : "Average day", value: kcal(targets.average.kcal))
            LabeledContent("Protein · Carbs · Fat", value: grams(targets.average))
            if let training = targets.training, let rest = targets.rest {
                LabeledContent("Gym days") {
                    VStack(alignment: .trailing) {
                        Text(kcal(training.kcal))
                        Text(grams(training)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Rest days") {
                    VStack(alignment: .trailing) {
                        Text(kcal(rest.kcal))
                        Text(grams(rest)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Expected change",
                           value: "\(NumberInput.signed(targets.plannedWeeklyChangeKg)) kg/week")
            if let weeks = targets.weeksToGoal,
               let date = Calendar.current.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: .now) {
                LabeledContent("Reach \(NumberInput.format(targetKg)) kg", value: date.formatted(.dateTime.month().day().year()))
            }
        } header: {
            Text("Your targets")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(targets.notes, id: \.self) { Text($0).foregroundStyle(.orange) }
                Text("An estimate, usually within about 10%. Weigh in weekly; if your weight isn't moving as expected after 2-3 weeks, come back and adjust.")
            }
        }
    }

    private func kcal(_ value: Double) -> String { "\(NumberInput.format(value, maxFractionDigits: 0)) kcal" }

    private func grams(_ macros: Macros) -> String {
        "\(NumberInput.format(macros.protein, maxFractionDigits: 0)) · \(NumberInput.format(macros.carbs, maxFractionDigits: 0)) · \(NumberInput.format(macros.fat, maxFractionDigits: 0)) g"
    }
}

/// One tappable circle per weekday, in the order of the user's calendar.
struct WeekdayPicker: View {
    @Binding var selection: WeekdaySet

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 6) {
            ForEach(CalendarGrid.orderedWeekdays(calendar: calendar), id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    selection.toggle(weekday)
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isOn ? Color.primary : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(isOn ? Color(UIColor.systemBackground) : Color.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
