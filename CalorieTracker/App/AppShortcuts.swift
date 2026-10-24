import AppIntents

/// Phrases for Siri and the Shortcuts app. Any of these can also go on the Action Button.
struct EasyCalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogSavedMealIntent(),
                    phrases: ["Log \(\.$meal) in \(.applicationName)",
                              "Log a saved meal in \(.applicationName)"],
                    shortTitle: "Log Saved Meal",
                    systemImageName: "bookmark")
        AppShortcut(intent: CaloriesLeftIntent(),
                    phrases: ["How many calories do I have left in \(.applicationName)",
                              "Calories left in \(.applicationName)"],
                    shortTitle: "Calories Left",
                    systemImageName: "flame")
        AppShortcut(intent: QuickAddCaloriesIntent(),
                    phrases: ["Quick add calories in \(.applicationName)",
                              "Add calories in \(.applicationName)"],
                    shortTitle: "Quick Add",
                    systemImageName: "plus.circle")
        AppShortcut(intent: OpenScannerIntent(),
                    phrases: ["Scan food with \(.applicationName)",
                              "Scan my meal with \(.applicationName)"],
                    shortTitle: "Scan Food",
                    systemImageName: "camera.viewfinder")
    }
}
