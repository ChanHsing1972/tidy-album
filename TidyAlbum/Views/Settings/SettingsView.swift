import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
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
                    Picker(selection: $settings.deletionMode) {
                        Text(settings.t("App Trash First")).tag(DeletionMode.appTrash)
                        Text(settings.t("Move to System Trash")).tag(DeletionMode.systemTrash)
                    } label: {
                        Label(settings.t("Delete Behavior"), systemImage: "trash")
                    }
                    Picker(selection: $settings.sortOrder) {
                        Text(settings.t("Newest First")).tag(PhotoSortOrder.newestFirst)
                        Text(settings.t("Random")).tag(PhotoSortOrder.random)
                    } label: {
                        Label(settings.t("Photo Order"), systemImage: "arrow.up.arrow.down")
                    }
                    Picker(selection: $settings.progressDisplayMode) {
                        Text(settings.t("Numbers Only")).tag(ProgressDisplayMode.textOnly)
                        Text(settings.t("Progress Bar Only")).tag(ProgressDisplayMode.barOnly)
                        Text(settings.t("Show Both")).tag(ProgressDisplayMode.both)
                    } label: {
                        Label(settings.t("Progress Display"), systemImage: "info.circle")
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
                } footer: {
                    Text(settings.t("Only one group is loaded at a time to keep browsing smooth."))
                    if settings.deletionMode == .systemTrash {
                        Text(settings.t("Direct deletion asks Photos for confirmation and cannot be undone inside TidyAlbum."))
                    }
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
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
