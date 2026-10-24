import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female

    var id: String { rawValue }
    var title: String { self == .male ? "Male" : "Female" }
}

/// Day-to-day movement outside workouts. Workouts are added separately so they aren't counted twice.
enum Lifestyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case desk, light, onFeet, physical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desk: "Mostly sitting"
        case .light: "Lightly active"
        case .onFeet: "On my feet"
        case .physical: "Physical job"
        }
    }

    var detail: String {
        switch self {
        case .desk: "Desk job, under ~5,000 steps"
        case .light: "Some walking, ~5,000-8,000 steps"
        case .onFeet: "Standing or walking most of the day"
        case .physical: "Manual labour, lifting all day"
        }
    }

    /// Multiplier on BMR, slightly below the textbook activity factors because those include exercise.
    var factor: Double {
        switch self {
        case .desk: 1.2
        case .light: 1.35
        case .onFeet: 1.5
        case .physical: 1.7
        }
    }
}

enum CardioIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy, moderate, hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }

    var detail: String {
        switch self {
        case .easy: "Brisk walk, easy bike"
        case .moderate: "Jog, steady cycling, rowing"
        case .hard: "Running, intervals, spin class"
        }
    }

    /// Compendium of Physical Activities, rounded.
    var met: Double {
        switch self {
        case .easy: 4
        case .moderate: 7
        case .hard: 10
        }
    }
}

/// Weekdays as a bitmask, using Calendar's numbering (1 = Sunday ... 7 = Saturday).
struct WeekdaySet: Equatable, Sendable {
    var rawValue: Int

    static let empty = WeekdaySet(rawValue: 0)

    init(rawValue: Int) { self.rawValue = rawValue & 0b111_1111 }

    init(_ weekdays: [Int]) {
        self.init(rawValue: weekdays.reduce(0) { $0 | WeekdaySet.bit($1) })
    }

    var count: Int { rawValue.nonzeroBitCount }

    func contains(_ weekday: Int) -> Bool { rawValue & WeekdaySet.bit(weekday) != 0 }

    mutating func toggle(_ weekday: Int) { rawValue ^= WeekdaySet.bit(weekday) }

    func contains(day: Date, calendar: Calendar = .current) -> Bool {
        contains(calendar.component(.weekday, from: day))
    }

    private static func bit(_ weekday: Int) -> Int { (1..<8).contains(weekday) ? 1 << (weekday - 1) : 0 }
}

/// Everything the calorie target is worked out from.
struct PlanInputs: Equatable, Sendable {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var lifestyle: Lifestyle
    var trainingDays: WeekdaySet
    var sessionMinutes: Double
    var cardioMinutesPerWeek: Double
    var cardioIntensity: CardioIntensity
    var targetKg: Double
    /// Size of the weekly change asked for, always positive. The direction comes from target vs. current weight.
    var weeklyRateKg: Double
    var cycling: Bool
    /// Share of the average day's kcal moved onto each training day when cycling.
    var cyclingShift: Double
}

enum GoalDirection: Equatable, Sendable {
    case lose, maintain, gain

    /// Within half a kilo of the target counts as there.
    static func between(current: Double, target: Double) -> GoalDirection {
        if target < current - 0.5 { return .lose }
        if target > current + 0.5 { return .gain }
        return .maintain
    }
}

struct PlanTargets: Equatable, Sendable {
    var bmr: Double
    var maintenance: Double
    /// Average daily target across the week. This is what a plain DailyGoal would hold.
    var average: Macros
    /// Set only when cycling is on and there's at least one training and one rest day.
    var training: Macros?
    var rest: Macros?
    var direction: GoalDirection
    /// Signed kg per week the target works out to.
    var plannedWeeklyChangeKg: Double
    var weeksToGoal: Double?
    var notes: [String]
}

enum EnergyMath {
    /// Rule of thumb for body fat: about 7,700 kcal per kg.
    static let kcalPerKg = 7700.0
    /// Resistance training, general to vigorous, with rest between sets.
    static let gymMET = 5.0

    /// Mifflin-St Jeor resting energy.
    static func bmr(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    /// kcal burned above resting during an activity: (MET - 1) x kg x hours.
    /// The resting MET is already in BMR, so it's taken out here.
    static func exerciseKcal(met: Double, weightKg: Double, minutes: Double) -> Double {
        max(0, met - 1) * weightKg * minutes / 60
    }

    /// Workouts per week spread evenly over seven days.
    static func dailyExerciseKcal(_ inputs: PlanInputs) -> Double {
        let gym = exerciseKcal(met: gymMET, weightKg: inputs.weightKg,
                               minutes: inputs.sessionMinutes * Double(inputs.trainingDays.count))
        let cardio = exerciseKcal(met: inputs.cardioIntensity.met, weightKg: inputs.weightKg,
                                  minutes: inputs.cardioMinutesPerWeek)
        return (gym + cardio) / 7
    }

    static func maintenance(_ inputs: PlanInputs) -> Double {
        bmr(sex: inputs.sex, age: inputs.age, heightCm: inputs.heightCm, weightKg: inputs.weightKg)
            * inputs.lifestyle.factor + dailyExerciseKcal(inputs)
    }

    /// Expected kg per week from eating `dailyIntake` on average against `maintenance`. Negative is a loss.
    static func weeklyChangeKg(dailyIntake: Double, maintenance: Double) -> Double {
        (dailyIntake - maintenance) * 7 / kcalPerKg
    }
}

enum PlanCalculator {
    /// Rest days never drop below this many grams of carbs when cycling.
    static let minRestCarbs = 50.0

    static func targets(_ inputs: PlanInputs) -> PlanTargets {
        let bmr = EnergyMath.bmr(sex: inputs.sex, age: inputs.age, heightCm: inputs.heightCm, weightKg: inputs.weightKg)
        let maintenance = EnergyMath.maintenance(inputs)
        let direction = GoalDirection.between(current: inputs.weightKg, target: inputs.targetKg)
        var notes: [String] = []

        let rate = direction == .maintain ? 0 : max(0, inputs.weeklyRateKg)
        let signedRate = direction == .lose ? -rate : rate
        var kcal = maintenance + signedRate * EnergyMath.kcalPerKg / 7

        if direction == .lose, rate > inputs.weightKg * 0.01 {
            notes.append("Losing more than 1% of body weight a week makes it hard to keep muscle. Consider a slower pace.")
        }
        if direction == .gain, rate > 0.5 {
            notes.append("Gaining faster than 0.5 kg a week is mostly fat for anyone past their first year of lifting.")
        }

        // Below these intakes it's hard to cover basic nutrition without supervision.
        let floor: Double = inputs.sex == .male ? 1500 : 1200
        if kcal < floor {
            kcal = floor
            notes.append("Raised to \(NumberInput.format(floor, maxFractionDigits: 0)) kcal, the usual minimum without medical supervision.")
        }

        let planned = EnergyMath.weeklyChangeKg(dailyIntake: kcal, maintenance: maintenance)
        let average = macros(kcal: kcal, inputs: inputs, direction: direction)

        var weeksToGoal: Double?
        if direction != .maintain, abs(planned) > 0.01 {
            weeksToGoal = abs(inputs.targetKg - inputs.weightKg) / abs(planned)
        }

        var training: Macros?
        var rest: Macros?
        if inputs.cycling {
            if let split = cycle(average, trainingDays: inputs.trainingDays.count, shift: inputs.cyclingShift) {
                training = split.training
                rest = split.rest
            } else if inputs.trainingDays.count == 0 || inputs.trainingDays.count == 7 {
                notes.append("Carb cycling needs at least one training day and one rest day.")
            } else {
                notes.append("Carbs are too low to cycle without dropping rest days under \(Int(minRestCarbs)) g.")
            }
        }

        return PlanTargets(bmr: bmr, maintenance: maintenance, average: average, training: training, rest: rest,
                           direction: direction, plannedWeeklyChangeKg: planned, weeksToGoal: weeksToGoal,
                           notes: notes)
    }

    /// Protein by body weight, fat at a quarter of kcal (with a floor), carbs fill the rest.
    static func macros(kcal: Double, inputs: PlanInputs, direction: GoalDirection) -> Macros {
        // Cutting: more protein to hold muscle, scaled to goal weight so it isn't inflated by fat mass.
        let proteinBase = direction == .lose ? 2.0 * inputs.targetKg : 1.8 * inputs.weightKg
        let protein = min(proteinBase, kcal * 0.35 / 4)
        let fat = max(kcal * 0.25 / 9, 0.6 * inputs.weightKg)
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return Macros(kcal: kcal, protein: protein.rounded(), carbs: carbs.rounded(), fat: fat.rounded())
    }

    /// Moves carbs from rest days to training days, keeping the weekly total the same.
    /// Nil when there's nothing to cycle.
    static func cycle(_ average: Macros, trainingDays: Int, shift: Double) -> (training: Macros, rest: Macros)? {
        guard (1...6).contains(trainingDays), shift > 0 else { return nil }
        let restDays = Double(7 - trainingDays)
        var bonus = average.kcal * shift
        var cut = bonus * Double(trainingDays) / restDays
        let maxCut = (average.carbs - minRestCarbs) * 4
        guard maxCut > 0 else { return nil }
        if cut > maxCut {
            cut = maxCut
            bonus = cut * restDays / Double(trainingDays)
        }
        var training = average
        training.kcal += bonus
        training.carbs = (training.carbs + bonus / 4).rounded()
        var rest = average
        rest.kcal -= cut
        rest.carbs = (rest.carbs - cut / 4).rounded()
        return (training, rest)
    }
}

enum Adherence: Equatable, Sendable {
    case hit, missed
}

enum AdherenceMath {
    /// A day counts as on target within 10% either side of its kcal goal.
    static let tolerance = 0.10

    /// Nil when there's nothing to judge: no goal, or nothing logged.
    static func status(eaten: Double, target: Double?) -> Adherence? {
        guard let target, target > 0, eaten > 0 else { return nil }
        return abs(eaten - target) <= target * tolerance ? .hit : .missed
    }
}

enum CalendarGrid {
    /// The seven days of the week containing `day`, starting on the calendar's first weekday.
    static func week(containing day: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Rows of seven for the month containing `day`. Nil pads the days before the 1st and after the last.
    static func month(containing day: Date, calendar: Calendar = .current) -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: day),
              let count = calendar.range(of: .day, in: .month, for: day)?.count else { return [] }
        let lead = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Weekday numbers (1 = Sunday) in display order for the calendar's first weekday.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

enum TrainingSchedule {
    /// A day the user marked by hand wins over the weekly schedule.
    static func isTraining(_ day: Date, schedule: WeekdaySet, override: Bool?, calendar: Calendar = .current) -> Bool {
        override ?? schedule.contains(day: day, calendar: calendar)
    }
}

extension NumberInput {
    /// "+0.25" / "−0.5" with a real minus sign, for weight change.
    static func signed(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let magnitude = format(abs(value), maxFractionDigits: maxFractionDigits)
        if magnitude == format(0, maxFractionDigits: maxFractionDigits) { return magnitude }
        return (value < 0 ? "\u{2212}" : "+") + magnitude
    }
}
