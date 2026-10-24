import Foundation

/// Works out each day's goal from the goal history and any training/rest marks.
struct DayTargets {
    let goals: [DailyGoal]
    let calendar: Calendar
    private let marks: [Date: Bool]

    init(goals: [DailyGoal], marks: [TrainingDayMark], calendar: Calendar = .current) {
        self.goals = goals
        self.calendar = calendar
        var byDay: [Date: Bool] = [:]
        for mark in marks { byDay[calendar.startOfDay(for: mark.day)] = mark.isTraining }
        self.marks = byDay
    }

    func goal(on day: Date) -> DailyGoal? {
        GoalSelection.active(goals, on: day, effectiveFrom: \.effectiveFrom, calendar: calendar)
    }

    func mark(on day: Date) -> Bool? { marks[calendar.startOfDay(for: day)] }

    func isTraining(_ day: Date) -> Bool {
        TrainingSchedule.isTraining(day, schedule: goal(on: day)?.trainingWeekdays ?? .empty,
                                    override: mark(on: day), calendar: calendar)
    }

    func target(on day: Date) -> Macros? {
        goal(on: day)?.target(trainingDay: isTraining(day))
    }
}
