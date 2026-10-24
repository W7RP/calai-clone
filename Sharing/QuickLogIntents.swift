import AppIntents
import Foundation
import WidgetKit

/// Screens a widget, control or Shortcut can open the app on.
enum AppRoute: String, Codable, Sendable {
    case scan, barcode, describe, saved

    static let scheme = "easycal"

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let route = AppRoute(rawValue: host) else { return nil }
        self = route
    }
}

enum QuickLog {
    /// Posted in the app's own process when a Shortcut runs there, so the log shows up straight away.
    static let changed = Notification.Name("EasyCalQuickLogChanged")
    private static let routeKey = "pendingRoute"

    static func add(_ log: PendingLog) {
        SharedStore.add(log)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Asks the app to open on a screen next time it's in front.
    static func request(_ route: AppRoute) {
        SharedStore.defaults.set(route.rawValue, forKey: routeKey)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// The screen a control asked for, cleared once read.
    static func takeRoute() -> AppRoute? {
        guard let raw = SharedStore.defaults.string(forKey: routeKey) else { return nil }
        SharedStore.defaults.removeObject(forKey: routeKey)
        return AppRoute(rawValue: raw)
    }

    /// "1,240 kcal left today." or "980 kcal over today." or, without a goal, "1,020 kcal eaten today."
    static func summary(_ day: WidgetSnapshot.Day) -> String {
        guard let left = day.kcalLeft else { return "\(Format.kcal(day.eaten.kcal)) kcal eaten today." }
        let protein = day.target.map { $0.protein - day.eaten.protein } ?? 0
        let kcal = left >= 0 ? "\(Format.kcal(left)) kcal left today" : "\(Format.kcal(-left)) kcal over today"
        return protein > 0 ? "\(kcal), and \(Format.grams(protein)) of protein to go." : "\(kcal)."
    }
}

struct SavedMealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved meal"
    static let defaultQuery = SavedMealQuery()

    let id: UUID
    let name: String
    let kcal: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Format.kcal(kcal)) kcal")
    }

    init(_ meal: SharedMeal) {
        id = meal.id
        name = meal.name
        kcal = meal.totals.kcal
    }
}

struct SavedMealQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedMealEntity] {
        let meals = SharedStore.snapshot()?.meals ?? []
        return identifiers.compactMap { id in meals.first { $0.id == id }.map(SavedMealEntity.init) }
    }

    func suggestedEntities() async throws -> [SavedMealEntity] {
        (SharedStore.snapshot()?.meals ?? []).map(SavedMealEntity.init)
    }
}

/// Logs a saved meal without opening the app. Used by the Quick log widget's buttons and by Shortcuts.
struct LogSavedMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Saved Meal"
    static let description = IntentDescription("Logs one of your saved meals in EasyCal at the current time.")

    @Parameter(title: "Meal")
    var meal: SavedMealEntity

    init() {}

    init(meal: SavedMealEntity) {
        self.meal = meal
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let saved = SharedStore.snapshot()?.meals.first(where: { $0.id == meal.id }) else {
            return .result(dialog: "That meal isn't saved any more. Open EasyCal to pick another.")
        }
        let now = Date.now
        QuickLog.add(PendingLog(date: now, mealRaw: saved.mealRaw, items: saved.items, savedMealID: saved.id))
        let message = "Logged \(saved.name), \(Format.kcal(saved.totals.kcal)) kcal. \(QuickLog.summary(SharedStore.today()))"
        return .result(dialog: "\(message)")
    }
}

/// Logs a number of calories under a name, for anything that isn't saved.
struct QuickAddCaloriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add Calories"
    static let description = IntentDescription("Adds calories, and optionally protein, to today's log in EasyCal.")

    @Parameter(title: "Calories", inclusiveRange: (1, 5000))
    var kcal: Int

    @Parameter(title: "Protein (g)")
    var protein: Int?

    @Parameter(title: "Name")
    var name: String?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$kcal) kcal") {
            \.$protein
            \.$name
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let title = name?.trimmingCharacters(in: .whitespaces).isEmpty == false ? name! : "Quick add"
        let macros = Macros(kcal: Double(kcal), protein: Double(protein ?? 0), carbs: 0, fat: 0)
        QuickLog.add(PendingLog(date: now, mealRaw: Meal.suggested(for: now).rawValue,
                                items: [SavedMealItem(foodName: title, grams: 0, macros: macros, sourceRaw: "manual")]))
        return .result(dialog: "Added \(kcal) kcal. \(QuickLog.summary(SharedStore.today()))")
    }
}

/// Answers "how many calories do I have left" from the latest snapshot.
struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories Left Today"
    static let description = IntentDescription("Tells you how many calories and how much protein you have left today.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let today = SharedStore.today()
        return .result(value: Int((today.kcalLeft ?? -today.eaten.kcal).rounded()),
                       dialog: "\(QuickLog.summary(today))")
    }
}

/// Opens the app on the food camera.
struct OpenScannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Food"
    static let description = IntentDescription("Opens EasyCal on the camera to photograph a meal.")
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        QuickLog.request(.scan)
        return .result()
    }
}

/// Opens the app on saved meals and recent foods.
struct OpenSavedMealsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Saved Meals"
    static let description = IntentDescription("Opens EasyCal on your saved meals and recent foods.")
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        QuickLog.request(.saved)
        return .result()
    }
}
