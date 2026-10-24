import SwiftData
import SwiftUI

/// Foods logged before, newest first, so repeats need no scan or typing.
struct RecentFoodsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.lastUsed, order: .reverse) private var foods: [FoodItem]
    @State private var search = ""

    let day: Date

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { food in
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
                    for index in offsets { context.delete(filtered[index]) }
                }
            }
            .overlay {
                if foods.isEmpty {
                    ContentUnavailableView("No foods yet", systemImage: "clock",
                                           description: Text("Foods you log show up here for quick re-adding."))
                }
            }
            .searchable(text: $search)
            .themedList()
            .navigationTitle("Recent foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filtered: [FoodItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedStandardContains(query) || ($0.brand?.localizedStandardContains(query) ?? false)
        }
    }
}
