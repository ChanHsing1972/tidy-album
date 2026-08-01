import SwiftUI

// MARK: - Root Tab Architecture

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app.hasLaunchedBefore") private var hasLaunchedBefore = false
    @StateObject private var settings: SettingsStore
    @StateObject private var analytics: AnalyticsStore
    @StateObject private var manager: PhotoManager
    @State private var showsWelcome = false

    init() {
        // 🧪 调试专用：取消下面这行的注释，每次启动都强行清除“已看过”标记
        UserDefaults.standard.removeObject(forKey: "app.hasLaunchedBefore")
        let settings = SettingsStore()
        let analytics = AnalyticsStore()
        _settings = StateObject(wrappedValue: settings)
        _analytics = StateObject(wrappedValue: analytics)
        _manager = StateObject(
            wrappedValue: PhotoManager(
                photoService: PhotoLibraryService(),
                settings: settings,
                analytics: analytics
            )
        )
    }

    var body: some View {
        TabView {
            CleanHomeView(manager: manager, settings: settings)
                .tabItem {
                    Label(settings.t("Clean"), systemImage: "sparkles")
                }

            AnalyticsView(store: analytics, settings: settings, manager: manager)
                .tabItem {
                    Label(settings.t("Analytics"), systemImage: "chart.bar.xaxis")
                }

            SettingsView(settings: settings, manager: manager)
                .tabItem {
                    Label(settings.t("Settings"), systemImage: "gearshape")
                }
        }
        .tint(.blue)
        .environment(\.locale, settings.language.locale)
        .preferredColorScheme(settings.themeMode.colorScheme)
        .sheet(isPresented: $showsWelcome) {
            WelcomeView(settings: settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
                .interactiveDismissDisabled()
        }
        .onAppear {
            guard !hasLaunchedBefore else { return }
            hasLaunchedBefore = true
            showsWelcome = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.checkPermission() }
        }
    }
}


//#Preview("完整 App 预览") {
//    ContentView()}
