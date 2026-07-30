import SwiftUI

// MARK: - 根内容视图 (Root Content View)
/// 应用的根视图，负责管理页面导航状态和全局布局。
///
/// ## 导航状态
/// - `home`：首页，展示统计与筛选
/// - `cleaning`：清理界面，类 Tinder 卡片交互
/// - `summary`：清理完成后的摘要页面
///
/// ## 职责
/// - 持有 `PhotoManager` 作为全局状态源
/// - 管理页面间转场动画
/// - 处理授权状态的 UI 分支
struct ContentView: View {

    // MARK: 状态

    /// 全局照片管理器
    @StateObject private var manager = PhotoManager(photoService: PhotoLibraryService())

    /// 当前应用页面状态
    @State private var appState: AppState = .home

    /// 是否展示垃圾桶 Sheet
    @State private var showTrash = false

    // MARK: - Body

    var body: some View {
        ZStack {
            DesignTokens.Colors.appBackground.ignoresSafeArea()

            if manager.isAuthorized {
                currentPage
            } else {
                PermissionView()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTrash) {
            TrashView(manager: manager)
        }
    }

    // MARK: - 当前页面 (Current Page)

    @ViewBuilder
    private var currentPage: some View {
        switch appState {
        case .home:
            HomeView(
                manager: manager,
                onStart: {
                    manager.fetchPhotos()
                    withAnimation(AnimationPresets.pageTransition) {
                        appState = .cleaning
                    }
                },
                onShowTrash: { showTrash = true }
            )
            .transition(AnimationPresets.appearTransition)

        case .cleaning:
            CleaningView(
                manager: manager,
                onFinish: {
                    withAnimation(AnimationPresets.pageTransition) {
                        appState = .summary
                    }
                },
                onBack: {
                    withAnimation(AnimationPresets.pageTransition) {
                        appState = .home
                    }
                },
                onShowTrash: { showTrash = true }
            )
            .transition(AnimationPresets.slideFromTrailing)

        case .summary:
            SummaryView(
                manager: manager,
                onHome: {
                    withAnimation(AnimationPresets.pageTransition) {
                        appState = .home
                    }
                }
            )
            .transition(AnimationPresets.slideFromBottom)
        }
    }
}

// MARK: - 应用页面状态 (App State)

extension ContentView {
    /// 定义应用的三个主要页面状态
    enum AppState {
        /// 首页
        case home
        /// 清理中
        case cleaning
        /// 清理摘要
        case summary
    }
}