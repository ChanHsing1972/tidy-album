import SwiftUI
import Inject

// MARK: - Settings

struct SettingsView: View {
    @ObserveInjection var inject
    @ObservedObject var settings: SettingsStore
    @ObservedObject var manager: PhotoManager

    @State private var showsClearViewedConfirmation = false

    var body: some View {
        let _ = inject
        NavigationStack {
            Form {
                Section(settings.t("General")) {
                    Picker(selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    } label: {
                        Label(settings.t("Language"), systemImage: "globe")
                    }
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label(settings.t("Haptic Feedback"), systemImage: "iphone.radiowaves.left.and.right")
                    }
                    Picker(selection: $settings.themeMode) {
                        Text(settings.t("Follow System")).tag(ThemeMode.system)
                        Text(settings.t("Light")).tag(ThemeMode.light)
                        Text(settings.t("Dark")).tag(ThemeMode.dark)
                    } label: {
                        Label(settings.t("Theme"), systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    Picker(selection: $settings.sortOrder) {
                        Text(settings.t("Newest First")).tag(PhotoSortOrder.newestFirst)
                        Text(settings.t("Random")).tag(PhotoSortOrder.random)
                    } label: {
                        Label(settings.t("Photo Order"), systemImage: "arrow.up.arrow.down")
                    }
                    if settings.sortOrder == .random {
                        Toggle(isOn: $settings.excludesViewedInRandomMode) {
                            Label(settings.t("Filter Viewed Items"), systemImage: "eye.slash")
                        }
                        if settings.excludesViewedInRandomMode {
                            LabeledContent(
                                settings.t("Viewed Items"),
                                value: manager.viewedAssetCount.formatted()
                            )
                            Button(settings.t("Clear Viewed History"), role: .destructive) {
                                showsClearViewedConfirmation = true
                            }
                            .disabled(manager.viewedAssetCount == 0)
                        }
                    }
                    Picker(selection: $settings.assetInfoDisplayMode) {
                        Text(settings.t("Location")).tag(AssetInfoDisplayMode.location)
                        Text(settings.t("File Size")).tag(AssetInfoDisplayMode.fileSize)
                        Text(settings.t("Captured")).tag(AssetInfoDisplayMode.fullDate)
                        Text(settings.t("Dimensions")).tag(AssetInfoDisplayMode.resolution)
                    } label: {
                        Label(settings.t("Info Display"), systemImage: "info.circle")
                    }
                    Picker(selection: $settings.progressDisplayMode) {
                        Text(settings.t("Numbers Only")).tag(ProgressDisplayMode.textOnly)
                        Text(settings.t("Bar Only")).tag(ProgressDisplayMode.barOnly)
                        Text(settings.t("Show Both")).tag(ProgressDisplayMode.both)
                    } label: {
                        Label(settings.t("Progress Display"), systemImage: "chart.bar")
                    }
                    Picker(selection: $settings.cleaningGroupSize) {
                        ForEach(CleaningGroupSize.allCases) { size in
                            Text("\(size.rawValue) \(settings.t("Items"))").tag(size)
                        }
                    } label: {
                        Label(settings.t("Group Size"), systemImage: "square.grid.3x3")
                    }
                } header: {
                    Text(settings.t("Cleaning Preferences"))
                } 

                Section(settings.t("About & Support")) {
                    LabeledContent(settings.t("Version"), value: appVersion)
                    LabeledContent(settings.t("Developer"), value: "TidyAlbum")
                    VStack(alignment: .leading, spacing: 8) {
                        Label(settings.t("Privacy"), systemImage: "lock.shield")
                        Text(settings.t("Privacy Detail"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(settings.t("Settings"))
            .confirmationDialog(
                settings.t("Clear Viewed History?"),
                isPresented: $showsClearViewedConfirmation,
                titleVisibility: .visible
            ) {
                Button(settings.t("Clear Viewed History"), role: .destructive) {
                    manager.clearViewedHistory()
                }
                Button(settings.t("Cancel"), role: .cancel) {}
            } message: {
                Text(settings.t("Previously reviewed items will appear in random sessions again."))
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
