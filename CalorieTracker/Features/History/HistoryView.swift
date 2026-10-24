import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyGoal.effectiveFrom, order: .reverse) private var goals: [DailyGoal]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \LogEntry.date) private var entries: [LogEntry]
    @Query private var marks: [TrainingDayMark]
    @Query private var plans: [GoalPlan]

    @State private var range = 7
    @State private var showingWeight = false

    var body: some View {
        let days = DayMath.dailyTotals(entries.map { ($0.date, $0.kcal) }, endingOn: .now, count: range)
        let logged = days.filter { $0.kcal > 0 }
        let average = logged.isEmpty ? 0 : logged.map(\.kcal).reduce(0, +) / Double(logged.count)
        let targets = DayTargets(goals: goals, marks: marks)
        let goal = targets.goal(on: .now)?.kcal
        let plan = plans.first.flatMap { plan in weights.last.map { plan.inputs(weightKg: $0.kilograms) } }
        let maintenance = plan.map(EnergyMath.maintenance)
        let start = days.first?.day ?? .now
        let weightPoints = weights.filter { $0.date >= start }

        NavigationStack {
            List {
                Picker("Range", selection: $range) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    Chart {
                        ForEach(days, id: \.day) { day in
                            BarMark(x: .value("Day", day.day, unit: .day), y: .value("kcal", day.kcal))
                                .foregroundStyle(targets.target(on: day.day).map { day.kcal > $0.kcal ? Color.red : Color.green } ?? .green)
                        }
                        if let goal {
                            RuleMark(y: .value("Goal", goal))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Goal").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel("Calories per day")
                    LabeledContent("Average on logged days", value: "\(NumberInput.format(average, maxFractionDigits: 0)) kcal")
                    LabeledContent("Days logged", value: "\(logged.count) of \(range)")
                } header: {
                    Text("Calories")
                }

                Section {
                    AdherenceCalendarView(kcalByDay: kcalByDay, targets: targets, maintenance: maintenance)
                } header: {
                    Text("Adherence")
                } footer: {
                    Text("Green: within 10% of that day's calorie goal. Red: further off. Days with nothing logged stay blank.")
                }

                Section {
                    if let plan {
                        GoalPace(plan: plan, recent: lastWeekAverage)
                    } else {
                        Text("Set a weight goal in Settings to see where your eating is heading.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Goal pace")
                } footer: {
                    if plan != nil {
                        Text("Based on the last 7 full days you logged and your estimated maintenance. Expect day-to-day weight to swing 1-2 kg with water; the trend over weeks is what counts.")
                    }
                }

                Section {
                    if weightPoints.count >= 2 {
                        Chart(weightPoints) { point in
                            LineMark(x: .value("Day", point.date, unit: .day), y: .value("kg", point.kilograms))
                            PointMark(x: .value("Day", point.date, unit: .day), y: .value("kg", point.kilograms))
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                        .accessibilityLabel("Weight trend")
                    }
                    if let last = weights.last {
                        LabeledContent("Latest", value: "\(NumberInput.format(last.kilograms)) kg · \(last.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                    Button("Log weight", systemImage: "scalemass") { showingWeight = true }
                } header: {
                    Text("Weight (optional)")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingWeight) {
                WeightFormView()
                    .presentationDetents([.medium])
            }
        }
    }
}

extension HistoryView {
    private var kcalByDay: [Date: Double] {
        var sums: [Date: Double] = [:]
        for entry in entries { sums[Calendar.current.startOfDay(for: entry.date), default: 0] += entry.kcal }
        return sums
    }

    /// Average kcal over logged days among the 7 days before today. Today is left out because it isn't finished.
    private var lastWeekAverage: Double? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) else { return nil }
        let logged = DayMath.dailyTotals(entries.map { ($0.date, $0.kcal) }, endingOn: yesterday, count: 7)
            .filter { $0.kcal > 0 }
        return logged.isEmpty ? nil : logged.map(\.kcal).reduce(0, +) / Double(logged.count)
    }
}

/// Where the last week's eating leads, next to what the plan aims for.
private struct GoalPace: View {
    let plan: PlanInputs
    let recent: Double?

    var body: some View {
        let targets = PlanCalculator.targets(plan)
        LabeledContent("Maintenance (est.)", value: "\(NumberInput.format(targets.maintenance, maxFractionDigits: 0)) kcal")
        LabeledContent("Planned", value: "\(NumberInput.signed(targets.plannedWeeklyChangeKg)) kg/week")
        if let recent {
            let change = EnergyMath.weeklyChangeKg(dailyIntake: recent, maintenance: targets.maintenance)
            LabeledContent("Last 7 days", value: "\(NumberInput.format(recent, maxFractionDigits: 0)) kcal/day")
            LabeledContent("At that pace", value: "\(NumberInput.signed(change)) kg/week")
            LabeledContent("In 4 weeks", value: "about \(NumberInput.format(plan.weightKg + change * 4)) kg")
            if let eta = arrival(change: change) {
                LabeledContent("Goal \(NumberInput.format(plan.targetKg)) kg", value: eta.formatted(.dateTime.month().day().year()))
            }
        } else {
            Text("Log a few days to see your pace.")
                .foregroundStyle(.secondary)
        }
    }

    /// When the goal weight is reached at `change` kg/week, if that's the right direction and under two years away.
    private func arrival(change: Double) -> Date? {
        let gap = plan.targetKg - plan.weightKg
        guard abs(gap) > 0.5, abs(change) > 0.01, gap.sign == change.sign else { return nil }
        let days = gap / change * 7
        guard days < 730 else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(days.rounded()), to: .now)
    }
}

private struct WeightFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kilograms = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                NumberField(label: "Weight", unit: "kg", text: $kilograms)
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg = NumberInput.parse(kilograms), kg > 0 {
                            context.insert(WeightEntry(date: date, kilograms: kg))
                        }
                        dismiss()
                    }
                    .disabled((NumberInput.parse(kilograms) ?? 0) <= 0)
                }
            }
        }
    }
}
