import AVFoundation
import Photos
import UIKit

// MARK: - Asset Sharing

@MainActor
final class AssetSharingService {
    static let shared = AssetSharingService()

    private init() {}

    func activityItems(for asset: PHAsset) async -> [Any] {
        let filename = originalFilename(for: asset)
        if asset.mediaType == .video, let url = await videoURL(for: asset) {
            if let tempURL = copyToTemp(url: url, filename: filename) {
                return [tempURL]
            }
            return [url]
        }
        if let image = await fullResolutionImage(for: asset) {
            if let tempURL = saveToTemp(image: image, filename: filename, asset: asset) {
                return [tempURL]
            }
            return [image]
        }
        return []
    }

    // MARK: - Original Filename

    private func originalFilename(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first?.originalFilename ?? defaultFilename(for: asset)
    }

    private func defaultFilename(for asset: PHAsset) -> String {
        let ext = asset.mediaType == .video ? "mp4" : "jpg"
        if let date = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            return "Photo_\(formatter.string(from: date)).\(ext)"
        }
        return "Photo_\(asset.localIdentifier.prefix(8)).\(ext)"
    }

    // MARK: - Temp File Helpers

    private func saveToTemp(image: UIImage, filename: String, asset: PHAsset) -> URL? {
        guard let data = image.jpegData(compressionQuality: 1.0) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func copyToTemp(url: URL, filename: String) -> URL? {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Image & Video Requests

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
