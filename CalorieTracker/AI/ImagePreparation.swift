import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImagePreparation {
    /// 1568 px on the long edge is where Claude stops downscaling, and is enough for OpenAI's and Gemini's
    /// high-detail tiles; small print on nutrition labels stays legible. Typically 250-450 KB.
    static let defaultMaxSide = 1_568

    /// Downscales any photo (HEIC, JPEG, PNG) and re-encodes as JPEG. Decodes straight to the target size,
    /// so a 48 MP photo never sits in memory at full resolution. Orientation is applied, and metadata,
    /// including GPS location, is dropped.
    static func jpegForUpload(_ data: Data, maxSide: Int = defaultMaxSide, quality: Double = 0.75) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        // Never upscale a small image.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? maxSide
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? maxSide
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxSide, max(width, height)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
