import Photos
import ImageIO
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

    static func normalizedData(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            normalize(data)
        }.value
    }

    private static func normalize(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
                ] as CFDictionary
              ) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
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
