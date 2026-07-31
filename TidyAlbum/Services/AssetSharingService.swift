import AVFoundation
import Photos
import UIKit

// MARK: - Asset Sharing

@MainActor
final class AssetSharingService {
    static let shared = AssetSharingService()

    private init() {}

    func activityItems(for asset: PHAsset) async -> [Any] {
        if asset.mediaType == .video, let url = await videoURL(for: asset) {
            return [url]
        }
        if let image = await fullResolutionImage(for: asset) {
            return [image]
        }
        return []
    }

    private func fullResolutionImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let gate = SharingContinuationGate(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                if isInCloud && data == nil && error == nil { return }
                gate.resume(returning: data.flatMap(UIImage.init(data:)))
            }
            Task {
                try? await Task.sleep(for: .seconds(15))
                gate.resume(returning: nil)
            }
        }
    }

    private func videoURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let gate = SharingContinuationGate(continuation)
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                gate.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                gate.resume(returning: nil)
            }
        }
    }
}

// MARK: - Single Resume Continuation

private final class SharingContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
