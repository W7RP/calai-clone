import Foundation

enum Meal: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// Default meal for a new entry, so logging at 12:30 doesn't need a tap to pick "Lunch".
    static func suggested(for date: Date, calendar: Calendar = .current) -> Meal {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}
