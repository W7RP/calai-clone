import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CalorieTracker

struct ImagePreparationTests {
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func info(_ data: Data) throws -> (type: String, width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (CGImageSourceGetType(source) as String? ?? "",
                properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
                properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func largePhotoIsDownscaledToJPEG() throws {
        let output = try #require(ImagePreparation.jpegForUpload(try png(width: 4_032, height: 3_024)))
        let result = try info(output)
        #expect(result.type == UTType.jpeg.identifier)
        #expect(max(result.width, result.height) == ImagePreparation.defaultMaxSide)
        #expect(abs(Double(result.width) / Double(result.height) - 4.0 / 3.0) < 0.01)
    }

    @Test func smallImageIsNotUpscaled() throws {
        let output = try #require(ImagePreparation.jpegForUpload(try png(width: 640, height: 480)))
        let result = try info(output)
        #expect(result.width == 640)
        #expect(result.height == 480)
    }

    @Test func garbageIsRejected() {
        #expect(ImagePreparation.jpegForUpload(Data("not an image".utf8)) == nil)
    }
}
