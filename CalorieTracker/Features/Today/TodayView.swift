import SwiftData
import SwiftUI

/// Home: the week strip, what's left today, and every food logged, with one + button for adding more.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AnalysisCenter.self) private var analysis
    @Query private var allEntries: [LogEntry]

    @State private var day = Date.now
    @State private var editor: EntryEditor?
    @State private var showingAddMenu = false
    @State private var pendingAction: AddAction?
    @State private var scannerMode: FoodScannerView.Mode?
    @State private var scannedCode: ScannedCode?
    @State private var showingTypedScan = false
    @State private var showingMyFoods = false
    @State private var showingDescribe = false
    @State private var barcodeNotFound: String?
    @State private var review: ReviewTarget?

    var body: some View {
        let loggedDays = Set(allEntries.map { Calendar.current.startOfDay(for: $0.date) })

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HomeHeader(streak: DayMath.streak(loggedDays: loggedDays),
                               showsToday: !Calendar.current.isDateInToday(day)) { day = .now }
                    WeekStrip(selection: $day, loggedDays: loggedDays)
                    DayLog(day: day, editor: $editor) { review = ReviewTarget(id: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showingAddMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .frame(width: 62, height: 62)
                        .background(Color.primary, in: .circle)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .accessibilityLabel("Add food")
                .padding(20)
            }
            .sheet(isPresented: $showingAddMenu, onDismiss: runPendingAction) {
                AddMenuView { action in
                    pendingAction = action
                    showingAddMenu = false
                }
                .presentationDetents([.height(380)])
                .presentationCornerRadius(32)
            }
            .fullScreenCover(item: $scannerMode, onDismiss: {
                // Two sheets can't overlap, so the barcode lookup opens once the camera is gone.
                if let code = pendingCode {
                    pendingCode = nil
                    scannedCode = ScannedCode(code: code)
                }
            }) { mode in
                FoodScannerView(startIn: mode) { result in
                    switch result {
                    case .photo(let data):
                        analysis.start(day: day, description: "", photo: data)
                    case .barcode(let code):
                        pendingCode = code
                    }
                }
            }
            .sheet(item: $editor) { editor in
                EntryFormView(editor: editor)
            }
            .sheet(item: $scannedCode, onDismiss: openManualForMissingBarcode) { scanned in
                ScanFlowView(day: day, initialCode: scanned.code) { barcodeNotFound = $0 }
            }
            .sheet(isPresented: $showingTypedScan, onDismiss: openManualForMissingBarcode) {
                ScanFlowView(day: day) { barcodeNotFound = $0 }
            }
            .sheet(isPresented: $showingMyFoods) {
                MyFoodsView(day: day)
            }
            .sheet(isPresented: $showingDescribe) {
                AIAddView(day: day)
            }
            .sheet(item: $review) { target in
                ReviewSheet(id: target.id) { review = nil }
            }
            .onChange(of: readyJobs) { old, new in
                // Open the review as soon as an estimate lands, unless something else is on screen.
                guard let first = new.first(where: { !old.contains($0) }), nothingPresented else { return }
                review = ReviewTarget(id: first)
            }
        }
    }

    @State private var pendingCode: String?

    private var readyJobs: [UUID] {
        analysis.jobs.compactMap { job in
            if case .ready = job.state { job.id } else { nil }
        }
    }

    private var nothingPresented: Bool {
        !showingAddMenu && scannerMode == nil && scannedCode == nil && editor == nil && !showingTypedScan
            && !showingMyFoods && !showingDescribe && review == nil
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .scanFood:
            if FoodScannerView.isAvailable { scannerMode = .food } else { showingDescribe = true }
        case .barcode:
            if FoodScannerView.isAvailable { scannerMode = .barcode } else { showingTypedScan = true }
        case .describe:
            showingDescribe = true
        case .myFoods:
            showingMyFoods = true
        case .manual:
            editor = .new(day: day)
        case .copy(let meal):
            LogActions.copyPreviousDay(to: day, meal: meal, in: context)
        }
    }

    private func openManualForMissingBarcode() {
        if let code = barcodeNotFound {
            barcodeNotFound = nil
            editor = .new(day: day, barcode: code)
        }
    }
}

/// Foods waiting for a name before they're saved as a meal.
private struct PendingSave {
    let entries: [LogEntry]
    let meal: Meal

    var suggestedName: String { SavedMealNaming.suggestion(for: entries.map(\.foodName)) }
}

private struct ScannedCode: Identifiable {
    let code: String
    var id: String { code }
}

private struct ReviewTarget: Identifiable {
    let id: UUID
}

/// The review screen for a finished estimate, in its own navigation stack.
private struct ReviewSheet: View {
    @Environment(AnalysisCenter.self) private var analysis
    let id: UUID
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            if let job = analysis.job(id), case .ready(let estimate) = job.state {
                ReviewView(estimate: estimate, day: job.day, photo: job.jpeg, thumbnail: job.thumbnail) {
                    analysis.remove(id)
                    onClose()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Later") { onClose() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Discard", role: .destructive) {
                            analysis.remove(id)
                            onClose()
                        }
                    }
                }
            } else {
                ContentUnavailableView("Nothing to review", systemImage: "sparkles")
            }
        }
    }
}

/// What the entry sheet is editing: a new entry for a day, or an existing one.
enum EntryEditor: Identifiable {
    case new(day: Date, barcode: String? = nil)
    case edit(LogEntry)

    var id: String {
        switch self {
        case .new(let day, let barcode): "new-\(day.timeIntervalSince1970)-\(barcode ?? "")"
        case .edit(let entry): entry.id.uuidString
        }
    }
}

private struct HomeHeader: View {
    let streak: Int
    let showsToday: Bool
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.title2)
            Text("EasyCal")
                .font(.title2.bold())
            Spacer()
            if showsToday {
                Button(action: onToday) { Chip(text: "Today", symbol: "arrow.uturn.left") }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(streak)")
                    .monospacedDigit()
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.card, in: .capsule)
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak) day streak")
        }
        .padding(.top, 8)
    }
}

/// The list for one day. Separate from TodayView so its @Query can be rebuilt when the day changes.
private struct DayLog: View {
    @Environment(\.modelContext) private var context
    @Environment(AnalysisCenter.self) private var analysis
    @Query private var entries: [LogEntry]
    @Query(sort: \DailyGoal.effectiveFrom, order: .reverse) private var goals: [DailyGoal]
    @Query private var marks: [TrainingDayMark]
    @Query(sort: \SavedMeal.lastUsed, order: .reverse) private var savedMeals: [SavedMeal]
    @Binding var editor: EntryEditor?
    @State private var saving: PendingSave?
    @State private var mealName = ""
    @State private var quickLogged = 0
    let day: Date
    let onReview: (UUID) -> Void

    init(day: Date, editor: Binding<EntryEditor?>, onReview: @escaping (UUID) -> Void) {
        self.day = day
        self.onReview = onReview
        _editor = editor
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(filter: #Predicate<LogEntry> { $0.date >= start && $0.date < end }, sort: \.date)
        _marks = Query(filter: #Predicate<TrainingDayMark> { $0.day >= start && $0.day < end })
    }

    var body: some View {
        let totals = Macros.total(entries.map(\.macros))
        let targets = DayTargets(goals: goals, marks: marks)
        let goal = targets.goal(on: day)
        let isTraining = targets.isTraining(day)
        let target = goal?.target(trainingDay: isTraining)
        let jobs = analysis.jobs.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }

        VStack(alignment: .leading, spacing: 16) {
            CalorieCard(eaten: totals.kcal, goal: target?.kcal)

            HStack(spacing: 10) {
                ForEach(MacroKind.allCases) { kind in
                    MacroCard(kind: kind, eaten: kind.value(totals), goal: target.map(kind.value))
                }
            }

            if let goal, goal.isCycling {
                GymDayCard(isTraining: Binding(get: { isTraining },
                                               set: { setTraining($0, schedule: goal.trainingWeekdays) }))
            }

            if !savedMeals.isEmpty {
                QuickAddStrip(meals: Array(savedMeals.prefix(8))) { saved in
                    withAnimation { _ = LogActions.log(saved, on: day, in: context) }
                    quickLogged += 1
                }
            }

            Text("Food log")
                .font(.title3.bold())
                .padding(.top, 8)

            ForEach(jobs) { job in
                AnalyzingCard(job: job,
                              onReview: { onReview(job.id) },
                              onRetry: { analysis.retry(job.id) },
                              onDiscard: { withAnimation { analysis.remove(job.id) } })
            }

            ForEach(Meal.allCases) { meal in
                let items = entries.filter { $0.meal == meal }
                if !items.isEmpty {
                    HStack {
                        Text(meal.title)
                        Spacer()
                        Text("\(Format.kcal(Macros.total(items.map(\.macros)).kcal)) kcal")
                            .monospacedDigit()
                        Menu {
                            Button("Save as meal", systemImage: "bookmark") {
                                askToSave(items, meal: meal)
                            }
                            if !isToday {
                                Button("Log again today", systemImage: "arrow.clockwise") {
                                    for entry in items { LogActions.relog(entry, on: .now, in: context) }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 32, height: 24)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("\(meal.title) options")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    ForEach(items) { entry in
                        Button {
                            editor = .edit(entry)
                        } label: {
                            FoodCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editor = .edit(entry) }
                            Button(isToday ? "Log again" : "Log again today", systemImage: "arrow.clockwise") {
                                withAnimation { _ = LogActions.relog(entry, on: .now, in: context) }
                            }
                            Button("Save as meal", systemImage: "bookmark") {
                                askToSave([entry], meal: meal)
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation { context.delete(entry) }
                            }
                        }
                    }
                }
            }

            if entries.isEmpty && jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Nothing logged yet")
                        .font(.headline)
                    Text("Tap + to snap a photo of your meal, scan a barcode or describe what you ate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .card(padding: 28)
            }
        }
        .sensoryFeedback(.success, trigger: quickLogged)
        .alert("Save as meal", isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } })) {
            TextField("Name", text: $mealName)
            Button("Cancel", role: .cancel) { saving = nil }
            Button("Save") {
                if let saving {
                    let name = mealName.trimmingCharacters(in: .whitespaces)
                    LogActions.saveMeal(named: name.isEmpty ? saving.suggestedName : name, meal: saving.meal,
                                        entries: saving.entries, in: context)
                }
                saving = nil
            }
        } message: {
            Text("Log it again later with one tap from Home or Saved & recent.")
        }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private func askToSave(_ entries: [LogEntry], meal: Meal) {
        let pending = PendingSave(entries: entries, meal: meal)
        mealName = pending.suggestedName
        saving = pending
    }

    /// Marks this day by hand. Matching the weekly schedule again just removes the mark.
    private func setTraining(_ isTraining: Bool, schedule: WeekdaySet) {
        for mark in marks { context.delete(mark) }
        if isTraining != schedule.contains(day: day) {
            context.insert(TrainingDayMark(day: Calendar.current.startOfDay(for: day), isTraining: isTraining))
        }
    }
}

#Preview {
    TodayView()
        .environment(AnalysisCenter())
        .modelContainer(for: AppModels.all, inMemory: true)
}
