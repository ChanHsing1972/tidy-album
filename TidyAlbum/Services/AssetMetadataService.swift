import AVFoundation
import ImageIO
import Photos

// MARK: - Metadata Service

@MainActor
final class AssetMetadataService {
    func load(for asset: PHAsset) async -> AssetMetadata {
        if asset.mediaType == .video {
            return await loadVideoMetadata(for: asset)
        }
        return await loadImageMetadata(for: asset)
    }

    private func loadImageMetadata(for asset: PHAsset) async -> AssetMetadata {
        let payload: (Data?, String?) = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            let requestID = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded && data != nil { return }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                // If in cloud and data is nil, wait for the download to complete
                if isInCloud && data == nil { return }
                resumed = true
                continuation.resume(returning: (data, uti))
            }

            // Timeout: if the callback hasn't fired after 8 seconds, resume with nil
            // This handles iCloud photos that can't be downloaded (e.g. no network)
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !resumed else { return }
                resumed = true
                PHImageManager.default().cancelImageRequest(requestID)
                continuation.resume(returning: (nil, nil))
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
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            var resumed = false
            let requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                resumed = true

                var size: Int64 = 0
                if let urlAsset = avAsset as? AVURLAsset {
                    size = Int64((try? urlAsset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                continuation.resume(returning: (avAsset, size))
            }

            // Timeout after 10 seconds for video
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !resumed else { return }
                resumed = true
                PHImageManager.default().cancelImageRequest(requestID)
                continuation.resume(returning: (nil, 0))
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