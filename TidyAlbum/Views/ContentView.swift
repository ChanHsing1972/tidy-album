import SwiftUI

// MARK: - Root Tab Architecture

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings: SettingsStore
    @StateObject private var analytics: AnalyticsStore
    @StateObject private var manager: PhotoManager

    init() {
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

            SettingsView(settings: settings)
                .tabItem {
                    Label(settings.t("Settings"), systemImage: "gearshape")
                }
        }
        .tint(.blue)
        .preferredColorScheme(settings.themeMode.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.checkPermission() }
        }
    }
}


//#Preview("完整 App 预览") {
//    ContentView()}
