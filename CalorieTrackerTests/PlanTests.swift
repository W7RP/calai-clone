import Foundation
import Testing
@testable import CalorieTracker

private func inputs(sex: Sex = .male, age: Int = 30, heightCm: Double = 180, weightKg: Double = 80,
                    lifestyle: Lifestyle = .desk, trainingDays: WeekdaySet = WeekdaySet([2, 4, 6]),
                    sessionMinutes: Double = 60, cardioMinutes: Double = 0, targetKg: Double = 75,
                    rate: Double = 0.5, cycling: Bool = false) -> PlanInputs {
    PlanInputs(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, lifestyle: lifestyle,
               trainingDays: trainingDays, sessionMinutes: sessionMinutes, cardioMinutesPerWeek: cardioMinutes,
               cardioIntensity: .moderate, targetKg: targetKg, weeklyRateKg: rate, cycling: cycling,
               cyclingShift: 0.15)
}

struct EnergyMathTests {
    @Test func mifflinStJeor() {
        #expect(EnergyMath.bmr(sex: .male, age: 30, heightCm: 180, weightKg: 80) == 1780)
        #expect(EnergyMath.bmr(sex: .female, age: 25, heightCm: 165, weightKg: 60) == 1345.25)
    }

    @Test func exerciseLeavesOutRestingBurn() {
        // (5 - 1) MET x 80 kg x 1 h
        #expect(EnergyMath.exerciseKcal(met: 5, weightKg: 80, minutes: 60) == 320)
    }

    @Test func maintenanceAddsWorkoutsSpreadOverTheWeek() {
        // 1780 x 1.2 + 3 sessions x 320 / 7
        #expect(abs(EnergyMath.maintenance(inputs()) - (2136 + 960.0 / 7)) < 1e-9)
        let withCardio = inputs(cardioMinutes: 120)
        // + (7 - 1) x 80 x 2 h / 7
        #expect(abs(EnergyMath.maintenance(withCardio) - EnergyMath.maintenance(inputs()) - 960.0 / 7) < 1e-9)
    }

    @Test func weeklyChangeFromAverageIntake() {
        #expect(abs(EnergyMath.weeklyChangeKg(dailyIntake: 2000, maintenance: 2550) - -0.5) < 1e-9)
        #expect(EnergyMath.weeklyChangeKg(dailyIntake: 2550, maintenance: 2550) == 0)
    }
}

struct PlanCalculatorTests {
    @Test func cutAtHalfAKiloAWeek() throws {
        let plan = PlanCalculator.targets(inputs())
        #expect(plan.direction == .lose)
        #expect(abs(plan.plannedWeeklyChangeKg - -0.5) < 1e-9)
        #expect(abs(plan.average.kcal - (plan.maintenance - 550)) < 1e-9)
        #expect(abs(try #require(plan.weeksToGoal) - 10) < 1e-9)
        // Protein 2 g/kg of goal weight, fat a quarter of kcal (0.6 g/kg floor), carbs the rest.
        #expect(plan.average.protein == 150)
        #expect(plan.average.fat == 48)
        #expect(plan.average.carbs == 173)
        #expect(plan.notes.isEmpty)
        #expect(plan.training == nil)
    }

    @Test func maintainingHasNoDeficit() {
        let plan = PlanCalculator.targets(inputs(targetKg: 80.3))
        #expect(plan.direction == .maintain)
        #expect(plan.average.kcal == plan.maintenance)
        #expect(plan.plannedWeeklyChangeKg == 0)
        #expect(plan.weeksToGoal == nil)
    }

    @Test func gainAddsASurplus() {
        let plan = PlanCalculator.targets(inputs(targetKg: 85, rate: 0.25))
        #expect(plan.direction == .gain)
        #expect(abs(plan.average.kcal - (plan.maintenance + 275)) < 1e-9)
        #expect(plan.notes.isEmpty)
    }

    @Test func aggressiveCutIsFlaggedAndFloored() {
        let plan = PlanCalculator.targets(inputs(sex: .female, age: 40, heightCm: 155, weightKg: 55,
                                                 trainingDays: .empty, targetKg: 50, rate: 1.0))
        #expect(plan.average.kcal == 1200)
        #expect(plan.notes.count == 2)
        // The floor slows the real pace below what was asked.
        #expect(plan.plannedWeeklyChangeKg > -1.0)
    }

    @Test func cyclingKeepsTheWeeklyTotal() throws {
        let plan = PlanCalculator.targets(inputs(cycling: true))
        let training = try #require(plan.training)
        let rest = try #require(plan.rest)
        #expect(abs(training.kcal * 3 + rest.kcal * 4 - plan.average.kcal * 7) < 1e-6)
        #expect(training.kcal > plan.average.kcal && rest.kcal < plan.average.kcal)
        #expect(training.protein == plan.average.protein && rest.fat == plan.average.fat)
        #expect(abs(training.kcal - plan.average.kcal * 1.15) < 1e-6)
    }

    @Test func cyclingNeedsBothKindsOfDay() {
        #expect(PlanCalculator.cycle(Macros(kcal: 2000, protein: 150, carbs: 200, fat: 60), trainingDays: 0, shift: 0.15) == nil)
        #expect(PlanCalculator.cycle(Macros(kcal: 2000, protein: 150, carbs: 200, fat: 60), trainingDays: 7, shift: 0.15) == nil)
        let plan = PlanCalculator.targets(inputs(trainingDays: .empty, cycling: true))
        #expect(plan.training == nil)
        #expect(plan.notes.count == 1)
    }

    @Test func cyclingNeverTakesRestDaysUnderTheCarbFloor() throws {
        let average = Macros(kcal: 2000, protein: 150, carbs: 100, fat: 60)
        let split = try #require(PlanCalculator.cycle(average, trainingDays: 5, shift: 0.25))
        #expect(split.rest.carbs == PlanCalculator.minRestCarbs)
        #expect(abs(split.training.kcal * 5 + split.rest.kcal * 2 - 14000) < 1e-6)
    }
}

struct WeekdaySetTests {
    @Test func bits() {
        var set = WeekdaySet([2, 4, 6])
        #expect(set.count == 3)
        #expect(set.contains(4) && !set.contains(5))
        set.toggle(4)
        set.toggle(1)
        #expect(set == WeekdaySet([1, 2, 6]))
        #expect(!set.contains(0) && !set.contains(8))
    }

    @Test func manualMarkBeatsSchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let schedule = WeekdaySet([7])
        #expect(TrainingSchedule.isTraining(saturday, schedule: schedule, override: nil, calendar: calendar))
        #expect(!TrainingSchedule.isTraining(saturday, schedule: schedule, override: false, calendar: calendar))
        #expect(TrainingSchedule.isTraining(saturday, schedule: .empty, override: true, calendar: calendar))
    }
}

struct AdherenceTests {
    @Test func withinTenPercentEitherSide() {
        #expect(AdherenceMath.status(eaten: 2150, target: 2000) == .hit)
        #expect(AdherenceMath.status(eaten: 1800, target: 2000) == .hit)
        #expect(AdherenceMath.status(eaten: 2250, target: 2000) == .missed)
        #expect(AdherenceMath.status(eaten: 1500, target: 2000) == .missed)
    }

    @Test func nothingToJudge() {
        #expect(AdherenceMath.status(eaten: 0, target: 2000) == nil)
        #expect(AdherenceMath.status(eaten: 1800, target: nil) == nil)
    }
}

struct CalendarGridTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    @Test func monthPadsToWholeWeeks() {
        // October 2026 starts on a Thursday.
        let sunday = calendar(firstWeekday: 1)
        let rows = CalendarGrid.month(containing: date(24, sunday), calendar: sunday)
        #expect(rows.count == 5)
        #expect(rows[0].prefix(4).allSatisfy { $0 == nil })
        #expect(rows[0][4].map { sunday.component(.day, from: $0) } == 1)
        #expect(rows.flatMap { $0 }.compactMap { $0 }.count == 31)

        let monday = calendar(firstWeekday: 2)
        let mondayRows = CalendarGrid.month(containing: date(24, monday), calendar: monday)
        #expect(mondayRows[0][3].map { monday.component(.day, from: $0) } == 1)
        #expect(mondayRows.allSatisfy { $0.count == 7 })
    }

    @Test func weekFollowsFirstWeekday() {
        let sunday = calendar(firstWeekday: 1)
        let week = CalendarGrid.week(containing: date(24, sunday), calendar: sunday)
        #expect(week.map { sunday.component(.day, from: $0) } == [18, 19, 20, 21, 22, 23, 24])

        let monday = calendar(firstWeekday: 2)
        #expect(CalendarGrid.week(containing: date(24, monday), calendar: monday).map { monday.component(.day, from: $0) }
                == [19, 20, 21, 22, 23, 24, 25])
        #expect(CalendarGrid.orderedWeekdays(calendar: monday) == [2, 3, 4, 5, 6, 7, 1])
    }
}

struct SignedFormatTests {
    @Test func signs() {
        #expect(NumberInput.signed(-0.5) == "\u{2212}0.5")
        #expect(NumberInput.signed(0.25) == "+0.25")
        #expect(NumberInput.signed(0.001) == "0")
    }
}
