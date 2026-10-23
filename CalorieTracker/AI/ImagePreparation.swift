import UIKit

enum ImagePreparation {
    /// Shrinks to at most `maxSide` on the long edge and re-encodes as JPEG. Phone photos are 3-5 MB;
    /// this keeps uploads around 150-300 KB, which is plenty for reading a plate or a label.
    static func jpegForUpload(_ data: Data, maxSide: CGFloat = 1_024, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
