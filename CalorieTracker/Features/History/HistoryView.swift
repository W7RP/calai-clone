import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
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
        let streak = DayMath.streak(loggedDays: Set(kcalByDay.filter { $0.value > 0 }.keys))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weight").font(.subheadline).foregroundStyle(.secondary)
                            Text(weights.last.map { "\(NumberInput.format($0.kilograms)) kg" } ?? "–")
                                .font(.title.bold())
                                .monospacedDigit()
                            Text(plans.first.map { "Goal \(NumberInput.format($0.targetKg)) kg" } ?? "No goal set")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Log weight") { showingWeight = true }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(UIColor.systemBackground))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.primary, in: .capsule)
                                .padding(.top, 6)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .card()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Day streak").font(.subheadline).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "flame.fill")
                                Text("\(streak)").monospacedDigit()
                            }
                            .font(.title.bold())
                            Text(streak == 1 ? "day in a row" : "days in a row")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .card()
                        .accessibilityElement(children: .combine)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if weightPoints.count >= 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weight trend").font(.headline)
                            Chart(weightPoints) { point in
                                LineMark(x: .value("Day", point.date, unit: .day), y: .value("kg", point.kilograms))
                                    .foregroundStyle(Color.primary)
                                PointMark(x: .value("Day", point.date, unit: .day), y: .value("kg", point.kilograms))
                                    .foregroundStyle(Color.primary)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 160)
                            .accessibilityLabel("Weight trend")
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Goal pace").font(.headline)
                        if let plan {
                            GoalPace(plan: plan, recent: lastWeekAverage)
                            Text("Based on the last 7 full days you logged and your estimated maintenance. Day-to-day weight swings 1-2 kg with water; the trend over weeks is what counts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Set a weight goal in Settings to see where your eating is heading.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Calories").font(.headline)
                            Spacer()
                            Picker("Range", selection: $range) {
                                Text("7 days").tag(7)
                                Text("30 days").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        Chart {
                            ForEach(days, id: \.day) { day in
                                let over = targets.target(on: day.day).map { day.kcal > $0.kcal * (1 + AdherenceMath.tolerance) } ?? false
                                BarMark(x: .value("Day", day.day, unit: .day), y: .value("kcal", day.kcal))
                                    .foregroundStyle(over ? Color.primary.opacity(0.3) : Color.primary)
                                    .cornerRadius(4)
                            }
                            if let goal {
                                RuleMark(y: .value("Goal", goal))
                                    .foregroundStyle(Color.secondary)
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .annotation(position: .top, alignment: .leading) {
                                        Text("Goal").font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(height: 200)
                        .accessibilityLabel("Calories per day")
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(Format.kcal(average)) kcal").font(.headline).monospacedDigit()
                                Text("Average on logged days").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(logged.count) of \(range)").font(.headline).monospacedDigit()
                                Text("Days logged").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Faded bars are more than 10% over that day's goal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Adherence").font(.headline)
                        AdherenceCalendarView(kcalByDay: kcalByDay, targets: targets, maintenance: maintenance)
                        Text("Green: within 10% of that day's calorie goal. Red: further off. Days with nothing logged stay blank.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .card()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .pageBackground()
            .navigationTitle("Progress")
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
