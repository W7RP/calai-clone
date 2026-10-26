import SwiftUI

/// Amount entry: − and + steps around the number, a unit menu, and quick picks for the unit.
/// Works inside a Form row or a card, so every button keeps its own tap area.
struct AmountControl: View {
    @Binding var amount: AmountInput
    /// Where the cup weight came from ("from the label"), shown under it.
    var densityNote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                stepButton(-1, symbol: "minus")
                TextField("0", text: $amount.text)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                    .background(Theme.quiet, in: .rect(cornerRadius: 12))
                    .accessibilityLabel("Amount in \(amount.unit.label(for: 2))")
                Menu {
                    Picker("Unit", selection: Binding(get: { amount.unit }, set: { amount.convert(to: $0) })) {
                        ForEach(amount.measure.units) { unit in
                            Text(menuTitle(unit)).tag(unit)
                        }
                    }
                } label: {
                    Chip(text: amount.unit.label(for: amount.quantity ?? 0), symbol: "chevron.up.chevron.down")
                }
                .tint(.primary)
                .accessibilityLabel("Unit, \(amount.unit.label(for: 2))")
                stepButton(1, symbol: "plus")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(amount.unit.presets, id: \.self) { value in
                        Button {
                            amount.set(value)
                        } label: {
                            Chip(text: "\(AmountText.quantity(value)) \(amount.unit.label(for: value))",
                                 filled: amount.quantity == value)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()

            measures
        }
    }

    /// What one serving or one cup weighs, editable, since labels and databases are often off or silent.
    @ViewBuilder
    private var measures: some View {
        if amount.unit == .servings, let serving = amount.measure.servingGrams {
            MeasureField(title: "1 serving is", value: serving) { amount.setServingGrams($0) }
                .id("serving")
            hint
        } else if amount.unit.isVolume, let each = amount.measure.grams(per: amount.unit) {
            MeasureField(title: "1 \(amount.unit.rawValue) weighs", value: each) { amount.setGramsPerUnit($0) }
                .id(amount.unit)
            if let densityNote, !amount.assumesWater {
                Text("Weight \(densityNote).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if amount.assumesWater {
                Label("Guessed as water. Check the label: a cup of cereal or flour weighs far less.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                hint
                Spacer()
                if (amount.grams ?? 0) > 0 {
                    Button("Make \(amount.summary) 1 serving") { amount.makeOneServing() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .tint(.primary)
                }
            }
        } else {
            hint
        }
    }

    @ViewBuilder
    private var hint: some View {
        if let hint = amount.hint {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func stepButton(_ direction: Int, symbol: String) -> some View {
        Button {
            amount.step(direction)
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Theme.quiet, in: .circle)
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .disabled(direction < 0 && (amount.quantity ?? 0) <= 0)
        .accessibilityLabel(direction > 0 ? "More" : "Less")
    }

    /// "cup (250 g)", "serving (175 g)"; grams and millilitres need no explanation.
    private func menuTitle(_ unit: AmountUnit) -> String {
        guard unit != .grams, unit != .milliliters, let grams = amount.measure.grams(per: unit) else {
            return unit.rawValue
        }
        return "\(unit.rawValue) (\(NumberInput.format(grams, maxFractionDigits: 0)) g)"
    }
}

/// "1 cup weighs [29] g". Applies each valid number as it's typed; the amount scales from per-gram values,
/// so half-typed numbers on the way don't leave anything off.
private struct MeasureField: View {
    let title: String
    let onChange: (Double) -> Void
    @State private var text: String

    init(title: String, value: Double, onChange: @escaping (Double) -> Void) {
        self.title = title
        self.onChange = onChange
        _text = State(initialValue: NumberInput.format(value))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.quiet, in: .rect(cornerRadius: 8))
            Text("g")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .monospacedDigit()
        .onChange(of: text) { _, new in
            if let value = NumberInput.parse(new), value > 0 { onChange(value) }
        }
    }
}
