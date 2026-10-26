import SwiftData
import SwiftUI

/// Scan -> local cache -> Open Food Facts -> amount. A miss hands the barcode back for manual entry.
struct ScanFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let day: Date
    /// A code the full-screen scanner already read, so this skips straight to the lookup.
    let initialCode: String?
    let onNotFound: (String) -> Void

    private enum Stage {
        case scanning
        case looking(String)
        case found(FoodAmountView.Choice)
        case failed(String, barcode: String)
    }

    @State private var stage: Stage
    @State private var typedCode = ""

    init(day: Date, initialCode: String? = nil, onNotFound: @escaping (String) -> Void) {
        self.day = day
        self.initialCode = initialCode
        self.onNotFound = onNotFound
        _stage = State(initialValue: initialCode.map { Stage.looking($0) } ?? .scanning)
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .task {
                    if let initialCode, case .looking = stage { await lookUp(initialCode) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .scanning:
            scanner
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
        case .looking(let code):
            ProgressView("Looking up \(code)…")
        case .found(let choice):
            FoodAmountView(choice: choice, day: day) { dismiss() }
        case .failed(let message, let code):
            ContentUnavailableView {
                Label("Lookup failed", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await lookUp(code) } }
                Button("Enter manually") { notFound(code) }
            }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        VStack(spacing: 0) {
            if BarcodeScannerView.isAvailable {
                BarcodeScannerView { code in Task { await lookUp(code) } }
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("Camera scanning isn't available", systemImage: "barcode.viewfinder",
                                       description: Text("Type the number under the barcode instead."))
            }
            HStack {
                TextField("Or type the barcode", text: $typedCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Look up") {
                    if let code = BarcodeNormalizer.normalize(typedCode) { Task { await lookUp(code) } }
                }
                .disabled(BarcodeNormalizer.normalize(typedCode) == nil)
            }
            .padding()
            .background(.bar)
        }
    }

    private func lookUp(_ code: String) async {
        stage = .looking(code)
        if let cached = cachedFood(barcode: code) {
            // Products saved by an older version are read again once, so their units are the barcode's own.
            if cached.source == .off, (cached.lookupVersion ?? 0) < FoodItem.currentLookupVersion,
               let draft = try? await OpenFoodFactsClient().product(barcode: code) {
                cached.servingText = draft.servingText
                cached.measure = draft.measure
                cached.lookupVersion = FoodItem.currentLookupVersion
            }
            stage = .found(.cached(cached))
            return
        }
        do {
            if let draft = try await OpenFoodFactsClient().product(barcode: code) {
                stage = .found(.draft(draft))
            } else {
                notFound(code)
            }
        } catch {
            stage = .failed(error.localizedDescription, barcode: code)
        }
    }

    private func cachedFood(barcode: String) -> FoodItem? {
        var descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == barcode },
                                                   sortBy: [SortDescriptor(\.lastUsed, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func notFound(_ code: String) {
        onNotFound(code)
        dismiss()
    }
}
