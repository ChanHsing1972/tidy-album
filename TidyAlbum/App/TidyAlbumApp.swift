import SwiftUI

/// TidyAlbum — 相册清理助手
///
/// 通过类 Tinder 卡片交互帮助用户快速筛选、删除和收藏照片，
/// 支持按截屏、自拍、收藏等分类进行批量清理。
@main
struct TidyAlbumApp: App {
    @AppStorage("app.hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var showsWelcome = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showsWelcome) {
                    WelcomeView()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                        .interactiveDismissDisabled()
                }
                .onAppear {
                    if !hasLaunchedBefore {
                        hasLaunchedBefore = true
                        showsWelcome = true
                    }
                }
        }
    }
}