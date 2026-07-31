import Foundation

// MARK: - In-App Localization

enum AppStrings {
    static func text(_ key: String, language: AppLanguage) -> String {
        guard language == .simplifiedChinese else { return key }
        return chinese[key] ?? key
    }

    private static let chinese: [String: String] = [
        "Clean": "清理", "Analytics": "统计", "Settings": "设置", "TidyAlbum": "TidyAlbum",
        "Make room for what matters.": "为真正重要的回忆腾出空间。", "Photos and videos": "照片与视频",
        "Pending deletion": "待删除", "Start Cleaning": "开始清理", "Choose a collection": "选择清理范围",
        "All Photos": "全部照片", "Screenshots": "截屏", "Selfies": "自拍", "Favorites": "个人收藏",
        "No items in this collection": "此分类中暂无项目", "Review another collection": "查看其他分类",
        "Review complete": "浏览完成", "You reviewed every item in this session.": "你已浏览完本次会话的全部项目。",
        "Done": "完成", "Close": "关闭", "Trash": "待删除", "Restore": "恢复", "Restore All": "全部恢复",
        "Delete All": "全部删除", "Delete from Photos?": "从系统照片中删除？",
        "These items will move to Recently Deleted in Photos.": "这些项目将移入系统“照片”的最近删除，可在系统保留期内恢复。",
        "Cancel": "取消", "Delete": "删除", "Photo Details": "照片详情", "Media Details": "媒体详情",
        "File": "文件", "File Size": "文件大小", "Format": "格式", "Dimensions": "分辨率",
        "Captured": "拍摄时间", "Camera": "相机", "Device": "设备", "Lens": "镜头", "Aperture": "光圈",
        "Exposure": "曝光", "ISO": "ISO", "Focal Length": "焦距", "Location": "拍摄地点",
        "No location data": "无位置数据", "Loading details…": "正在读取详情…", "Video": "视频", "Photo": "照片",
        "Space Reclaimed": "累计释放空间", "Items Cleaned": "累计清理", "Items Reviewed": "累计浏览",
        "Cleanup Overview": "清理概览", "Space by Media": "释放空间分布", "Photos": "照片", "Videos": "视频",
        "Cleaning Wins": "清理战果", "Screenshots Cleaned": "已清理截屏", "Large Videos": "大型视频",
        "Other Items": "其他项目", "Most Productive Time": "最高效时段", "No cleanup history yet": "暂无清理记录",
        "Start a cleaning session to see your progress here.": "完成一次清理后，这里会展示你的成果。",
        "General": "通用", "Language": "语言", "Haptic Feedback": "触觉反馈", "Cleaning Preferences": "清理偏好",
        "Delete Behavior": "删除方式", "App Trash First": "先放入 App 待删除", "Move to System Trash": "直接移入系统废纸篓",
        "Photo Order": "照片顺序", "Newest First": "按日期倒序", "Random": "随机抽取", "About & Support": "关于与支持",
        "Version": "版本", "Developer": "开发者", "Privacy": "隐私", "Processed entirely on device": "完全在设备本地处理",
        "Privacy Detail": "TidyAlbum 使用 PhotoKit 在本地读取与处理照片。照片、视频及其元数据不会上传到任何服务器。",
        "Direct deletion asks Photos for confirmation and cannot be undone inside TidyAlbum.": "直接删除会请求系统“照片”确认，且无法在 TidyAlbum 内撤回。",
        "Swipe left or right to browse. Swipe up to delete, down to favorite.": "左右滑动浏览，上滑删除，下滑收藏。",
        "Undo": "撤回", "Details": "详情", "Favorite": "收藏", "Remove Favorite": "取消收藏",
        "Delete Failed": "删除失败", "Try again from the pending deletion queue.": "请在待删除队列中重试。",
        "Limited Library": "有限照片访问", "Manage Access": "管理访问", "Photo Access Required": "需要照片访问权限",
        "TidyAlbum needs access to help you review and clean your library.": "TidyAlbum 需要访问照片，才能帮助你浏览和整理图库。",
        "Open Settings": "打开设置", "Items": "项", "Today": "今天", "This Week": "本周",
        "All processing stays on this iPhone or iPad.": "所有处理均保留在这台 iPhone 或 iPad 上。",
        "Session Complete": "清理完成", "You've cleaned up your album!": "你已整理过相册！",
        "Deleted": "已删除", "In Trash": "待删除", "Back to Home": "返回首页",
        "Progress Display": "进度展示", "Numbers Only": "仅数字", "Progress Bar Only": "仅进度条",
        "Show Both": "均展示"
    ]
}

extension SettingsStore {
    func t(_ key: String) -> String {
        AppStrings.text(key, language: language)
    }
}
