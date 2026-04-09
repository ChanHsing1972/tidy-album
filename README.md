# TidyAlbum

TidyAlbum 是一款运行在 iOS 上的相册清理工具，使用 SwiftUI 构建，旨在帮助用户快速清理照片，保持相册整洁。用户只需左滑、右滑、上滑照片，即可轻松实现删除、保留或喜爱操作，界面优雅、响应迅速。

## 要求

- Xcode 13 或更高
- iOS 15 或更高（或与目标 Xcode 版本兼容的 iOS 版本）
- Swift 5

## 项目结构

- `TidyAlbum/` — 应用主代码
	- `ContentView.swift` — 主界面
	- `PhotoManager.swift` — 照片访问与处理逻辑
	- `PhotoView.swift` — 照片预览组件
	- `TidyAlbumApp.swift` — App 入口
