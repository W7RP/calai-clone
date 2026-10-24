import SwiftData
import SwiftUI

/// Every AI-proposed item is shown and editable here before anything is saved.
struct ReviewView: View {
    @Environment(\.modelContext) private var context

    let day: Date
    let note: String?
    let analysis: String?
    let warnings: [String]
    let photo: Data?
    let thumbnail: Data?
    let onSaved: () -> Void

    @State private var items: [ReviewItem]
    @State private var meal = Meal.suggested(for: .now)
    @State private var showingAnalysis = false

    init(estimate: FoodEstimate, day: Date, photo: Data? = nil, thumbnail: Data? = nil,
         onSaved: @escaping () -> Void) {
        self.day = day
        note = estimate.note
        analysis = estimate.analysis
        warnings = estimate.warnings
        self.photo = photo
        self.thumbnail = thumbnail
        self.onSaved = onSaved
        _items = State(initialValue: estimate.items.map(ReviewItem.init))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                        .accessibilityHidden(true)
                }

                summary

                notes

                Text("Items")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach($items) { $item in
                    ReviewItemCard(item: $item) {
                        withAnimation { items.removeAll { $0.id == item.id } }
                    }
                }
                if items.isEmpty {
                    Text("Nothing left to log.")
                        .foregroundStyle(.secondary)
                        .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom) {
            Button("Log meal", action: save)
                .buttonStyle(.primary)
                .disabled(items.isEmpty || !items.allSatisfy(\.isValid))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.page)
        }
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Chip(text: Date.now.formatted(date: .omitted, time: .shortened), symbol: "clock")
                Spacer()
                Menu {
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Chip(text: meal.title, symbol: "chevron.up.chevron.down")
                }
                .tint(.primary)
            }
            Text(title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(Theme.quiet, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Calories").font(.subheadline).foregroundStyle(.secondary)
                    Text(Format.kcal(total.kcal))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.quiet, lineWidth: 1.5))

            HStack(spacing: 10) {
                ForEach(MacroKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(kind.title, systemImage: kind.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Format.grams(kind.value(total)))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.quiet, lineWidth: 1.5))
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("These are estimates. Check the amounts before logging.", systemImage: "sparkles")
                .font(.footnote.weight(.medium))
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let analysis {
                DisclosureGroup("How this was estimated", isExpanded: $showingAnalysis) {
                    Text(analysis)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.footnote)
                .tint(.primary)
            }
        }
        .card()
    }

    private var title: String {
        let names = items.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = names.first else { return "Your meal" }
        return names.count == 1 ? first : "\(first) + \(names.count - 1) more"
    }

    private var total: Macros {
        Macros.total(items.compactMap(\.parsed).map(\.macros))
    }

    private func save() {
        let date = EntryFormView.combine(day: day, timeFrom: .now)
        for item in items {
            guard let parsed = item.parsed else { continue }
            var food: FoodItem?
            if let per100g = parsed.macros.per100g(fromGrams: parsed.grams) {
                food = FoodCache.upsert(in: context, name: parsed.name, per100g: per100g,
                                        servingGrams: parsed.grams, source: .ai)
            }
            context.insert(LogEntry(date: date, meal: meal, foodName: parsed.name, grams: parsed.grams,
                                    macros: parsed.macros, source: .ai, foodItem: food,
                                    aiConfidence: parsed.confidenceScore, thumbnail: thumbnail))
        }
        onSaved()
    }
}

/// One estimated item, every number editable in place.
private struct ReviewItemCard: View {
    @Binding var item: ReviewItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Food", text: $item.name, axis: .vertical)
                    .font(.headline)
                Button("Remove", systemImage: "trash", action: onRemove)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Chip(text: item.fromLabel ? "From label" : "Estimate",
                     symbol: item.fromLabel ? "text.viewfinder" : "sparkles")
                Chip(text: "\(item.confidence.rawValue.capitalized) confidence",
                     symbol: item.confidence == .low ? "exclamationmark.circle" : nil)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    BoxField(label: "Amount", unit: "g", symbol: "scalemass", text: $item.grams)
                        .onChange(of: item.grams) { old, new in item.rescale(fromGrams: old, toGrams: new) }
                    BoxField(label: "Calories", unit: "kcal", symbol: "flame.fill", text: $item.kcal)
                }
                GridRow {
                    HStack(spacing: 8) {
                        BoxField(label: "Protein", unit: "g", symbol: MacroKind.protein.symbol, text: $item.protein)
                        BoxField(label: "Carbs", unit: "g", symbol: MacroKind.carbs.symbol, text: $item.carbs)
                        BoxField(label: "Fat", unit: "g", symbol: MacroKind.fat.symbol, text: $item.fat)
                    }
                    .gridCellColumns(2)
                }
            }
        }
        .card()
    }
}

/// A labelled number in a rounded box, for editing inside cards.
struct BoxField: View {
    let label: String
    let unit: String
    var symbol: String?
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(label)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.headline)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quiet, in: .rect(cornerRadius: 12))
    }
}

/// Editable copy of one estimated item; fields are strings so partially typed numbers survive.
struct ReviewItem: Identifiable {
    let id = UUID()
    var name: String
    var grams: String
    var kcal: String
    var protein: String
    var carbs: String
    var fat: String
    let confidence: EstimatedItem.Confidence
    let fromLabel: Bool

    init(_ item: EstimatedItem) {
        name = item.name
        grams = NumberInput.format(item.grams)
        kcal = NumberInput.format(item.macros.kcal, maxFractionDigits: 0)
        protein = NumberInput.format(item.macros.protein)
        carbs = NumberInput.format(item.macros.carbs)
        fat = NumberInput.format(item.macros.fat)
        confidence = item.confidence
        fromLabel = item.fromLabel
    }

    var parsed: EstimatedItem? {
        guard let g = NumberInput.parse(grams), let k = NumberInput.parse(kcal),
              let p = NumberInput.parse(protein), let c = NumberInput.parse(carbs), let f = NumberInput.parse(fat),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return EstimatedItem(name: name.trimmingCharacters(in: .whitespaces), grams: g,
                             macros: Macros(kcal: k, protein: p, carbs: c, fat: f),
                             confidence: confidence, fromLabel: fromLabel)
    }

    var isValid: Bool { parsed != nil }

    /// Changing the amount scales the nutrition with it, which is almost always what's meant.
    mutating func rescale(fromGrams old: String, toGrams new: String) {
        guard let from = NumberInput.parse(old), let to = NumberInput.parse(new), from > 0, to > 0, from != to,
              let current = parsed else { return }
        let scaled = current.macros.scaled(by: to / from)
        kcal = NumberInput.format(scaled.kcal, maxFractionDigits: 0)
        protein = NumberInput.format(scaled.protein)
        carbs = NumberInput.format(scaled.carbs)
        fat = NumberInput.format(scaled.fat)
    }
}
