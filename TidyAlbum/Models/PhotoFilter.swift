import SwiftUI

// MARK: - 照片筛选条件模型
/// 定义相册清理支持的筛选模式。
/// 每个 case 关联对应的 SF Symbol 图标和本地化标题。
enum PhotoFilter: String, CaseIterable, Identifiable {
    /// 全部照片与视频
    case all = "全部照片"
    /// 截屏
    case screenshots = "截屏"
    /// 自拍
    case selfies = "自拍"
    /// 个人收藏
    case favorites = "个人收藏"

    // MARK: Identifiable

    var id: String { rawValue }

    // MARK: - 图标

    /// 筛选条件对应的 SF Symbol 图标名称
    var icon: String {
        switch self {
        case .all:         "photo.on.rectangle.angled"
        case .screenshots: "camera.viewfinder"
        case .selfies:     "person.crop.square"
        case .favorites:   "heart.fill"
        }
    }
}