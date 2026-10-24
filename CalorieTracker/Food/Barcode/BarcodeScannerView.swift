import SwiftUI
import VisionKit

/// Live camera scanner for retail barcodes. Reports the first code it sees, once.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var reported = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !reported else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                   let code = BarcodeNormalizer.normalize(payload) {
                    reported = true
                    dataScanner.stopScanning()
                    onScan(code)
                    return
                }
            }
        }
    }
}

enum BarcodeNormalizer {
    /// Digits only, 8-14 long. UPC-A scans arrive as 12 digits; OFF stores them as EAN-13 with a leading 0.
    static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        return digits.count == 12 ? "0" + digits : digits
    }
}
