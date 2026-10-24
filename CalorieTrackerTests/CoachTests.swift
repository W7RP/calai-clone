import Foundation
import Testing
@testable import CalorieTracker

struct CoachPromptTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = calendar
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: hour, minute: minute))!
    }

    private var context: CoachContext {
        CoachContext(
            now: date(18, 30),
            target: Macros(kcal: 2200, protein: 160, carbs: 230, fat: 70),
            isTrainingDay: true,
            today: [
                .init(time: date(12, 15), meal: .lunch, name: "Chicken bowl", macros: Macros(kcal: 640, protein: 52, carbs: 70, fat: 14)),
                .init(time: date(8), meal: .breakfast, name: "Oats", macros: Macros(kcal: 420, protein: 18, carbs: 60, fat: 9)),
            ],
            weekAverage: Macros(kcal: 2050, protein: 140, carbs: 210, fat: 66),
            daysLoggedThisWeek: 6,
            weekTarget: Macros(kcal: 2150, protein: 160, carbs: 220, fat: 70),
            trendKg: 82.4,
            weeklyRateKg: -0.42,
            goalKg: 78,
            plannedWeeklyChangeKg: -0.5,
            maintenanceKcal: 2700,
            savedMeals: [(name: "Protein shake", macros: Macros(kcal: 210, protein: 40, carbs: 6, fat: 3))])
    }

    @Test func rendersWhatsLeftAndTheLogInOrder() {
        let text = context.render(timeZone: .gmt)
        #expect(text.contains("Left today: 1140 kcal, 90 g protein, 100 g carbs, 47 g fat."))
        #expect(text.contains("(gym day, higher carbs)"))
        let oats = text.range(of: "Oats")!
        let bowl = text.range(of: "Chicken bowl")!
        #expect(oats.lowerBound < bowl.lowerBound)
        #expect(text.contains("Last 7 days (6 logged)"))
        #expect(text.contains("trend weight 82.4 kg, changing \u{2212}0.4 kg/week"))
        #expect(text.contains("Protein shake (210 kcal, 40 g protein"))
    }

    @Test func withoutAGoalSaysSo() {
        var context = context
        context.target = nil
        context.today = []
        let text = context.render(timeZone: .gmt)
        #expect(text.contains("No calorie goal is set."))
        #expect(text.contains("Nothing logged today yet."))
    }

    @Test func systemPromptCarriesTheData() {
        let system = CoachPrompt.system(context)
        #expect(system.contains("nutrition coach"))
        #expect(system.contains("Left today:"))
    }

    @MainActor
    @Test func requestKeepsRecentTurnsStartingWithTheUser() {
        var messages: [CoachSession.Message] = []
        for index in 0..<15 {
            messages.append(.init(role: index.isMultiple(of: 2) ? .user : .coach, text: "\(index)"))
        }
        let request = CoachSession.request(for: messages, context: context)
        #expect(request.messages.count <= CoachSession.historyLimit)
        #expect(request.messages.first?.role == .user)
        #expect(request.messages.last == .user(.text("14")))
        #expect(request.schema == nil)
    }
}
