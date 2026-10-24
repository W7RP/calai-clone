import SwiftData
import SwiftUI

@main
struct CalorieTrackerApp: App {
    @State private var analysis = AnalysisCenter()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(analysis)
                .environment(router)
                .tint(.primary)
        }
        .modelContainer(for: AppModels.all)
    }
}
