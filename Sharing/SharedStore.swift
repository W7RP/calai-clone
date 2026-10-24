import Foundation

/// What the widgets, controls and Shortcuts actions can see without opening the app's database.
///
/// The app writes a snapshot of today whenever the log changes. Logging from a widget or Shortcut
/// adds a pending log here instead, which the app moves into its database the next time it runs.
/// That keeps the database owned by one process, so nothing can corrupt it or miss an update.
enum SharedStore {
    static let appGroup = "group.com.w7rp.calorietracker"

    private static let snapshotKey = "widgetSnapshot"
    private static let pendingKey = "pendingLogs"

    /// Falls back to the app's own defaults if the App Group isn't set up, so the app still runs.
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func snapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func pendingLogs() -> [PendingLog] {
        guard let data = defaults.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingLog].self, from: data)) ?? []
    }

    static func add(_ log: PendingLog) {
        setPending(pendingLogs() + [log])
    }

    /// Drops logs the app has stored, keeping any that arrived in the meantime.
    static func removePending(ids: Set<UUID>) {
        setPending(pendingLogs().filter { !ids.contains($0.id) })
    }

    private static func setPending(_ logs: [PendingLog]) {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        defaults.set(data, forKey: pendingKey)
    }

    /// Today's totals and target as the widgets should show them, pending logs included.
    static func today(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot.Day {
        (snapshot() ?? .empty).day(at: now, pending: pendingLogs(), calendar: calendar)
    }
}

/// Today as the app last saw it, plus the targets for the coming week so a stale snapshot still
/// shows the right goal after midnight.
struct WidgetSnapshot: Codable, Sendable {
    /// Start of the day `eaten` belongs to.
    var day: Date
    var eaten: Macros
    /// Start of day -> target, for today and the next six days. Missing when no goal is set.
    var targets: [Date: Macros]
    /// Saved meals for quick logging, most recently used first. Photos left out to keep it small.
    var meals: [SharedMeal]
    var updated: Date

    static let empty = WidgetSnapshot(day: .distantPast, eaten: .zero, targets: [:], meals: [], updated: .distantPast)

    struct Day: Sendable, Equatable {
        var eaten: Macros
        var target: Macros?

        var kcalLeft: Double? { target.map { $0.kcal - eaten.kcal } }
    }

    func day(at now: Date, pending: [PendingLog], calendar: Calendar = .current) -> Day {
        let today = calendar.startOfDay(for: now)
        let stored = calendar.isDate(day, inSameDayAs: today) ? eaten : .zero
        let extra = Macros.total(pending.filter { calendar.isDate($0.date, inSameDayAs: today) }.map(\.totals))
        return Day(eaten: stored + extra, target: targets[today])
    }
}

/// A saved meal as the widgets see it.
struct SharedMeal: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var mealRaw: String
    var items: [SavedMealItem]

    var totals: Macros { Macros.total(items.map(\.macros)) }
}

/// Food logged from outside the app, waiting to be stored.
struct PendingLog: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var mealRaw: String
    var items: [SavedMealItem]
    /// The saved meal it came from, so the app can bump its last-used date.
    var savedMealID: UUID?

    var totals: Macros { Macros.total(items.map(\.macros)) }
}
