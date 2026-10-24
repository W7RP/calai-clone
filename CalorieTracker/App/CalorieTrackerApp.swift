import SwiftData
import SwiftUI

@main
struct CalorieTrackerApp: App {
    @State private var analysis = AnalysisCenter()
    @State private var router = AppRouter()
    @State private var coach = CoachSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(analysis)
                .environment(router)
                .environment(coach)
                .tint(.primary)
        }
        .modelContainer(for: AppModels.all)
    }
}
