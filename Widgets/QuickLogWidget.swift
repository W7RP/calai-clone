import AppIntents
import SwiftUI
import WidgetKit

/// Saved meals with a + button each. Tapping one logs it without opening the app.
struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.w7rp.calorietracker.quicklog", provider: TodayProvider()) { entry in
            QuickLogWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Log a saved meal with one tap, without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        let count = switch family {
        case .systemSmall: 2
        case .systemLarge: 6
        default: 3
        }
        let meals = Array(entry.meals.prefix(count))

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if family == .systemSmall {
                    Text("Quick log")
                        .font(.subheadline.bold())
                } else {
                    Text(entry.today.headline)
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text(entry.today.headlineCaption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Link(destination: AppRoute.scan.url) {
                    Image(systemName: "camera.viewfinder")
                        .font(.subheadline.bold())
                }
                .accessibilityLabel("Scan food")
            }

            if meals.isEmpty {
                Spacer(minLength: 0)
                Text("Save a meal in EasyCal (long-press a food on Home) to log it from here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(meals) { meal in
                    Button(intent: LogSavedMealIntent(meal: SavedMealEntity(meal))) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(meal.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(Format.kcal(meal.totals.kcal)) kcal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus")
                                .font(.caption.bold())
                                .foregroundStyle(Color(UIColor.systemBackground))
                                .frame(width: 22, height: 22)
                                .background(Color.primary, in: .circle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.quiet, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(AppRoute.saved.url)
    }
}

#Preview(as: .systemMedium) {
    QuickLogWidget()
} timeline: {
    TodayEntry.preview
}
