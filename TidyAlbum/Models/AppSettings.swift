import Combine
import Foundation
import SwiftUI

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

    var locale: Locale {
        switch self {
        case .simplifiedChinese: Locale(identifier: "zh_CN")
        case .english: Locale(identifier: "en_US")
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

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CleaningGroupSize: Int, CaseIterable, Identifiable {
    case develop = 1
    case compact = 25
    case standard = 50
    case large = 100
    case extraLarge = 200

    var id: Int { rawValue }
}

enum AssetInfoDisplayMode: String, CaseIterable, Identifiable {
    case location
    case fileSize
    case fullDate
    case resolution

    var id: String { rawValue }
}

enum DownwardSwipeAction: String, CaseIterable, Identifiable {
    case favorite
    case addToAlbum

    var id: String { rawValue }
}

// MARK: - Settings Store

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let language = "settings.language"
        static let haptics = "settings.haptics"
        static let autoPlayLivePhotos = "settings.autoPlayLivePhotos"
        static let deletionMode = "settings.deletionMode"
        static let sortOrder = "settings.sortOrder"
        static let excludesViewedInRandomMode = "settings.excludesViewedInRandomMode"
        static let progressDisplay = "settings.progressDisplay"
        static let cleaningGroupSize = "settings.cleaningGroupSize"
        static let themeMode = "settings.themeMode"
        static let assetInfoDisplayMode = "settings.assetInfoDisplayMode"
        static let downwardSwipeAction = "settings.downwardSwipeAction"
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    @Published var autoPlayLivePhotos: Bool {
        didSet { defaults.set(autoPlayLivePhotos, forKey: Key.autoPlayLivePhotos) }
    }

    @Published var deletionMode: DeletionMode {
        didSet { defaults.set(deletionMode.rawValue, forKey: Key.deletionMode) }
    }

    @Published var sortOrder: PhotoSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Key.sortOrder) }
    }

    @Published var excludesViewedInRandomMode: Bool {
        didSet { defaults.set(excludesViewedInRandomMode, forKey: Key.excludesViewedInRandomMode) }
    }

    @Published var progressDisplayMode: ProgressDisplayMode {
        didSet { defaults.set(progressDisplayMode.rawValue, forKey: Key.progressDisplay) }
    }

    @Published var cleaningGroupSize: CleaningGroupSize {
        didSet { defaults.set(cleaningGroupSize.rawValue, forKey: Key.cleaningGroupSize) }
    }

    @Published var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Key.themeMode) }
    }

    @Published var assetInfoDisplayMode: AssetInfoDisplayMode {
        didSet { defaults.set(assetInfoDisplayMode.rawValue, forKey: Key.assetInfoDisplayMode) }
    }

    @Published var downwardSwipeAction: DownwardSwipeAction {
        didSet { defaults.set(downwardSwipeAction.rawValue, forKey: Key.downwardSwipeAction) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .simplifiedChinese
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        autoPlayLivePhotos = defaults.object(forKey: Key.autoPlayLivePhotos) as? Bool ?? true
        deletionMode = DeletionMode(rawValue: defaults.string(forKey: Key.deletionMode) ?? "") ?? .appTrash
        sortOrder = PhotoSortOrder(rawValue: defaults.string(forKey: Key.sortOrder) ?? "") ?? .newestFirst
        excludesViewedInRandomMode = defaults.object(forKey: Key.excludesViewedInRandomMode) as? Bool ?? false
        progressDisplayMode = ProgressDisplayMode(rawValue: defaults.string(forKey: Key.progressDisplay) ?? "") ?? .barOnly
        cleaningGroupSize = CleaningGroupSize(rawValue: defaults.integer(forKey: Key.cleaningGroupSize)) ?? .compact
        themeMode = ThemeMode(rawValue: defaults.string(forKey: Key.themeMode) ?? "") ?? .dark
        assetInfoDisplayMode = AssetInfoDisplayMode(rawValue: defaults.string(forKey: Key.assetInfoDisplayMode) ?? "") ?? .location
        downwardSwipeAction = DownwardSwipeAction(
            rawValue: defaults.string(forKey: Key.downwardSwipeAction) ?? ""
        ) ?? .favorite
    }
}
