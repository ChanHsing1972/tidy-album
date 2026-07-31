import Combine
import Foundation

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

// MARK: - Cleaning Preferences

enum DeletionMode: String, CaseIterable, Identifiable {
    case appTrash
    case systemTrash

    var id: String { rawValue }
}

enum PhotoSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case random

    var id: String { rawValue }
}

enum ProgressDisplayMode: String, CaseIterable, Identifiable {
    case textOnly
    case barOnly
    case both

    var id: String { rawValue }
}

// MARK: - Settings Store

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let language = "settings.language"
        static let haptics = "settings.haptics"
        static let deletionMode = "settings.deletionMode"
        static let sortOrder = "settings.sortOrder"
        static let progressDisplay = "settings.progressDisplay"
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    @Published var deletionMode: DeletionMode {
        didSet { defaults.set(deletionMode.rawValue, forKey: Key.deletionMode) }
    }

    @Published var sortOrder: PhotoSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Key.sortOrder) }
    }

    @Published var progressDisplayMode: ProgressDisplayMode {
        didSet { defaults.set(progressDisplayMode.rawValue, forKey: Key.progressDisplay) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .simplifiedChinese
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        deletionMode = DeletionMode(rawValue: defaults.string(forKey: Key.deletionMode) ?? "") ?? .appTrash
        sortOrder = PhotoSortOrder(rawValue: defaults.string(forKey: Key.sortOrder) ?? "") ?? .newestFirst
        progressDisplayMode = ProgressDisplayMode(rawValue: defaults.string(forKey: Key.progressDisplay) ?? "") ?? .both
    }
}
