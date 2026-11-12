import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Upstream's `QRCode` with `UIImage` in place of `NSImage`.
enum QRCode {
    /// A crisp QR code for `text`, rendered at `size` points without smoothing.
    static func image(for text: String, size: CGFloat = 240, correction: String = "M") -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction
        guard let output = filter.outputImage else { return nil }
        // Scale the tiny module grid up with nearest-neighbour so squares stay sharp.
        let pixels = size * 3
        let scale = pixels / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 3, orientation: .up)
    }

    /// Decodes the first QR code found in `image`, for tests and round-trip checks.
    static func decode(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: CIImage(cgImage: cgImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
