import SwiftUI

enum AddAction: Equatable {
    case scanFood, barcode, describe, myFoods, manual
    /// Yesterday's food for one meal, or the whole day when nil.
    case copy(Meal?)
}

/// The sheet behind the + button: one big tile per way of logging.
struct AddMenuView: View {
    let onSelect: (AddAction) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log food")
                .font(.title3.bold())
                .padding(.top, 24)
            LazyVGrid(columns: columns, spacing: 12) {
                Tile(title: "Scan food", symbol: "camera.viewfinder") { onSelect(.scanFood) }
                Tile(title: "Describe a meal", symbol: "text.bubble") { onSelect(.describe) }
                Tile(title: "Barcode", symbol: "barcode.viewfinder") { onSelect(.barcode) }
                Tile(title: "Saved & recent", symbol: "bookmark") { onSelect(.myFoods) }
                Tile(title: "Enter manually", symbol: "square.and.pencil") { onSelect(.manual) }
                Menu {
                    Button("Whole day") { onSelect(.copy(nil)) }
                    Divider()
                    ForEach(Meal.allCases) { meal in
                        Button(meal.title) { onSelect(.copy(meal)) }
                    }
                } label: {
                    TileLabel(title: "Copy yesterday", symbol: "doc.on.doc")
                }
                .tint(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .pageBackground()
    }
}

private struct Tile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TileLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

private struct TileLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .card(padding: 14)
    }
}
