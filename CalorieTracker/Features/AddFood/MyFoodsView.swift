import SwiftData
import SwiftUI

/// Saved meals and foods logged before, so repeats need no scan or typing.
struct MyFoodsView: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case meals = "Saved meals"
        case foods = "Recent foods"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.lastUsed, order: .reverse) private var foods: [FoodItem]
    @Query(sort: \SavedMeal.lastUsed, order: .reverse) private var meals: [SavedMeal]
    @State private var search = ""
    @State private var shelf: Shelf?
    @State private var logged = 0

    let day: Date

    var body: some View {
        let shown = shelf ?? (meals.isEmpty ? .foods : .meals)
        NavigationStack {
            List {
                switch shown {
                case .meals:
                    ForEach(filteredMeals) { saved in
                        NavigationLink {
                            SavedMealView(saved: saved, day: day) { dismiss() }
                        } label: {
                            SavedMealRow(saved: saved) {
                                LogActions.log(saved, on: day, in: context)
                                logged += 1
                                dismiss()
                            }
                        }
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { filteredMeals[$0] }
                        for saved in doomed { context.delete(saved) }
                    }
                case .foods:
                    ForEach(filteredFoods) { food in
                        NavigationLink {
                            FoodAmountView(choice: .cached(food), day: day) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name)
                                Text([food.brand, "\(NumberInput.format(food.kcalPer100g, maxFractionDigits: 0)) kcal / 100 g"]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        // Logged entries keep their own numbers, so removing a cached food changes no history.
                        let doomed = offsets.map { filteredFoods[$0] }
                        for food in doomed { context.delete(food) }
                    }
                }
            }
            .overlay {
                if shown == .meals && meals.isEmpty {
                    ContentUnavailableView("No saved meals", systemImage: "bookmark",
                                           description: Text("On Home, open a meal's ••• menu or long-press a food and choose Save as meal."))
                } else if shown == .foods && foods.isEmpty {
                    ContentUnavailableView("No foods yet", systemImage: "clock",
                                           description: Text("Foods you log show up here for quick re-adding."))
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Show", selection: Binding(get: { shown }, set: { shelf = $0 })) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            .searchable(text: $search)
            .themedList()
            .navigationTitle("My foods")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: logged)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var filteredFoods: [FoodItem] {
        guard !query.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedStandardContains(query) || ($0.brand?.localizedStandardContains(query) ?? false)
        }
    }

    private var filteredMeals: [SavedMeal] {
        guard !query.isEmpty else { return meals }
        return meals.filter {
            $0.name.localizedStandardContains(query) || $0.items.contains { $0.foodName.localizedStandardContains(query) }
        }
    }
}

/// A saved meal in a list, with a button that logs it straight away.
private struct SavedMealRow: View {
    let saved: SavedMeal
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.name)
                Text("\(saved.items.count) \(saved.items.count == 1 ? "item" : "items") · \(Format.kcal(saved.totals.kcal)) kcal · \(saved.meal.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Button(action: onLog) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .frame(width: 34, height: 34)
                    .background(Color.primary, in: .circle)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Log \(saved.name)")
        }
    }
}

/// One saved meal: its foods, a rename, and a log button with a meal picker.
struct SavedMealView: View {
    @Environment(\.modelContext) private var context
    @Bindable var saved: SavedMeal
    let day: Date
    let onLogged: () -> Void

    @State private var meal = Meal.snack
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $saved.name)
            }
            Section {
                ForEach(Array(saved.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.foodName)
                            Text("\(NumberInput.format(item.grams)) g · P \(Format.grams(item.protein)) · C \(Format.grams(item.carbs)) · F \(Format.grams(item.fat))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Format.kcal(item.kcal)) kcal")
                            .monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    var items = saved.items
                    items.remove(atOffsets: offsets)
                    saved.items = items
                }
            } header: {
                Text("Foods")
            } footer: {
                let totals = saved.totals
                Text("Total \(Format.kcal(totals.kcal)) kcal · P \(Format.grams(totals.protein)) · C \(Format.grams(totals.carbs)) · F \(Format.grams(totals.fat))")
                    .monospacedDigit()
            }
            Section {
                Picker("Log as", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                Button("Log meal") {
                    LogActions.log(saved, on: day, meal: meal, in: context)
                    onLogged()
                }
                .buttonStyle(.primary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(saved.items.isEmpty)
            }
        }
        .themedList()
        .navigationTitle(saved.name.isEmpty ? "Saved meal" : saved.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            meal = saved.meal
        }
    }
}
