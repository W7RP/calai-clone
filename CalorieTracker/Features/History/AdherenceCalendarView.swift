import SwiftUI

/// Week or month grid with each logged day green (within 10% of its goal) or red.
struct AdherenceCalendarView: View {
    /// kcal eaten, keyed by start of day.
    let kcalByDay: [Date: Double]
    let targets: DayTargets
    /// Estimated maintenance, for turning the period's average into a weekly change. Nil without a weight goal.
    let maintenance: Double?

    @State private var showMonth = false
    @State private var anchor = Date.now

    private var calendar: Calendar { targets.calendar }

    var body: some View {
        let days = showMonth
            ? CalendarGrid.month(containing: anchor, calendar: calendar).flatMap { $0 }.compactMap { $0 }
            : CalendarGrid.week(containing: anchor, calendar: calendar)
        let judged = days.compactMap(status)
        let logged = days.filter { isPast($0) && (kcalByDay[calendar.startOfDay(for: $0)] ?? 0) > 0 }
        let average = logged.isEmpty ? nil
            : logged.map { kcalByDay[calendar.startOfDay(for: $0)] ?? 0 }.reduce(0, +) / Double(logged.count)

        Picker("Period", selection: $showMonth) {
            Text("Week").tag(false)
            Text("Month").tag(true)
        }
        .pickerStyle(.segmented)

        HStack {
            Button("Previous", systemImage: "chevron.left") { move(by: -1) }
                .labelStyle(.iconOnly)
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button("Next", systemImage: "chevron.right") { move(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(containsToday)
        }
        .buttonStyle(.borderless)

        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(CalendarGrid.orderedWeekdays(calendar: calendar), id: \.self) { weekday in
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            if showMonth {
                ForEach(Array(CalendarGrid.month(containing: anchor, calendar: calendar).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { index in
                            if let day = row[index] {
                                cell(day, showKcal: false)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 36)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { cell($0, showKcal: true) }
                }
            }
        }
        .padding(.vertical, 4)

        LabeledContent("On target",
                       value: "\(judged.filter { $0 == .hit }.count) of \(judged.count) logged days")
        if let average {
            LabeledContent("Average", value: "\(NumberInput.format(average, maxFractionDigits: 0)) kcal/day")
            if let maintenance {
                LabeledContent("At this average",
                               value: "\(NumberInput.signed(EnergyMath.weeklyChangeKg(dailyIntake: average, maintenance: maintenance))) kg/week")
            }
        }
    }

    private var title: String {
        if showMonth { return anchor.formatted(.dateTime.month(.wide).year()) }
        let week = CalendarGrid.week(containing: anchor, calendar: calendar)
        guard let first = week.first, let last = week.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) - \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var containsToday: Bool {
        calendar.isDate(anchor, equalTo: .now, toGranularity: showMonth ? .month : .weekOfYear)
    }

    private func move(by step: Int) {
        anchor = calendar.date(byAdding: showMonth ? .month : .weekOfYear, value: step, to: anchor) ?? anchor
    }

    private func isPast(_ day: Date) -> Bool {
        calendar.startOfDay(for: day) < calendar.startOfDay(for: .now)
    }

    /// Today stays open until it's over, unless it's already past the upper bound.
    private func status(_ day: Date) -> Adherence? {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: .now) else { return nil }
        let eaten = kcalByDay[start] ?? 0
        let target = targets.target(on: day)?.kcal
        let result = AdherenceMath.status(eaten: eaten, target: target)
        if calendar.isDateInToday(day), result == .missed, let target, eaten < target { return nil }
        return result
    }

    private func cell(_ day: Date, showKcal: Bool) -> some View {
        let state = status(day)
        let isToday = calendar.isDateInToday(day)
        let isFuture = calendar.startOfDay(for: day) > calendar.startOfDay(for: .now)
        let fill: Color = switch state {
        case .hit: .green
        case .missed: .red
        case nil: .clear
        }
        let eaten = kcalByDay[calendar.startOfDay(for: day)] ?? 0

        return VStack(spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .frame(width: 32, height: 32)
                .background(fill.opacity(0.85), in: Circle())
                .overlay {
                    if isToday { Circle().stroke(Color.primary, lineWidth: 1.5) }
                }
                .foregroundStyle(state == nil ? Color.primary : Color.white)
            if showKcal {
                Text(eaten > 0 ? NumberInput.format(eaten, maxFractionDigits: 0) : " ")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if targets.goal(on: day)?.isCycling == true, targets.isTraining(day) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isFuture ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day, state: state, eaten: eaten))
    }

    private func accessibilityText(_ day: Date, state: Adherence?, eaten: Double) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month().day())
        switch state {
        case .hit: return "\(date), on target, \(NumberInput.format(eaten, maxFractionDigits: 0)) kcal"
        case .missed: return "\(date), off target, \(NumberInput.format(eaten, maxFractionDigits: 0)) kcal"
        case nil: return date
        }
    }
}
