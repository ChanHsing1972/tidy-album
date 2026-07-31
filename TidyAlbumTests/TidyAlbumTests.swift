//
//  TidyAlbumTests.swift
//  TidyAlbumTests
//
//  Created by 尘心 on 2025/12/23.
//

import Foundation
import Testing
@testable import TidyAlbum

struct TidyAlbumTests {
    @Test @MainActor
    func settingsPersistAcrossStoreInstances() {
        let suiteName = "TidyAlbumTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.language = .english
        settings.hapticsEnabled = false
        settings.deletionMode = .systemTrash
        settings.sortOrder = .random
        settings.progressDisplayMode = .barOnly
        settings.cleaningGroupSize = .extraLarge

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.language == .english)
        #expect(restored.hapticsEnabled == false)
        #expect(restored.deletionMode == .systemTrash)
        #expect(restored.sortOrder == .random)
        #expect(restored.progressDisplayMode == .barOnly)
        #expect(restored.cleaningGroupSize == .extraLarge)
    }

    @Test @MainActor
    func analyticsPersistAcrossStoreInstances() {
        let suiteName = "TidyAlbumTests.analytics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let analytics = AnalyticsStore(defaults: defaults)
        analytics.recordReview()
        analytics.recordReview()

        let restored = AnalyticsStore(defaults: defaults)
        #expect(restored.statistics.reviewedCount == 2)
        #expect(restored.statistics.cleanedCount == 0)
    }
}
