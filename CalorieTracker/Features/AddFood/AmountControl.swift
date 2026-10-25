import SwiftUI

/// Amount entry: − and + steps around the number, a unit menu, and quick picks for the unit.
/// Works inside a Form row or a card, so every button keeps its own tap area.
struct AmountControl: View {
    @Binding var amount: AmountInput

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

            if let hint = amount.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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
