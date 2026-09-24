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
    private var requests: [UUID: PHImageRequestID] = [:]
    private var preheatedAssets: [String: PHAsset] = [:]
    private var preheatTargetSize = CGSize.zero

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 192 * 1_024 * 1_024
    }

    func cachedImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit
    ) -> UIImage? {
        cache.object(forKey: cacheKey(asset: asset, targetSize: targetSize, contentMode: contentMode))
    }

    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .opportunistic,
        completion: @escaping (_ image: UIImage, _ isFinal: Bool) -> Void
    ) -> PHImageRequestID? {
        let key = cacheKey(asset: asset, targetSize: targetSize, contentMode: contentMode)
        if let image = cache.object(forKey: key) {
            completion(image, true)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let token = UUID()
        let requestID = manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, info in
            Task { @MainActor in
                guard let self, self.requests[token] != nil else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isFinal = !isDegraded
                if isFinal { self.requests[token] = nil }
                guard let image, !(info?[PHImageCancelledKey] as? Bool ?? false) else { return }
                if isFinal {
                    let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                    self.cache.setObject(image, forKey: key, cost: cost)
                }
                completion(image, isFinal)
            }
        }
        requests[token] = requestID
        return requestID
    }

    func cancel(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        requests = requests.filter { $0.value != requestID }
        manager.cancelImageRequest(requestID)
    }

    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        if preheatTargetSize != targetSize {
            manager.stopCachingImagesForAllAssets()
            preheatedAssets.removeAll()
            preheatTargetSize = targetSize
        }
        let requested = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let additions = requested.filter { preheatedAssets[$0.key] == nil }.map(\.value)
        let removals = preheatedAssets.filter { requested[$0.key] == nil }.map(\.value)
        if !removals.isEmpty {
            manager.stopCachingImages(
                for: removals,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            )
        }
        if !additions.isEmpty {
            manager.startCachingImages(
                for: additions,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            )
        }
        preheatedAssets = requested
    }

    func stopCaching() {
        manager.stopCachingImagesForAllAssets()
        preheatedAssets.removeAll()
        preheatTargetSize = .zero
    }

    /// Discard decoded images and prevent late PhotoKit callbacks from repopulating them.
    func invalidate() {
        let pending = Array(requests.values)
        requests.removeAll()
        pending.forEach { manager.cancelImageRequest($0) }
        cache.removeAllObjects()
        stopCaching()
    }

    private func cacheKey(
        asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode
    ) -> NSString {
        let widthBucket = Int(targetSize.width.rounded(.up) / 100) * 100
        let heightBucket = Int(targetSize.height.rounded(.up) / 100) * 100
        let mode = contentMode == .aspectFill ? "fill" : "fit"
        return "\(asset.localIdentifier)-\(widthBucket)x\(heightBucket)-\(mode)" as NSString
    }
}
