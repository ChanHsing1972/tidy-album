import SwiftUI
import Photos
import Combine

enum PhotoFilter: String, CaseIterable, Identifiable {
    case all = "All Photos"
    case screenshots = "Screenshots"
    case selfies = "Selfies"
    case favorites = "Favorites"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .screenshots: return "camera.viewfinder"
        case .selfies: return "person.crop.square"
        case .favorites: return "heart.fill"
        }
    }
}

@MainActor
class PhotoManager: NSObject, ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var trashBin: [PHAsset] = []
    @Published var isAuthorized = false
    @Published var currentFilter: PhotoFilter = .all
    @Published var isLoading = false
    
    // 统计数据
    @Published var sessionDeletedCount = 0
    
    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        checkPermission()
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            isAuthorized = true
            fetchPhotos()
        case .notDetermined:
            Task {
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    if status == .authorized || status == .limited {
                        self.isAuthorized = true
                        self.fetchPhotos()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }
    
    func setFilter(_ filter: PhotoFilter) {
        self.currentFilter = filter
        fetchPhotos()
    }
    
    func fetchPhotos() {
        isLoading = true
        
        Task {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let result: PHFetchResult<PHAsset>
            
            switch currentFilter {
            case .all:
                // Fetch images and videos
                let predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                options.predicate = predicate
                result = PHAsset.fetchAssets(with: options)
            case .screenshots:
                let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
                if let collection = collections.firstObject {
                    result = PHAsset.fetchAssets(in: collection, options: options)
                } else {
                    result = PHAsset.fetchAssets(with: .image, options: options) // Fallback
                }
            case .selfies:
                let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
                if let collection = collections.firstObject {
                    result = PHAsset.fetchAssets(in: collection, options: options)
                } else {
                    result = PHAsset.fetchAssets(with: .image, options: options)
                }
            case .favorites:
                // Favorites (Images + Videos)
                let predicate = NSPredicate(format: "favorite == YES AND (mediaType == %d OR mediaType == %d)", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                options.predicate = predicate
                result = PHAsset.fetchAssets(with: options)
            }
            
            var newAssets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                newAssets.append(asset)
            }
            
            // 过滤掉已经在垃圾桶里的照片
            let trashIds = Set(trashBin.map { $0.localIdentifier })
            let filteredAssets = newAssets.filter { !trashIds.contains($0.localIdentifier) }
            
            await MainActor.run {
                self.assets = filteredAssets
                self.isLoading = false
            }
        }
    }
    
    func addToTrash(asset: PHAsset) {
        if !trashBin.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
            trashBin.append(asset)
            sessionDeletedCount += 1
            // 确保 UI 立即更新，虽然 CleaningView 使用 currentIndex，但如果用户返回 Home 再进来，应该过滤掉
            // 这里不需要手动从 assets 移除，因为 fetchPhotos 会过滤
            // 但为了保险起见，我们可以触发一次 objectWillChange
            objectWillChange.send()
        }
    }
    
    func restoreFromTrash(asset: PHAsset) {
        if let index = trashBin.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            trashBin.remove(at: index)
            sessionDeletedCount -= 1
            // 恢复后，如果当前过滤器包含该照片，它应该重新出现在 assets 中
            // 为了简单起见，我们重新 fetch，或者手动插入回 assets
            // 重新 fetch 最安全
            fetchPhotos()
        }
    }
    
    func restoreAllFromTrash() {
        trashBin.removeAll()
        sessionDeletedCount = 0
        fetchPhotos()
    }
    
    func emptyTrash() {
        guard !trashBin.isEmpty else { return }
        
        let assetsToDelete = trashBin
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        } completionHandler: { success, error in
            Task { @MainActor in
                if success {
                    print("Deleted successfully")
                    self.trashBin.removeAll()
                    self.fetchPhotos()
                } else if let error = error {
                    print("Error deleting: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func toggleFavorite(asset: PHAsset) {
        // 乐观更新 UI
        objectWillChange.send()
        
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = !asset.isFavorite
        } completionHandler: { success, error in
            if !success {
                print("Error toggling favorite: \(String(describing: error))")
            }
        }
    }
}

extension PhotoManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.fetchPhotos()
        }
    }
}
