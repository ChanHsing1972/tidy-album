import AVFoundation
import ImageIO
import Photos

// MARK: - Metadata Service

@MainActor
final class AssetMetadataService {
    static let shared = AssetMetadataService()

    private var cache: [String: AssetMetadata] = [:]

    private init() {}

    func load(for asset: PHAsset) async -> AssetMetadata {
        if let cached = cache[asset.localIdentifier] { return cached }
        let metadata: AssetMetadata
        if asset.mediaType == .video {
            metadata = await loadVideoMetadata(for: asset)
        } else {
            metadata = await loadImageMetadata(for: asset)
        }
        cache[asset.localIdentifier] = metadata
        return metadata
    }

    private func loadImageMetadata(for asset: PHAsset) async -> AssetMetadata {
        let payload: (Data?, String?) = await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded && data != nil { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                if isInCloud && data == nil && error == nil { return }
                gate.resume(returning: (data, uti))
            }
            Task {
                try? await Task.sleep(for: .seconds(8))
                gate.resume(returning: (nil, nil))
            }
        }

        var model: String?
        var lens: String?
        var aperture: Double?
        var exposure: Double?
        var iso: Int?
        var focalLength: Double?

        if let data = payload.0,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            model = tiff?[kCGImagePropertyTIFFModel] as? String
            lens = exif?[kCGImagePropertyExifLensModel] as? String
            aperture = exif?[kCGImagePropertyExifFNumber] as? Double
            exposure = exif?[kCGImagePropertyExifExposureTime] as? Double
            focalLength = exif?[kCGImagePropertyExifFocalLength] as? Double
            if let values = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int] {
                iso = values.first
            }
        }

        let fileName = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "IMG_\(asset.localIdentifier.prefix(6))"
        let fileSize = Int64(payload.0?.count ?? 0)

        return AssetMetadata(
            fileName: fileName,
            fileSize: fileSize > 0 ? fileSize : estimatedFileSize(for: asset),
            uniformType: payload.1 ?? "public.jpeg",
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            deviceModel: model,
            lensModel: lens,
            aperture: aperture,
            exposureTime: exposure,
            iso: iso,
            focalLength: focalLength,
            location: asset.location
        )
    }

    private func loadVideoMetadata(for asset: PHAsset) async -> AssetMetadata {
        let (avAsset, fileSize): (AVAsset?, Int64) = await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation)
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                var size: Int64 = 0
                if let urlAsset = avAsset as? AVURLAsset {
                    size = Int64((try? urlAsset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                gate.resume(returning: (avAsset, size))
            }
            Task {
                try? await Task.sleep(for: .seconds(10))
                gate.resume(returning: (nil, 0))
            }
        }

        var type = "public.movie"
        if let urlAsset = avAsset as? AVURLAsset {
            type = urlAsset.url.pathExtension.uppercased()
        }

        return AssetMetadata(
            fileName: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "VID_\(asset.localIdentifier.prefix(6))",
            fileSize: fileSize > 0 ? fileSize : estimatedFileSize(for: asset),
            uniformType: type,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            deviceModel: nil,
            lensModel: nil,
            aperture: nil,
            exposureTime: nil,
            iso: nil,
            focalLength: nil,
            location: asset.location
        )
    }

    private func estimatedFileSize(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return max(Int64(asset.duration * 500_000), 1_000_000)
        }
        let pixels = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
        return max(Int64(Double(pixels) * 0.32), 200_000)
    }
}

// MARK: - Single Resume Continuation

private final class ContinuationGate<Value>: @unchecked Sendable {
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
