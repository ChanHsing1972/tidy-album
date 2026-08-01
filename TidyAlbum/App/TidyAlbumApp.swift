import SwiftUI
import Inject

/// TidyAlbum — 相册清理助手
@main
struct TidyAlbumApp: App {
    @ObserveInjection var inject
    var body: some Scene {
        WindowGroup {
            ContentView()
                .enableInjection()
        }
    }
}
