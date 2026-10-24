import SwiftUI
import WidgetKit

/// Calories left with a ring, plus macro rings on the medium size and Lock Screen versions.
struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.w7rp.calorietracker.calories", provider: TodayProvider()) { entry in
            CaloriesWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
        }
        .configurationDisplayName("Calories Left")
        .description("What's left of today's calories and macros.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        let today = entry.today
        switch family {
        case .accessoryCircular:
            Gauge(value: min(max(today.progress, 0), 1)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(today.headline)
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(today.headline) \(today.headlineCaption)", systemImage: "flame.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(MacroKind.allCases.map { kind in
                    "\(kind.title.prefix(1)) \(Format.kcal(today.gramsLeft(kind) ?? kind.value(today.eaten)))"
                }.joined(separator: " · ") + (today.target == nil ? " g" : " g left"))
                    .font(.caption)
                    .monospacedDigit()
            }
        case .accessoryInline:
            Label("\(today.headline) \(today.headlineCaption)", systemImage: "flame.fill")
        case .systemMedium:
            HStack(spacing: 16) {
                CalorieSummary(today: today)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    ForEach(MacroKind.allCases) { kind in
                        MacroRing(kind: kind, today: today)
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                ProgressRing(progress: today.progress, lineWidth: 8) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                }
                .frame(width: 64, height: 64)
                Spacer(minLength: 0)
                CalorieSummary(today: today)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CalorieSummary: View {
    let today: WidgetSnapshot.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(today.headline)
                .font(.system(size: 32, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(today.headlineCaption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacroRing: View {
    let kind: MacroKind
    let today: WidgetSnapshot.Day

    var body: some View {
        let left = today.gramsLeft(kind)
        let goal = today.target.map(kind.value) ?? 0
        VStack(spacing: 4) {
            ProgressRing(progress: goal > 0 ? kind.value(today.eaten) / goal : 0, lineWidth: 5) {
                Image(systemName: kind.symbol)
                    .font(.caption)
            }
            .frame(width: 44, height: 44)
            Text(Format.grams(abs(left ?? kind.value(today.eaten))))
                .font(.caption.bold())
                .monospacedDigit()
            Text(left.map { $0 >= 0 ? "\(kind.title) left" : "\(kind.title) over" } ?? kind.title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview(as: .systemMedium) {
    CaloriesWidget()
} timeline: {
    TodayEntry.preview
}
