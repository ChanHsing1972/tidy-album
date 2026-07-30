# TidyAlbum

TidyAlbum 是一款基于 SwiftUI、PhotoKit 和 Swift Charts 的本地相册清理工具。所有照片、视频和元数据处理均在设备上完成。

## MVVM 目录结构

```text
TidyAlbum/
├── App/                         App 入口
├── Core/Theme/                  设计令牌与动画参数
├── Core/Localization/           应用内中英文文案
├── Models/                      设置、筛选、统计与元数据模型
├── Services/                    PhotoKit、图片缓存、元数据服务
├── ViewModels/                  PhotoManager 会话状态与操作历史
└── Views/
    ├── ContentView.swift        原生 TabView 根导航
    ├── Home/                    清理首页与筛选入口
    ├── Cleaning/                手势浏览卡片与操作反馈
    ├── Trash/                   待删除队列与系统确认
    ├── Details/                 EXIF、文件信息与位置地图
    ├── Analytics/               Swift Charts 成就看板
    ├── Settings/                原生 Form 设置页
    └── Components/              共享媒体展示组件
```

应用需要 iOS 18.6 或更高版本，工程会通过 Xcode 的文件系统同步组自动收录新增 Swift 文件。
