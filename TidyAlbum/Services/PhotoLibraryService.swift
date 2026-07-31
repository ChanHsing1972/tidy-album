import Photos

// MARK: - 照片库服务实现 (Photo Library Service)
/// `PhotoLibraryServiceProtocol` 的具体实现，封装所有 Photos 框架调用。
/// 负责权限管理、资源获取、删除和收藏操作。
final class PhotoLibraryService: PhotoLibraryServiceProtocol {

    // MARK: - 权限管理 (Authorization)

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: - 资源获取 (Fetching)

    func fetchAssets(filter: PhotoFilter) async -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let result: PHFetchResult<PHAsset>

        switch filter {
        case .all:
            let predicate = NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            options.predicate = predicate
            result = PHAsset.fetchAssets(with: options)

        case .screenshots:
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumScreenshots,
                options: nil
            )
            if let collection = collections.firstObject {
                result = PHAsset.fetchAssets(in: collection, options: options)
            } else {
                result = PHAsset.fetchAssets(with: .image, options: options)
            }

        case .videos, .largeVideos:
            result = PHAsset.fetchAssets(with: .video, options: options)

        case .livePhotos:
            result = PHAsset.fetchAssets(with: .image, options: options)

        case .selfies:
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumSelfPortraits,
                options: nil
            )
            if let collection = collections.firstObject {
                result = PHAsset.fetchAssets(in: collection, options: options)
            } else {
                result = PHAsset.fetchAssets(with: .image, options: options)
            }

        case .favorites:
            let predicate = NSPredicate(
                format: "favorite == YES AND (mediaType == %d OR mediaType == %d)",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            options.predicate = predicate
            result = PHAsset.fetchAssets(with: options)
        }

        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        switch filter {
        case .largeVideos:
            return assets.filter {
                $0.duration >= 60 || ($0.pixelWidth >= 3_840 && $0.pixelHeight >= 2_160)
            }
        case .livePhotos:
            return assets.filter { $0.mediaSubtypes.contains(.photoLive) }
        default:
            return assets
        }
    }

    func fetchAssets(localIdentifiers: [String]) async -> [PHAsset] {
        guard !localIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // MARK: - 资源操作 (Asset Operations)

    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    func setFavorite(_ isFavorite: Bool, for asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = isFavorite
        }
    }

    // MARK: - 变更监听 (Change Observation)

    nonisolated func registerChangeObserver(_ observer: PHPhotoLibraryChangeObserver) {
        PHPhotoLibrary.shared().register(observer)
    }

    nonisolated func unregisterChangeObserver(_ observer: PHPhotoLibraryChangeObserver) {
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
    }
}
