import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyGoal.effectiveFrom, order: .reverse) private var goals: [DailyGoal]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \LogEntry.date) private var entries: [LogEntry]

    @State private var range = 7
    @State private var showingWeight = false

    var body: some View {
        let days = DayMath.dailyTotals(entries.map { ($0.date, $0.kcal) }, endingOn: .now, count: range)
        let logged = days.filter { $0.kcal > 0 }
        let average = logged.isEmpty ? 0 : logged.map(\.kcal).reduce(0, +) / Double(logged.count)
        let goal = GoalSelection.active(goals, on: .now, effectiveFrom: \.effectiveFrom)?.kcal
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
                                .foregroundStyle(goal.map { day.kcal > $0 ? Color.red : Color.green } ?? .green)
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
