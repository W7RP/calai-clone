import SwiftData
import SwiftUI

struct TodayView: View {
    @State private var day = Date.now
    @State private var editor: EntryEditor?
    @State private var showingSettings = false
    @State private var showingScanner = false
    @State private var showingRecents = false
    @State private var barcodeNotFound: String?
    @State private var aiSheet: AISheet?

    var body: some View {
        NavigationStack {
            DayLog(day: day, editor: $editor)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Previous day", systemImage: "chevron.left") { shift(by: -1) }
                        Spacer()
                        if !Calendar.current.isDateInToday(day) {
                            Button("Today") { day = .now }
                            Spacer()
                        }
                        Button("Next day", systemImage: "chevron.right") { shift(by: 1) }
                            .disabled(Calendar.current.isDateInToday(day))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Add food", systemImage: "plus") {
                            Button("Photo", systemImage: "camera") { aiSheet = .photo }
                            Button("Describe it", systemImage: "text.bubble") { aiSheet = .text }
                            Divider()
                            Button("Scan barcode", systemImage: "barcode.viewfinder") { showingScanner = true }
                            Button("Recent foods", systemImage: "clock") { showingRecents = true }
                            Button("Enter manually", systemImage: "square.and.pencil") { editor = .new(day: day) }
                        }
                    }
                }
                .sheet(item: $editor) { editor in
                    EntryFormView(editor: editor)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showingScanner, onDismiss: {
                    // Open manual entry only after the scanner sheet is gone; two sheets can't overlap.
                    if let code = barcodeNotFound {
                        barcodeNotFound = nil
                        editor = .new(day: day, barcode: code)
                    }
                }) {
                    ScanFlowView(day: day) { barcodeNotFound = $0 }
                }
                .sheet(isPresented: $showingRecents) {
                    RecentFoodsView(day: day)
                }
                .sheet(item: $aiSheet) { kind in
                    AIAddView(day: day, startWithCamera: kind == .photo)
                }
        }
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func shift(by days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
    }
}

enum AISheet: String, Identifiable {
    case photo, text
    var id: String { rawValue }
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

/// The list for one day. Separate from TodayView so its @Query can be rebuilt when the day changes.
private struct DayLog: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LogEntry]
    @Query(sort: \DailyGoal.effectiveFrom, order: .reverse) private var goals: [DailyGoal]
    @Binding var editor: EntryEditor?
    let day: Date

    init(day: Date, editor: Binding<EntryEditor?>) {
        self.day = day
        _editor = editor
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(filter: #Predicate<LogEntry> { $0.date >= start && $0.date < end }, sort: \.date)
    }

    var body: some View {
        let totals = Macros.total(entries.map(\.macros))
        let goal = GoalSelection.active(goals, on: day, effectiveFrom: \.effectiveFrom)

        List {
            Section {
                DaySummary(totals: totals, goal: goal?.macros)
            }

            ForEach(Meal.allCases) { meal in
                let items = entries.filter { $0.meal == meal }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { entry in
                            Button {
                                editor = .edit(entry)
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .tint(.primary)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(items[index]) }
                        }
                    } header: {
                        HStack {
                            Text(meal.title)
                            Spacer()
                            Text("\(NumberInput.format(Macros.total(items.map(\.macros)).kcal, maxFractionDigits: 0)) kcal")
                        }
                    }
                }
            }

            if entries.isEmpty {
                ContentUnavailableView("Nothing logged", systemImage: "fork.knife",
                                       description: Text("Tap + to add what you ate."))
                    .listRowBackground(Color.clear)
            }
        }
    }
}

private struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                Text("\(NumberInput.format(entry.grams, maxFractionDigits: 0)) g · P \(NumberInput.format(entry.protein)) · C \(NumberInput.format(entry.carbs)) · F \(NumberInput.format(entry.fat))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(NumberInput.format(entry.kcal, maxFractionDigits: 0)) kcal")
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DaySummary: View {
    let totals: Macros
    let goal: Macros?

    var body: some View {
        VStack(spacing: 12) {
            if let goal, goal.kcal > 0 {
                let remaining = goal.kcal - totals.kcal
                Gauge(value: min(totals.kcal, goal.kcal), in: 0...goal.kcal) {
                    Text("Calories")
                } currentValueLabel: {
                    Text(NumberInput.format(totals.kcal, maxFractionDigits: 0))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .scaleEffect(1.6)
                .padding(.vertical, 16)
                .tint(remaining < 0 ? .red : .green)
                Text(remaining >= 0
                     ? "\(NumberInput.format(remaining, maxFractionDigits: 0)) kcal left of \(NumberInput.format(goal.kcal, maxFractionDigits: 0))"
                     : "\(NumberInput.format(-remaining, maxFractionDigits: 0)) kcal over \(NumberInput.format(goal.kcal, maxFractionDigits: 0))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(NumberInput.format(totals.kcal, maxFractionDigits: 0)) kcal")
                    .font(.largeTitle.bold())
                Text("Set a daily goal in Settings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                MacroColumn(name: "Protein", value: totals.protein, goal: goal?.protein)
                MacroColumn(name: "Carbs", value: totals.carbs, goal: goal?.carbs)
                MacroColumn(name: "Fat", value: totals.fat, goal: goal?.fat)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct MacroColumn: View {
    let name: String
    let value: Double
    let goal: Double?

    var body: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(NumberInput.format(value, maxFractionDigits: 0)) g")
                .font(.headline)
                .monospacedDigit()
            if let goal, goal > 0 {
                ProgressView(value: min(value, goal), total: goal)
                Text("of \(NumberInput.format(goal, maxFractionDigits: 0)) g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [FoodItem.self, LogEntry.self, DailyGoal.self], inMemory: true)
}
