import SwiftData
import SwiftUI

@main
struct CalorieTrackerApp: App {
    @State private var analysis = AnalysisCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(analysis)
                .tint(.primary)
        }
        .modelContainer(for: [FoodItem.self, LogEntry.self, DailyGoal.self, WeightEntry.self, GoalPlan.self, TrainingDayMark.self])
    }
}
