import Photos
import UIKit

enum RelatedScreenshotImageError: LocalizedError {
    case invalidImage
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取这张图片。"
        case .photoLibraryDenied:
            return "没有获得保存到设备相册的权限。"
        }
    }
}

enum RelatedScreenshotImage {
    private static let maxDimension: CGFloat = 1600

    static func normalizedData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(longestSide, 1))
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).jpegData(
            withCompressionQuality: 0.86
        ) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func image(from data: Data) -> UIImage? {
        UIImage(data: data)
    }

    static func saveToPhotos(data: Data) async throws {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized || status == .limited else {
            throw RelatedScreenshotImageError.photoLibraryDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}
