import SwiftUI
import WidgetKit

@main
struct EasyCalWidgets: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        QuickLogWidget()
        ScanFoodControl()
        SavedMealsControl()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let today: WidgetSnapshot.Day
    let meals: [SharedMeal]

    static func current(at date: Date = .now) -> TodayEntry {
        TodayEntry(date: date, today: SharedStore.today(now: date), meals: SharedStore.snapshot()?.meals ?? [])
    }

    static let preview = TodayEntry(
        date: .now,
        today: WidgetSnapshot.Day(eaten: Macros(kcal: 1260, protein: 92, carbs: 130, fat: 41),
                                  target: Macros(kcal: 2200, protein: 160, carbs: 230, fat: 70)),
        meals: [
            SharedMeal(id: UUID(), name: "Oats & berries", mealRaw: "breakfast",
                       items: [SavedMealItem(foodName: "Oats", grams: 80, macros: Macros(kcal: 420, protein: 18, carbs: 60, fat: 9), sourceRaw: "manual")]),
            SharedMeal(id: UUID(), name: "Chicken bowl", mealRaw: "lunch",
                       items: [SavedMealItem(foodName: "Bowl", grams: 400, macros: Macros(kcal: 640, protein: 52, carbs: 70, fat: 14), sourceRaw: "manual")]),
            SharedMeal(id: UUID(), name: "Protein shake", mealRaw: "snack",
                       items: [SavedMealItem(foodName: "Shake", grams: 300, macros: Macros(kcal: 210, protein: 40, carbs: 6, fat: 3), sourceRaw: "manual")]),
        ])
}

/// Re-reads the snapshot now and again at midnight, when the day starts over.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview && SharedStore.snapshot() == nil ? .preview : .current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        completion(Timeline(entries: [.current(at: now), .current(at: midnight)], policy: .after(midnight)))
    }
}

extension WidgetSnapshot.Day {
    var progress: Double {
        guard let target, target.kcal > 0 else { return 0 }
        return eaten.kcal / target.kcal
    }

    /// The big number: kcal left, kcal over, or kcal eaten without a goal.
    var headline: String {
        guard let left = kcalLeft else { return Format.kcal(eaten.kcal) }
        return Format.kcal(abs(left))
    }

    var headlineCaption: String {
        guard let left = kcalLeft else { return "kcal eaten" }
        return left >= 0 ? "kcal left" : "kcal over"
    }

    func gramsLeft(_ kind: MacroKind) -> Double? {
        target.map { kind.value($0) - kind.value(eaten) }
    }
}

/// Scan food from Control Center, the Lock Screen or the Action Button.
struct ScanFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.w7rp.calorietracker.control.scan") {
            ControlWidgetButton(action: OpenScannerIntent()) {
                Label("Scan Food", systemImage: "camera.viewfinder")
            }
        }
        .displayName("Scan Food")
        .description("Opens EasyCal on the camera.")
    }
}

/// Opens saved meals and recent foods.
struct SavedMealsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.w7rp.calorietracker.control.saved") {
            ControlWidgetButton(action: OpenSavedMealsIntent()) {
                Label("Saved Meals", systemImage: "bookmark")
            }
        }
        .displayName("Saved Meals")
        .description("Opens your saved meals to log one.")
    }
}
