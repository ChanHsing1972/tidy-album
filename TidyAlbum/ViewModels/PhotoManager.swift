import SwiftUI
import Photos
import Combine

// MARK: - 照片管理器 (ViewModel)
/// 作为 MVVM 架构中的 ViewModel 层，负责管理照片清理流程的 UI 状态。
///
/// ## 职责
/// - 持有并暴露 UI 绑定的状态数据
/// - 协调 `PhotoLibraryServiceProtocol` 处理照片库操作
/// - 管理垃圾桶 (Trash Bin) 和会话统计等业务逻辑
///
/// ## 依赖
/// - `PhotoLibraryServiceProtocol`：通过依赖注入提供，遵循依赖倒置原则 (DIP)
@MainActor
final class PhotoManager: NSObject, ObservableObject {

    // MARK: - 依赖 (Dependencies)

    /// 照片库服务，遵循 DIP 通过协议注入
    private let photoService: PhotoLibraryServiceProtocol

    // MARK: - 发布状态 (Published State)

    /// 当前筛选条件下的照片资源列表
    @Published var assets: [PHAsset] = []

    /// 垃圾桶中的照片资源（待删除）
    @Published var trashBin: [PHAsset] = []

    /// 是否已获得照片库授权
    @Published var isAuthorized = false

    /// 当前激活的筛选条件
    @Published var currentFilter: PhotoFilter = .all

    /// 是否正在加载照片数据
    @Published var isLoading = false

    /// 本次会话中已删除的照片数量
    @Published var sessionDeletedCount = 0

    // MARK: - 初始化 (Initialization)

    /// 创建照片管理器实例
    /// - Parameter photoService: 照片库服务实例
    init(photoService: PhotoLibraryServiceProtocol) {
        self.photoService = photoService
        super.init()
        photoService.registerChangeObserver(self)
        checkPermission()
    }

    deinit {
        photoService.unregisterChangeObserver(self)
    }

    // MARK: - 权限管理 (Permission)

    /// 检查并请求照片库访问权限
    func checkPermission() {
        let status = photoService.authorizationStatus
        switch status {
        case .authorized, .limited:
            isAuthorized = true
            fetchPhotos()
        case .notDetermined:
            Task {
                let newStatus = await photoService.requestAuthorization()
                if newStatus == .authorized || newStatus == .limited {
                    isAuthorized = true
                    fetchPhotos()
                }
            }
        default:
            isAuthorized = false
        }
    }

    // MARK: - 筛选与获取 (Filter & Fetch)

    /// 切换筛选条件并重新加载照片
    /// - Parameter filter: 目标筛选条件
    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        fetchPhotos()
    }

    /// 根据当前筛选条件异步获取照片
    func fetchPhotos() {
        isLoading = true

        Task {
            let fetchedAssets = await photoService.fetchAssets(filter: currentFilter)

            // 过滤掉已在垃圾桶中的照片
            let trashIdentifiers = Set(trashBin.map(\.localIdentifier))
            let filteredAssets = fetchedAssets.filter { asset in
                !trashIdentifiers.contains(asset.localIdentifier)
            }

            assets = filteredAssets
            isLoading = false
        }
    }

    // MARK: - 垃圾桶管理 (Trash Bin)

    /// 将照片移入垃圾桶
    /// - Parameter asset: 待删除的照片资源
    func addToTrash(asset: PHAsset) {
        guard !trashBin.contains(where: { $0.localIdentifier == asset.localIdentifier }) else {
            return
        }
        trashBin.append(asset)
        sessionDeletedCount += 1
        objectWillChange.send()
    }

    /// 从垃圾桶中恢复单张照片
    /// - Parameter asset: 待恢复的照片资源
    func restoreFromTrash(asset: PHAsset) {
        guard let index = trashBin.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else {
            return
        }
        trashBin.remove(at: index)
        sessionDeletedCount = max(0, sessionDeletedCount - 1)
        fetchPhotos()
    }

    /// 一键恢复垃圾桶中的所有照片
    func restoreAllFromTrash() {
        trashBin.removeAll()
        sessionDeletedCount = 0
        fetchPhotos()
    }

    /// 清空垃圾桶，物理删除照片库中的资源
    func emptyTrash() {
        guard !trashBin.isEmpty else { return }

        let assetsToDelete = trashBin
        Task {
            do {
                try await photoService.deleteAssets(assetsToDelete)
                trashBin.removeAll()
                fetchPhotos()
            } catch {
                print("[PhotoManager] 删除照片失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 收藏管理 (Favorite)

    /// 切换照片的收藏状态（乐观更新 UI）
    /// - Parameter asset: 目标照片资源
    func toggleFavorite(asset: PHAsset) {
        objectWillChange.send()
        photoService.toggleFavorite(for: asset)
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.fetchPhotos()
        }
    }
}