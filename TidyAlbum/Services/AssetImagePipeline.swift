import Photos
import UIKit

// MARK: - Shared Image Pipeline

/// A single PhotoKit caching manager serves cards, backgrounds and grids. Keeping
/// decoded images here prevents a newly promoted card from briefly returning to a placeholder.
@MainActor
final class AssetImagePipeline {
    static let shared = AssetImagePipeline()

    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 80
    }

    func cachedImage(for asset: PHAsset, targetSize: CGSize) -> UIImage? {
        cache.object(forKey: cacheKey(asset: asset, targetSize: targetSize))
    }

    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        completion: @escaping (UIImage) -> Void
    ) -> PHImageRequestID? {
        let key = cacheKey(asset: asset, targetSize: targetSize)
        if let image = cache.object(forKey: key) {
            completion(image)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, info in
            guard let image else { return }
            Task { @MainActor in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    self?.cache.setObject(image, forKey: key)
                }
                completion(image)
            }
        }
    }

    func cancel(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        manager.cancelImageRequest(requestID)
    }

    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        manager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        )
    }

    func stopCaching() {
        manager.stopCachingImagesForAllAssets()
    }

    private func cacheKey(asset: PHAsset, targetSize: CGSize) -> NSString {
        let widthBucket = Int(targetSize.width.rounded(.up) / 100) * 100
        let heightBucket = Int(targetSize.height.rounded(.up) / 100) * 100
        return "\(asset.localIdentifier)-\(widthBucket)x\(heightBucket)" as NSString
    }
}
