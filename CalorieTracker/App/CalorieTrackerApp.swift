import SwiftData
import SwiftUI

@main
struct CalorieTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(for: [FoodItem.self, LogEntry.self, DailyGoal.self])
    }
}
