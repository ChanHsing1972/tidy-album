import SwiftUI

/// TidyAlbum — 相册清理助手
@main
struct TidyAlbumApp: App {
    @AppStorage("app.hasLaunchedBefore") private var hasLaunchedBefore = false
    @StateObject private var settings = SettingsStore()
    @State private var showsWelcome = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showsWelcome) {
                    WelcomeView(settings: settings)
                        .presentationDetents([.large])
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
