import SwiftData
import SwiftUI

enum Onboarding {
    static let doneKey = "onboardingDone"
}

/// First run: one question per screen, then the plan those answers give.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, sex, age, height, weight, lifestyle, gym, goal, target, pace, cycling, building, plan, ai
    }

    enum Goal: CaseIterable, Identifiable {
        case lose, maintain, gain

        var id: Self { self }

        var title: String {
            switch self {
            case .lose: "Lose weight"
            case .maintain: "Maintain"
            case .gain: "Gain weight"
            }
        }

        var symbol: String {
            switch self {
            case .lose: "arrow.down.right"
            case .maintain: "equal"
            case .gain: "arrow.up.right"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @AppStorage(Onboarding.doneKey) private var onboarded = false
    @Query private var plans: [GoalPlan]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var step = Step.welcome
    @State private var goingBack = false
    @State private var loaded = false
    @State private var sex: Sex?
    @State private var age = 30
    @State private var heightCm = 175
    @State private var weightKg = 75
    @State private var lifestyle: Lifestyle?
    @State private var trainingDays = WeekdaySet.empty
    @State private var goal: Goal?
    @State private var targetKg = 70
    @State private var rate = 0.5
    @State private var cycling: Bool?
    @State private var showingAISetup = false
    @State private var openedAISetup = false

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                topBar
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                        .id(step)
                        .transition(.asymmetric(insertion: .move(edge: goingBack ? .leading : .trailing),
                                                removal: .move(edge: goingBack ? .trailing : .leading))
                            .combined(with: .opacity))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            bottomBar
        }
        .pageBackground()
        .onAppear(perform: load)
        .sheet(isPresented: $showingAISetup) {
            NavigationStack {
                AIProviderSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingAISetup = false }
                        }
                    }
            }
        }
    }

    // MARK: Layout

    private var topBar: some View {
        HStack(spacing: 16) {
            Button("Back", systemImage: "chevron.left", action: back)
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Theme.card, in: .circle)
                .disabled(step == .building)
                .opacity(step == .building ? 0 : 1)
            ProgressView(value: progress)
                .tint(.primary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                Button("Get started") { advance() }
                    .buttonStyle(.primary)
                Button("Skip setup, I'll do it later") { onboarded = true }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .building:
                EmptyView()
            case .plan:
                Button("Let's go") {
                    if let inputs { PlanStore.save(inputs, in: context) }
                    advance()
                }
                .buttonStyle(.primary)
            case .ai:
                if openedAISetup {
                    Button("Start logging") { onboarded = true }
                        .buttonStyle(.primary)
                    Button("Change AI settings") { showingAISetup = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Set up AI") {
                        openedAISetup = true
                        showingAISetup = true
                    }
                    .buttonStyle(.primary)
                    Button("Later, I'll log by hand for now") { onboarded = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            default:
                Button("Continue") { advance() }
                    .buttonStyle(.primary)
                    .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .tint(.primary)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 80)
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .frame(width: 88, height: 88)
                    .background(Color.primary, in: .rect(cornerRadius: 24))
                Text("Calorie tracking\nmade easy")
                    .font(.system(size: 40, weight: .bold))
                Text("Snap a photo, scan a barcode or just say what you ate. Your own AI does the counting.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "camera.viewfinder", text: "Photo in, calories and macros out")
                    Feature(symbol: "target", text: "A daily target built from your goal")
                    Feature(symbol: "lock", text: "No account, no subscription. Data stays on your phone")
                }
                .padding(.top, 12)
            }
        case .sex:
            Question(title: "What's your sex?", subtitle: "Used to estimate how much energy you burn at rest.") {
                ForEach(Sex.allCases) { option in
                    OptionRow(title: option.title, isSelected: sex == option) { sex = option }
                }
            }
        case .age:
            Question(title: "How old are you?", subtitle: "Your resting burn drops a little with age.") {
                WheelPicker(selection: $age, values: Array(14...100), unit: "years")
            }
        case .height:
            Question(title: "How tall are you?", subtitle: "In centimetres.") {
                WheelPicker(selection: $heightCm, values: Array(120...220), unit: "cm")
            }
        case .weight:
            Question(title: "What do you weigh now?", subtitle: "In kilograms. You can log your weight any time later.") {
                WheelPicker(selection: $weightKg, values: Array(35...250), unit: "kg")
            }
        case .lifestyle:
            Question(title: "How active is your day?", subtitle: "Outside of workouts. Those come next.") {
                ForEach(Lifestyle.allCases) { option in
                    OptionRow(title: option.title, detail: option.detail, isSelected: lifestyle == option) {
                        lifestyle = option
                    }
                }
            }
        case .gym:
            Question(title: "Which days do you train?",
                     subtitle: "Lifting or any gym session of about an hour. Skip if you don't train.") {
                WeekdayPicker(selection: $trainingDays)
                    .padding(.vertical, 8)
                Text(trainingDays.count == 0 ? "No gym days" : "\(trainingDays.count) days a week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .goal:
            Question(title: "What's your goal?", subtitle: "This sets your daily calorie target.") {
                ForEach(Goal.allCases) { option in
                    OptionRow(title: option.title, symbol: option.symbol, isSelected: goal == option) {
                        goal = option
                    }
                }
            }
        case .target:
            Question(title: "What's your goal weight?",
                     subtitle: goal == .gain ? "Pick a weight above \(weightKg) kg." : "Pick a weight below \(weightKg) kg.") {
                WheelPicker(selection: $targetKg, values: targetRange, unit: "kg")
            }
        case .pace:
            Question(title: goal == .gain ? "How fast do you want to gain?" : "How fast do you want to lose?",
                     subtitle: "Slower is easier to stick to.") {
                ForEach(PlanView.rates, id: \.self) { option in
                    OptionRow(title: "\(NumberInput.format(option, maxFractionDigits: 2)) kg per week",
                              detail: paceDetail(option), isSelected: rate == option) { rate = option }
                }
            }
        case .cycling:
            Question(title: "Try carb cycling?",
                     subtitle: "More carbs on gym days, fewer on rest days. The weekly total stays the same.") {
                OptionRow(title: "Yes, cycle my carbs", symbol: "arrow.triangle.2.circlepath", isSelected: cycling == true) {
                    cycling = true
                }
                OptionRow(title: "No, same target every day", symbol: "equal", isSelected: cycling == false) {
                    cycling = false
                }
            }
        case .building:
            BuildingPlan { advance() }
        case .plan:
            if let inputs {
                PlanSummary(inputs: inputs, targets: PlanCalculator.targets(inputs))
            }
        case .ai:
            Question(title: "Connect your AI",
                     subtitle: "EasyCal reads your photos and descriptions with an AI you already have. Sign in with ChatGPT, or paste a Claude, OpenAI or Gemini key.") {
                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "person.crop.circle.badge.checkmark", text: "Use your ChatGPT plan, no key needed")
                    Feature(symbol: "key", text: "Keys stay in the iPhone Keychain")
                    Feature(symbol: "barcode.viewfinder", text: "Barcodes and manual entry work without AI")
                }
                .card(padding: 20)
            }
        }
    }

    // MARK: Flow

    private var visibleSteps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .target, .pace: goal != .maintain
            case .cycling: trainingDays.count > 0
            default: true
            }
        }
    }

    private var progress: Double {
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step), steps.count > 1 else { return 0 }
        return Double(index) / Double(steps.count - 1)
    }

    private var canContinue: Bool {
        switch step {
        case .sex: sex != nil
        case .lifestyle: lifestyle != nil
        case .goal: goal != nil
        case .cycling: cycling != nil
        case .target: goal == .gain ? targetKg > weightKg : targetKg < weightKg
        default: true
        }
    }

    private var targetRange: [Int] {
        goal == .gain ? Array((weightKg + 1)...max(weightKg + 1, 250)) : Array(35...max(35, weightKg - 1))
    }

    private func advance() {
        // Keep the goal weight on the right side of the current weight when the goal changes.
        if step == .goal {
            switch goal {
            case .lose: if targetKg >= weightKg { targetKg = max(35, weightKg - 5) }
            case .gain: if targetKg <= weightKg { targetKg = min(250, weightKg + 5) }
            default: break
            }
        }
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        goingBack = false
        withAnimation(.snappy) { step = steps[index + 1] }
    }

    private func back() {
        var steps = visibleSteps
        steps.removeAll { $0 == .building }
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        goingBack = true
        withAnimation(.snappy) { step = steps[index - 1] }
    }

    private var inputs: PlanInputs? {
        guard let sex, let lifestyle else { return nil }
        let target = goal == .maintain || goal == nil ? weightKg : targetKg
        return PlanInputs(sex: sex, age: age, heightCm: Double(heightCm), weightKg: Double(weightKg),
                          lifestyle: lifestyle, trainingDays: trainingDays,
                          sessionMinutes: trainingDays.count > 0 ? 60 : 0, cardioMinutesPerWeek: 0,
                          cardioIntensity: .moderate, targetKg: Double(target), weeklyRateKg: rate,
                          cycling: cycling == true && trainingDays.count > 0, cyclingShift: 0.15)
    }

    private func paceDetail(_ rate: Double) -> String {
        let gap = abs(Double(targetKg - weightKg))
        guard gap > 0 else { return "" }
        let weeks = Int((gap / rate).rounded(.up))
        guard let date = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: .now) else { return "" }
        return "Reach \(targetKg) kg around \(date.formatted(.dateTime.month(.abbreviated).year()))"
    }

    /// Answers already given, for when the questions are run again from Settings.
    private func load() {
        guard !loaded else { return }
        loaded = true
        // Writes the key, so saving the plan halfway through doesn't make the root treat this as an old install.
        onboarded = false
        if let latest = weights.last { weightKg = Int(latest.kilograms.rounded()) }
        guard let plan = plans.first else { return }
        sex = plan.sex
        age = min(100, max(14, Calendar.current.component(.year, from: .now) - plan.birthYear))
        heightCm = Int(plan.heightCm.rounded())
        lifestyle = plan.lifestyle
        trainingDays = plan.trainingWeekdays
        targetKg = Int(plan.targetKg.rounded())
        let direction: Goal = switch GoalDirection.between(current: Double(weightKg), target: plan.targetKg) {
        case .lose: .lose
        case .maintain: .maintain
        case .gain: .gain
        }
        goal = direction
        if PlanView.rates.contains(plan.weeklyRateKg) { rate = plan.weeklyRateKg }
        cycling = plan.cycling
    }
}

// MARK: - Pieces

private struct Question<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 24)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.top, 32)
        }
    }
}

/// A big selectable row. Selected rows go black.
private struct OptionRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.headline)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .opacity(0.7)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : Color.primary)
            .background(isSelected ? Color.primary : Theme.card, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct WheelPicker: View {
    @Binding var selection: Int
    let values: [Int]
    let unit: String

    var body: some View {
        Picker(unit, selection: $selection) {
            ForEach(values, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .card(padding: 8)
        .onAppear {
            // A value from an earlier answer can sit outside a narrowed range.
            if !values.contains(selection), let nearest = values.min(by: { abs($0 - selection) < abs($1 - selection) }) {
                selection = nearest
            }
        }
    }
}

private struct Feature: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Theme.quiet, in: .circle)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
    }
}

/// A short pause with a filling ring, so the plan feels worked out rather than instant.
private struct BuildingPlan: View {
    let onDone: () -> Void
    @State private var progress = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 100)
            ProgressRing(progress: progress, lineWidth: 12) {
                Text("\(Int(progress * 100))%")
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 160, height: 160)
            Text("Building your plan")
                .font(.title2.bold())
            Text("Working out your burn, target and macros")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .task {
            for tick in 1...20 {
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation { progress = Double(tick) / 20 }
            }
            try? await Task.sleep(for: .milliseconds(300))
            onDone()
        }
    }
}

private struct PlanSummary: View {
    let inputs: PlanInputs
    let targets: PlanTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark")
                .font(.title2.bold())
                .foregroundStyle(Color(UIColor.systemBackground))
                .frame(width: 48, height: 48)
                .background(Color.primary, in: .circle)
                .padding(.top, 24)
            Text("Your plan is ready")
                .font(.system(size: 32, weight: .bold))
            if let weeks = targets.weeksToGoal,
               let date = Calendar.current.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: .now) {
                Text("You could reach \(NumberInput.format(inputs.targetKg)) kg by \(date.formatted(.dateTime.month(.wide).day().year())).")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("Eat around this to hold your weight steady.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                Text("Daily target").font(.headline)
                HStack(spacing: 18) {
                    ProgressRing(progress: 1, lineWidth: 10) {
                        Image(systemName: "flame.fill").font(.title2)
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading) {
                        Text(Format.kcal(targets.average.kcal))
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                        Text(targets.training == nil ? "calories a day" : "calories on an average day")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(MacroKind.allCases) { kind in
                        VStack(spacing: 8) {
                            ProgressRing(progress: 1, lineWidth: 6) {
                                Image(systemName: kind.symbol).font(.subheadline)
                            }
                            .frame(width: 52, height: 52)
                            Text(Format.grams(kind.value(targets.average))).font(.headline).monospacedDigit()
                            Text(kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.quiet, in: .rect(cornerRadius: 16))
                    }
                }
                if let training = targets.training, let rest = targets.rest {
                    HStack {
                        Label("Gym days \(Format.kcal(training.kcal))", systemImage: "dumbbell.fill")
                        Spacer()
                        Label("Rest days \(Format.kcal(rest.kcal))", systemImage: "bed.double.fill")
                    }
                    .font(.subheadline)
                }
            }
            .card(padding: 20)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(targets.notes, id: \.self) { Text($0).foregroundStyle(.orange) }
                Text("An estimate, usually within about 10%. Weigh in weekly and adjust in Settings if your weight isn't moving as expected after 2-3 weeks.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
    }
}
