import Photos

// MARK: - 照片库服务协议 (Photo Library Service Protocol)
/// 抽象照片库操作接口，遵循依赖倒置原则 (DIP)。
/// ViewModel 依赖此协议而非具体实现，便于单元测试和未来替换底层实现。
@MainActor
protocol PhotoLibraryServiceProtocol: AnyObject {

    // MARK: 权限管理

    /// 请求照片库读写权限
    /// - Returns: 授权状态
    func requestAuthorization() async -> PHAuthorizationStatus

    /// 同步查询当前授权状态
    var authorizationStatus: PHAuthorizationStatus { get }

    // MARK: 资源获取

    /// 根据筛选条件异步获取照片资源
    /// - Parameter filter: 照片筛选条件
    /// - Returns: 匹配的照片资源数组
    func fetchAssets(filter: PhotoFilter) async -> [PHAsset]

    /// Restores assets referenced by the app's persisted pending-deletion queue.
    func fetchAssets(localIdentifiers: [String]) async -> [PHAsset]

    // MARK: 资源操作

    /// 删除指定照片资源（物理删除，不可恢复）
    /// - Parameter assets: 待删除的照片资源数组
    func deleteAssets(_ assets: [PHAsset]) async throws

    /// 将照片收藏状态设置为明确值，便于可靠撤回操作。
    func setFavorite(_ isFavorite: Bool, for asset: PHAsset) async throws

    // MARK: 变更监听

    /// 注册照片库变更监听器（可从任意线程调用）
    /// - Parameter observer: 遵循 PHPhotoLibraryChangeObserver 的监听者
    nonisolated func registerChangeObserver(_ observer: PHPhotoLibraryChangeObserver)

    /// 取消注册照片库变更监听器（可从任意线程调用）
    /// - Parameter observer: 已注册的监听者
    nonisolated func unregisterChangeObserver(_ observer: PHPhotoLibraryChangeObserver)
}
