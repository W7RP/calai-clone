import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// Full-screen camera with one shutter: photograph a meal or a label, or point it at a barcode.
struct FoodScannerView: View {
    enum Mode: CaseIterable, Identifiable {
        case food, barcode, label

        var id: Self { self }

        var title: String {
            switch self {
            case .food: "Scan food"
            case .barcode: "Barcode"
            case .label: "Food label"
            }
        }

        var symbol: String {
            switch self {
            case .food: "fork.knife"
            case .barcode: "barcode.viewfinder"
            case .label: "text.viewfinder"
            }
        }

        var hint: String {
            switch self {
            case .food: "Fit the whole plate in the frame"
            case .barcode: "Point at the barcode"
            case .label: "Fill the frame with the nutrition table"
            }
        }
    }

    enum Result {
        case photo(Data)
        case barcode(String)
    }

    /// Needs a device that supports VisionKit scanning and camera access not turned off.
    /// Camera access not asked for yet counts as available; starting the scanner asks.
    static var isAvailable: Bool {
        guard DataScannerViewController.isSupported else { return false }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status != .denied && status != .restricted
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var camera = ScannerCamera()
    @State private var photoItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var flashOn = false

    let onResult: (Result) -> Void

    init(startIn mode: Mode = .food, onResult: @escaping (Result) -> Void) {
        _mode = State(initialValue: mode)
        self.onResult = onResult
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveScanner(camera: camera) { code in
                guard mode == .barcode else { return false }
                finish(.barcode(code))
                return true
            }
            .ignoresSafeArea()

            ViewfinderFrame(mode: mode)
                .padding(.horizontal, 36)
                .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                Text(mode.hint)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: .capsule)
                    .padding(.bottom, 16)
                modePicker
                shutterRow
            }
            .foregroundStyle(.white)
        }
        .statusBarHidden()
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    finish(.photo(data))
                }
                photoItem = nil
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: .circle)
            Spacer()
            Button(flashOn ? "Torch off" : "Torch on", systemImage: flashOn ? "bolt.fill" : "bolt.slash") {
                flashOn.toggle()
                camera.setTorch(flashOn)
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.4), in: .circle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { option in
                Button {
                    withAnimation(.snappy) { mode = option }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbol).font(.title3)
                        Text(option.title).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(mode == option ? Color.black : Color.white)
                    .background(mode == option ? Color.white : Color.white.opacity(0.15), in: .rect(cornerRadius: 14))
                }
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle").font(.title3)
                    Text("Library").font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Color.white.opacity(0.15), in: .rect(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 16)
    }

    private var shutterRow: some View {
        Button(action: capture) {
            ZStack {
                Circle().fill(.white).frame(width: 66, height: 66)
                Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
                if isCapturing { ProgressView().tint(.black) }
            }
        }
        .accessibilityLabel("Take photo")
        .disabled(mode == .barcode || isCapturing)
        .opacity(mode == .barcode ? 0.35 : 1)
        .padding(.vertical, 20)
    }

    private func capture() {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            if let data = await camera.capturePhoto() {
                finish(.photo(data))
            }
        }
    }

    private func finish(_ result: Result) {
        camera.setTorch(false)
        onResult(result)
        dismiss()
    }
}

/// Lets SwiftUI ask the VisionKit scanner for a still photo.
@MainActor
final class ScannerCamera {
    fileprivate weak var scanner: DataScannerViewController?

    func capturePhoto() async -> Data? {
        guard let scanner, let image = try? await scanner.capturePhoto() else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch,
              (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

/// The VisionKit camera, always watching for barcodes. `onBarcode` returns true once it has used a code.
private struct LiveScanner: UIViewControllerRepresentable {
    let camera: ScannerCamera
    let onBarcode: (String) -> Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false)
        scanner.delegate = context.coordinator
        camera.scanner = scanner
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onBarcode = onBarcode
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onBarcode: (String) -> Bool
        private var used = false

        init(onBarcode: @escaping (String) -> Bool) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            // A code already in view when the user switches to Barcode only arrives as an update.
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            guard !used else { return }
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                   let code = BarcodeNormalizer.normalize(payload), onBarcode(code) {
                    used = true
                    return
                }
            }
        }
    }
}

/// Four corner brackets. Wide for barcodes, square for plates and labels.
private struct ViewfinderFrame: View {
    let mode: FoodScannerView.Mode

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = mode == .barcode ? width * 0.45 : width * 1.1
            CornerBrackets()
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: width, height: height)
                .position(x: width / 2, y: geometry.size.height * 0.44)
                .animation(.snappy, value: mode)
        }
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.16
        var path = Path()
        // Top left, top right, bottom right, bottom left.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}
