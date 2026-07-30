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
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                continuation.resume(returning: (data, uti))
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

        return AssetMetadata(
            fileName: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "—",
            fileSize: Int64(payload.0?.count ?? 0),
            uniformType: payload.1 ?? "—",
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
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }

        var size: Int64 = 0
        var type = "public.movie"
        if let urlAsset = avAsset as? AVURLAsset {
            size = Int64((try? urlAsset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            type = urlAsset.url.pathExtension.uppercased()
        }

        return AssetMetadata(
            fileName: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "—",
            fileSize: size,
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
}
