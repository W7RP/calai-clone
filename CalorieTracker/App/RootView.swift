import SwiftData
import SwiftUI

/// Onboarding on first run, then three tabs.
struct RootView: View {
    @AppStorage(Onboarding.doneKey) private var onboarded = false
    @Query private var goals: [DailyGoal]

    var body: some View {
        if onboarded || isExistingUser {
            TabView {
                Tab("Home", systemImage: "house.fill") {
                    TodayView()
                }
                Tab("Progress", systemImage: "chart.bar.fill") {
                    HistoryView()
                }
                Tab("Settings", systemImage: "gearshape.fill") {
                    SettingsView()
                }
            }
            .task {
                if isExistingUser { onboarded = true }
            }
        } else {
            OnboardingView()
        }
    }

    /// Someone who set goals before onboarding existed shouldn't be asked the questions again.
    private var isExistingUser: Bool {
        UserDefaults.standard.object(forKey: Onboarding.doneKey) == nil && !goals.isEmpty
    }
}
