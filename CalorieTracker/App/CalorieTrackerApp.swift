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
        .modelContainer(for: AppModels.all)
    }
}
