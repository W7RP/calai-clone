import SwiftUI
import UIKit

/// The black-and-white look: soft grey page, white cards, black ink. Dark mode flips it.
enum Theme {
    static let page = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : UIColor(white: 0.965, alpha: 1) })
    static let card = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : .white })
    /// Ring tracks, chip fills and other quiet surfaces.
    static let quiet = Color.primary.opacity(0.07)
    static let cardRadius: CGFloat = 22
}

extension View {
    /// A white rounded card with a faint shadow, the building block of every screen.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }

    /// The grey page behind the cards.
    func pageBackground() -> some View {
        background(Theme.page.ignoresSafeArea())
    }

    /// Forms and lists on the same grey page, with white rows.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.page.ignoresSafeArea())
    }
}

/// Full-width black capsule, used for the one main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color(UIColor.systemBackground))
            .background(Color.primary.opacity(isEnabled ? 1 : 0.25), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Outlined capsule for the secondary action next to a primary one.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.primary)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Progress ring with an icon in the middle. Over 100% the ring stays full and turns dashed.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: Center

    var body: some View {
        let over = progress > 1
        ZStack {
            Circle().stroke(Theme.quiet, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.primary,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: over ? .butt : .round,
                                           dash: over ? [3, 3] : []))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            center
        }
    }
}

/// The three macros, each with its own symbol so they're told apart without colour.
enum MacroKind: CaseIterable, Identifiable {
    case protein, carbs, fat

    var id: Self { self }

    var title: String {
        switch self {
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }

    var symbol: String {
        switch self {
        case .protein: "fish.fill"
        case .carbs: "carrot.fill"
        case .fat: "drop.fill"
        }
    }

    func value(_ macros: Macros) -> Double {
        switch self {
        case .protein: macros.protein
        case .carbs: macros.carbs
        case .fat: macros.fat
        }
    }
}

/// Small grey pill, for times, labels and toggles.
struct Chip: View {
    let text: String
    var symbol: String?
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(filled ? Color(UIColor.systemBackground) : .primary)
        .background(filled ? Color.primary : Theme.quiet, in: .capsule)
    }
}

enum Format {
    static func kcal(_ value: Double) -> String { NumberInput.format(value, maxFractionDigits: 0) }
    static func grams(_ value: Double) -> String { "\(NumberInput.format(value, maxFractionDigits: 0))g" }
}
