import SwiftData
import SwiftUI

/// Onboarding on first run, then three tabs.
struct RootView: View {
    enum Page: Hashable { case home, progress, settings }

    @AppStorage(Onboarding.doneKey) private var onboarded = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Query private var goals: [DailyGoal]
    @State private var tab = Page.home
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        Group {
            if onboarded || isExistingUser {
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "house.fill", value: Page.home) {
                        TodayView()
                    }
                    Tab("Progress", systemImage: "chart.bar.fill", value: Page.progress) {
                        HistoryView()
                    }
                    Tab("Settings", systemImage: "gearshape.fill", value: Page.settings) {
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
        .background {
            WidgetSync(day: today)
                .id(today)
        }
        .onOpenURL { url in
            if let route = AppRoute(url: url) { open(route) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            today = Calendar.current.startOfDay(for: .now)
            catchUp()
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickLog.changed)) { _ in
            catchUp()
        }
    }

    /// Someone who set goals before onboarding existed shouldn't be asked the questions again.
    private var isExistingUser: Bool {
        UserDefaults.standard.object(forKey: Onboarding.doneKey) == nil && !goals.isEmpty
    }

    /// Stores food logged from widgets and Shortcuts, and opens any screen a control asked for.
    private func catchUp() {
        PendingLogImporter.importPending(into: context)
        if let route = QuickLog.takeRoute() { open(route) }
    }

    private func open(_ route: AppRoute) {
        guard onboarded || isExistingUser else { return }
        tab = .home
        router.route = route
    }
}

/// A screen the app was asked to open from outside, picked up by Home.
@MainActor
@Observable
final class AppRouter {
    var route: AppRoute?
}
