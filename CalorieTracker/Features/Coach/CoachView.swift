import SwiftData
import SwiftUI

/// Chat with the AI provider set up in Settings, which sees today's log, targets and weight trend.
struct CoachView: View {
    @Environment(CoachSession.self) private var session
    @Query(sort: \LogEntry.date, order: .reverse) private var entries: [LogEntry]
    @Query(sort: \DailyGoal.effectiveFrom, order: .reverse) private var goals: [DailyGoal]
    @Query private var marks: [TrainingDayMark]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var plans: [GoalPlan]
    @Query(sort: \SavedMeal.lastUsed, order: .reverse) private var savedMeals: [SavedMeal]

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.messages.isEmpty {
                            Intro(provider: AIProviderSettings.activeProvider.name) { ask($0) }
                        }
                        ForEach(session.messages) { message in
                            Bubble(message: message)
                                .id(message.id)
                        }
                        if session.isThinking {
                            ThinkingBubble()
                                .id("thinking")
                        }
                        if let error = session.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error)
                                    .font(.subheadline)
                                Button("Try again") { session.retry(context: context()) }
                                    .font(.subheadline.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .tint(.primary)
                            }
                            .card(padding: 14)
                            .id("error")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) {
                    if let last = session.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: session.isThinking) {
                    if session.isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            .pageBackground()
            .safeAreaInset(edge: .bottom) {
                Composer(text: $draft, focused: $focused, busy: session.isThinking) {
                    ask(draft)
                    draft = ""
                }
            }
            .navigationTitle("Coach")
            .toolbar {
                if !session.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New chat", systemImage: "square.and.pencil") { session.reset() }
                    }
                }
            }
        }
    }

    private func ask(_ question: String) {
        session.ask(question, context: context())
    }

    private func context() -> CoachContext {
        CoachContextBuilder.make(entries: entries, goals: goals, marks: marks, weights: weights, plan: plans.first,
                                 savedMeals: savedMeals)
    }
}

@MainActor
enum CoachContextBuilder {
    static func make(entries: [LogEntry], goals: [DailyGoal], marks: [TrainingDayMark], weights: [WeightEntry],
                     plan: GoalPlan?, savedMeals: [SavedMeal], now: Date = .now,
                     calendar: Calendar = .current) -> CoachContext {
        let targets = DayTargets(goals: goals, marks: marks, calendar: calendar)
        let today = entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let goal = targets.goal(on: now)

        // The seven days before today, and their average over the days something was logged.
        let start = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        var byDay: [Date: Macros] = [:]
        for entry in entries where entry.date >= weekStart && entry.date < start {
            byDay[calendar.startOfDay(for: entry.date), default: .zero] = byDay[calendar.startOfDay(for: entry.date), default: .zero] + entry.macros
        }
        let loggedDays = byDay.values.filter { $0.kcal > 0 }
        let weekAverage = loggedDays.isEmpty ? nil : Macros.total(loggedDays).scaled(by: 1 / Double(loggedDays.count))
        let weekTargets = byDay.keys.compactMap { targets.target(on: $0) }
        let weekTarget = weekTargets.isEmpty ? nil : Macros.total(weekTargets).scaled(by: 1 / Double(weekTargets.count))

        let trend = WeightTrend.points(weights.map { ($0.date, $0.kilograms) }, calendar: calendar)
        let inputs = plan.flatMap { plan in trend.last.map { plan.inputs(weightKg: $0.trend, on: now, calendar: calendar) } }
        let planned = inputs.map(PlanCalculator.targets)

        return CoachContext(
            now: now,
            target: targets.target(on: now),
            isTrainingDay: goal?.isCycling == true ? targets.isTraining(now) : nil,
            today: today.map { CoachContext.LoggedFood(time: $0.date, meal: $0.meal, name: $0.foodName, macros: $0.macros) },
            weekAverage: weekAverage,
            daysLoggedThisWeek: loggedDays.count,
            weekTarget: weekTarget,
            trendKg: trend.last?.trend,
            weeklyRateKg: WeightTrend.weeklyRate(trend, calendar: calendar),
            goalKg: plan?.targetKg,
            plannedWeeklyChangeKg: planned?.plannedWeeklyChangeKg,
            maintenanceKcal: planned?.maintenance,
            savedMeals: savedMeals.prefix(10).map { ($0.name, $0.totals) })
    }
}

private struct Intro: View {
    let provider: String
    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
            Text("Ask your coach")
                .font(.title2.bold())
            Text("It sees today's log, your targets and your weight trend, and answers with \(provider). Only those numbers and food names are sent.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(CoachPrompt.suggestions, id: \.self) { suggestion in
                Button {
                    onAsk(suggestion)
                } label: {
                    HStack {
                        Text(suggestion)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.bold())
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .card(padding: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }
}

private struct Bubble: View {
    let message: CoachSession.Message

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(Self.markdown(message.text))
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(isUser ? Color(UIColor.systemBackground) : .primary)
                .background(isUser ? Color.primary : Theme.card, in: .rect(cornerRadius: 20))
                .shadow(color: .black.opacity(isUser ? 0 : 0.04), radius: 8, y: 2)
            if !isUser { Spacer(minLength: 24) }
        }
    }

    /// Bold, italics and links from the reply; anything else shows as typed.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct ThinkingBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Thinking…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }
}

private struct Composer: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let busy: Bool
    let onSend: () -> Void

    var body: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about food, macros or your goal", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused(focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.card, in: .rect(cornerRadius: 22))
                .onSubmit { if !empty && !busy { onSend() } }
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(empty || busy ? 0.25 : 1), in: .circle)
            }
            .disabled(empty || busy)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.page)
    }
}
