import PhotosUI
import SwiftUI
import VisionKit

/// Scans a QR code with the camera (VisionKit), or reads one from a photo, and hands the text
/// to `onCode`. What the text may be (an address, a `tezos:` URI, a dApp pairing link) is the
/// caller's business; nothing here acts on it.
struct QRScannerView: View {
    let title: String
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var message: String?

    private var cameraAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        VStack(spacing: 16) {
            if cameraAvailable {
                CameraScanner { code in finish(code) }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.3)))
            } else {
                ContentUnavailableView("Camera unavailable", systemImage: "camera",
                                       description: Text(DataScannerViewController.isSupported
                                                         ? "Allow Signet Go to use the camera in Settings, or choose a photo of the QR code."
                                                         : "This device cannot scan with the camera. Choose a photo of the QR code instead."))
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Choose a photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                message = nil
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                      let code = QRCode.decode(image) else {
                    message = "No QR code found in that photo."
                    return
                }
                finish(code)
            }
        }
    }

    private func finish(_ code: String) {
        onCode(code.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// VisionKit's live scanner, reporting the first QR code it recognises.
private struct CameraScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue, !text.isEmpty {
                    done = true
                    scanner.stopScanning()
                    onCode(text)
                    return
                }
            }
        }
    }
}

/// What a scanned code means for an address field: a bare address or name, or the address of a
/// `tezos:` payment URI (TZIP-style `tezos:<address>[?…]`); anything else is returned as is.
enum ScannedRecipient {
    static func text(from code: String) -> String {
        var text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("tezos:") {
            text = String(text.dropFirst("tezos:".count))
            if text.hasPrefix("//") { text = String(text.dropFirst(2)) }
            if let end = text.firstIndex(where: { $0 == "?" || $0 == "/" || $0 == "@" }) { text = String(text[..<end]) }
        }
        return text
    }
}
