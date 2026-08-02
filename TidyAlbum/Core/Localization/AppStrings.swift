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
        "Library Overview": "图库概览", "Selected Collection": "当前分类", "Collections": "分类",
        "Loading Photos": "正在载入照片", "Review Pending Items": "查看待删除项目",
        "All Photos": "全部", "All": "全部", "Photos": "照片", "Screenshots": "截屏", "Selfies": "自拍", "Favorites": "个人收藏",
        "Live Photos": "实况照片", "Some photos are not available to TidyAlbum.": "部分照片尚未授权给 TidyAlbum。",
        "No items in this collection": "此分类中暂无项目", "Review another collection": "查看其他分类",
        "Review complete": "浏览完成", "You reviewed every item in this session.": "你已浏览完本次会话的全部项目。",
        "Done": "完成", "Close": "关闭", "Trash": "待删除", "Restore": "恢复", "Restore All": "全部恢复",
        "Trash is Empty": "待删除队列为空", "Items marked for deletion appear here.": "标记删除的项目会显示在这里。",
        "View Details": "查看详情", "About": "约",
        "Delete All": "全部删除", "Delete from Photos?": "从系统照片中删除？",
        "These items will move to Recently Deleted in Photos.": "这些项目将移入系统“照片”的最近删除，可在系统保留期内恢复。",
        "Cancel": "取消", "Delete": "删除", "Photo Details": "照片详情", "Media Details": "媒体详情",
        "File": "文件", "File Size": "文件大小", "Format": "格式", "Dimensions": "分辨率",
        "Captured": "拍摄时间", "Camera": "相机", "Device": "设备", "Lens": "镜头", "Aperture": "光圈",
        "Exposure": "曝光", "ISO": "ISO", "Focal Length": "焦距", "Location": "拍摄地点",
        "No location data": "无位置数据", "Loading details…": "正在读取详情…", "Video": "视频", "Photo": "照片",
        "Duration": "时长", "Unknown File": "未知文件", "Unknown Date": "未知日期", "Share": "分享",
        "Space Reclaimed": "累计释放空间", "Items Cleaned": "累计清理", "Items Reviewed": "累计浏览",
        "Cleanup Overview": "清理概览", "Space by Media": "释放空间分布", "Videos": "视频", "Date": "日期",
        "Cleaning Wins": "清理战果", "Screenshots Cleaned": "已清理截屏", "Large Videos": "大型视频",
        "Other Items": "其他项目", "Most Productive Time": "最高效时段", "No cleanup history yet": "暂无清理记录",
        "Last 7 Days": "近七日", "Total": "总计",
        "More": "更多", "Reset Statistics": "重置统计", "Reset Cleanup History?": "重置清理记录？",
        "This removes cleanup statistics from this device.": "这会从当前设备移除全部清理统计。",
        "Start a cleaning session to see your progress here.": "完成一次清理后，这里会展示你的成果。",
        "General": "通用", "Language": "语言", "Haptic Feedback": "触觉反馈", "Cleaning Preferences": "清理偏好",
        "Delete Behavior": "删除方式", "App Trash First": "先放入 App 待删除", "Move to System Trash": "直接移入系统废纸篓",
        "Photo Order": "照片顺序", "Newest First": "按日期倒序", "Random": "随机抽取", "About & Support": "关于",
        "Filter Viewed Items": "过滤已查看项目", "Viewed Items": "已查看项目", "Clear Viewed History": "清空已查看记录",
        "Clear Viewed History?": "清空已查看记录？", "Previously reviewed items will appear in random sessions again.": "此前看过的项目将重新出现在随机清理中。",
        "inin previous random sessions.": "随机清理时不再显示此前已经查看过的项目。", "All Items Reviewed": "已查看全部项目",
        "Quick Clean All Photos": "快速清理全部照片",
        "Group Size": "每组数量", "Only one group is loaded at a time to keep browsing smooth.": "每次只载入一组，确保大型图库的浏览依然流畅。",
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
        "Cleanup Summary": "清理总结", "Space Selected": "已选空间", "Reviewed This Session": "本次浏览",
        "Marked for Deletion": "标记待删除", "Back to Library": "关闭", "This Session": "本次清理",
        "Ready for review in Pending Deletion": "所选项目已进入待删除，可在删除前再次确认", "Next Step": "下一步",
        "No items added to Pending Deletion": "本次没有新增待删除项目",
        "Items ready in Pending Deletion": "%d 项已进入待删除，可在删除前再次确认",
        "Open Pending Deletion": "打开待删除列表",
        "Progress Display": "进度展示", "Numbers Only": "仅数字", "Bar Only": "仅进度条",
        "Show Both": "均展示", "Info Display": "浮岛信息", "Group": "组",
        "Clean Next Group": "清理下一组", "View Summary": "查看清理总结", "Continue Reviewing": "继续查看本组",
        "Group Finished": "本组已完成", "All Done": "全部完成", "Continue with the next group?": "是否继续清理下一组？",
        "Finish Session": "结束清理", "Next Group": "下一组", "Finish": "完成",
        "Group Complete": "本组完成", "All items in this group reviewed": "已浏览完本组全部项目",
        "Group X of Y": "第 %d 组 / 共 %d 组",
        "Theme": "主题", "Follow System": "跟随系统", "Light": "浅色", "Dark": "深色",
        "Unable to Share": "无法分享", "The original item could not be prepared. Please check iCloud connectivity and try again.": "无法读取原始项目，请检查 iCloud 网络状态后重试。", "No device information": "无设备信息", "No camera information": "无镜头信息", "Shutter": "快门",
        "Swipe to Review": "滑动整理", "Swipe up to delete, down to favorite. Left and right to browse.": "上滑快速删除，下滑添加收藏，左右滑动即可轻松浏览所有照片。",
        "Private & Local": "绝对私密", "Everything stays on your device. No data is ever uploaded.": "所有数据仅保留在本地设备，绝不会上传至任何服务器。",
        "Track Progress": "记录清理成果", "See how much space you've reclaimed over time.": "随时直观查看累计清理数，以及成功释放的存储空间。", "Continue": "继续", "Welcome to\nTidyAlbum": "欢迎使用\nTidyAlbum"
    ]
}

extension SettingsStore {
    func t(_ key: String) -> String {
        AppStrings.text(key, language: language)
    }

    func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMMdEEEEjm")
        return formatter.string(from: date)
    }
}
