import Charts
import SwiftData
import SwiftUI

/// Weigh-ins as faint dots with the smoothed trend drawn through them.
struct WeightTrendCard: View {
    enum Span: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, half = 182, all = 0
        var id: Self { self }

        var title: String {
            switch self {
            case .month: "1M"
            case .quarter: "3M"
            case .half: "6M"
            case .all: "All"
            }
        }
    }

    let points: [WeightTrend.Point]
    let goalKg: Double?

    @State private var span = Span.quarter

    var body: some View {
        let shown = visible
        let rate = WeightTrend.weeklyRate(points)
        let change = shown.first.flatMap { first in shown.last.map { $0.trend - first.trend } }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight trend").font(.headline)
                Spacer()
                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            HStack(alignment: .top) {
                Stat(value: points.last.map { "\(NumberInput.format($0.trend)) kg" } ?? "–", caption: "Trend weight")
                Spacer()
                Stat(value: rate.map { "\(NumberInput.signed($0, maxFractionDigits: 1)) kg" } ?? "–", caption: "Per week, last 4 wks")
                Spacer()
                Stat(value: change.map { "\(NumberInput.signed($0, maxFractionDigits: 1)) kg" } ?? "–", caption: "Over this range")
            }

            Chart {
                ForEach(shown, id: \.day) { point in
                    PointMark(x: .value("Day", point.day, unit: .day), y: .value("Weigh-in", point.weight))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .symbolSize(24)
                    LineMark(x: .value("Day", point.day, unit: .day), y: .value("Trend", point.trend),
                             series: .value("Series", "Trend"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let goalKg, showsGoal(goalKg, in: shown) {
                    RuleMark(y: .value("Goal", goalKg))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Goal").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            .accessibilityLabel("Weight trend")
            .accessibilityValue(points.last.map { "Trend \(NumberInput.format($0.trend)) kilograms" } ?? "")

            Text("Dots are weigh-ins; the line smooths out day-to-day water swings. Weigh in most mornings for the best line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var visible: [WeightTrend.Point] {
        guard span != .all, let last = points.last?.day,
              let start = Calendar.current.date(byAdding: .day, value: -span.rawValue, to: last) else { return points }
        return points.filter { $0.day >= start }
    }

    /// The goal line only when it's near the data, so a far-off goal doesn't flatten the chart.
    private func showsGoal(_ goal: Double, in shown: [WeightTrend.Point]) -> Bool {
        let values = shown.flatMap { [$0.weight, $0.trend] }
        guard let low = values.min(), let high = values.max() else { return false }
        let margin = max(high - low, 2)
        return goal >= low - margin && goal <= high + margin
    }
}

private struct Stat: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every weigh-in, newest first, with swipe to delete.
struct WeighInsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    var body: some View {
        List {
            ForEach(weights) { entry in
                LabeledContent(entry.date.formatted(date: .abbreviated, time: .omitted),
                               value: "\(NumberInput.format(entry.kilograms)) kg")
                    .monospacedDigit()
            }
            .onDelete { offsets in
                let doomed = offsets.map { weights[$0] }
                for entry in doomed { context.delete(entry) }
            }
        }
        .overlay {
            if weights.isEmpty {
                ContentUnavailableView("No weigh-ins", systemImage: "scalemass")
            }
        }
        .themedList()
        .navigationTitle("Weigh-ins")
        .navigationBarTitleDisplayMode(.inline)
    }
}
