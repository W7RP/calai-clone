import Foundation

/// What the coach knows about the user, rendered into the system prompt for every question.
/// Only numbers and food names from the log go out, to the provider the user picked.
struct CoachContext: Sendable {
    struct LoggedFood: Equatable, Sendable {
        var time: Date
        var meal: Meal
        var name: String
        var macros: Macros
    }

    var now: Date
    var target: Macros?
    var isTrainingDay: Bool?
    var today: [LoggedFood]
    /// Average over days with food logged among the last seven, today left out.
    var weekAverage: Macros?
    var daysLoggedThisWeek: Int
    var weekTarget: Macros?
    var trendKg: Double?
    var weeklyRateKg: Double?
    var goalKg: Double?
    var plannedWeeklyChangeKg: Double?
    var maintenanceKcal: Double?
    var savedMeals: [(name: String, macros: Macros)]

    var eaten: Macros { Macros.total(today.map(\.macros)) }

    func render(timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        var dateStyle = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().hour().minute()
        dateStyle.timeZone = timeZone
        var timeStyle = Date.FormatStyle.dateTime.hour().minute()
        timeStyle.timeZone = timeZone
        lines.append("Now: \(now.formatted(dateStyle)).")

        if let target {
            let left = Macros(kcal: target.kcal - eaten.kcal, protein: target.protein - eaten.protein,
                              carbs: target.carbs - eaten.carbs, fat: target.fat - eaten.fat)
            var goal = "Today's target: \(Self.describe(target))"
            if let isTrainingDay { goal += isTrainingDay ? " (gym day, higher carbs)" : " (rest day, lower carbs)" }
            lines.append(goal + ".")
            lines.append("Eaten so far: \(Self.describe(eaten)).")
            lines.append("Left today: \(Self.describe(left)). Negative means over.")
        } else {
            lines.append("No calorie goal is set. Eaten so far: \(Self.describe(eaten)).")
        }

        if today.isEmpty {
            lines.append("Nothing logged today yet.")
        } else {
            lines.append("Logged today:")
            for food in today.sorted(by: { $0.time < $1.time }) {
                lines.append("- \(food.time.formatted(timeStyle)) \(food.meal.title.lowercased()): \(food.name), \(Self.describe(food.macros))")
            }
        }

        if let weekAverage {
            var week = "Last 7 days (\(daysLoggedThisWeek) logged): average \(Self.describe(weekAverage)) per logged day"
            if let weekTarget { week += " against an average target of \(Self.describe(weekTarget))" }
            lines.append(week + ".")
        }

        var body: [String] = []
        if let trendKg { body.append("trend weight \(NumberInput.format(trendKg)) kg") }
        if let weeklyRateKg { body.append("changing \(NumberInput.signed(weeklyRateKg, maxFractionDigits: 1)) kg/week over the last 4 weeks") }
        if let goalKg { body.append("goal \(NumberInput.format(goalKg)) kg") }
        if let plannedWeeklyChangeKg { body.append("planned \(NumberInput.signed(plannedWeeklyChangeKg, maxFractionDigits: 1)) kg/week") }
        if let maintenanceKcal { body.append("estimated maintenance \(Format.kcal(maintenanceKcal)) kcal") }
        if !body.isEmpty { lines.append("Body: " + body.joined(separator: ", ") + ".") }

        if !savedMeals.isEmpty {
            lines.append("Saved meals they eat often: "
                + savedMeals.prefix(10).map { "\($0.name) (\(Self.describe($0.macros)))" }.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ m: Macros) -> String {
        "\(Format.kcal(m.kcal)) kcal, \(Format.kcal(m.protein)) g protein, \(Format.kcal(m.carbs)) g carbs, \(Format.kcal(m.fat)) g fat"
    }
}

enum CoachPrompt {
    static func system(_ context: CoachContext) -> String {
        """
        You are the nutrition coach inside EasyCal, a calorie and macro tracker. Answer the user's questions using \
        their data below. Be specific and practical: name actual foods with amounts in grams or common portions, \
        and give the calories and protein they add. When suggesting what to eat, fit what's left of today's \
        targets, the time of day, and foods they already eat (their log and saved meals) when that helps.

        Style: short and direct, like a good coach texting back. Lead with the answer. Use a short list only \
        when giving options. Plain text with at most light **bold**; no headings or tables. Metric units.

        Be honest: if they are over, say so without guilt and suggest how to balance it out over the next days. \
        Don't invent numbers that aren't in the data. You aren't a doctor: for medical conditions, medication, \
        pregnancy, eating disorders or very low intakes, keep it general and suggest a professional. Never \
        recommend going below about 1,200 kcal a day.

        The user's data:
        \(context.render())
        """
    }

    static let suggestions = [
        "What should I eat to hit my protein tonight?",
        "How am I doing this week?",
        "Give me a high-protein snack under 300 kcal",
        "What should I change to reach my goal faster?",
    ]
}
