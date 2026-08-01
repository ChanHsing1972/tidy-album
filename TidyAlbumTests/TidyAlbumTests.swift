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
        settings.excludesViewedInRandomMode = true
        settings.progressDisplayMode = .barOnly
        settings.cleaningGroupSize = .extraLarge

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.language == .english)
        #expect(restored.hapticsEnabled == false)
        #expect(restored.deletionMode == .systemTrash)
        #expect(restored.sortOrder == .random)
        #expect(restored.excludesViewedInRandomMode)
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

    @Test @MainActor
    func analyticsResetClearsPersistedHistory() {
        let suiteName = "TidyAlbumTests.analyticsReset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let analytics = AnalyticsStore(defaults: defaults)
        analytics.recordReview()
        analytics.reset()

        let restored = AnalyticsStore(defaults: defaults)
        #expect(analytics.statistics.reviewedCount == 0)
        #expect(restored.statistics.reviewedCount == 0)
    }

    @Test @MainActor
    func fullDateUsesTheSelectedLanguageForWeekdays() {
        let suiteName = "TidyAlbumTests.dates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 10))!
        let settings = SettingsStore(defaults: defaults)

        settings.language = .simplifiedChinese
        #expect(settings.fullDate(friday).contains("星期五"))

        settings.language = .english
        #expect(settings.fullDate(friday).contains("Friday"))
    }

    @Test @MainActor
    func deletionTargetUsesTheFollowingPageFromTheRight() {
        let target = CleaningMotionGeometry.deletionTarget(currentIndex: 1, assetCount: 4)

        #expect(target == CleaningDeletionGeometry(pageIndex: 2, entryEdge: 1))
    }

    @Test @MainActor
    func deletionTargetUsesThePreviousPageFromTheLeftAtTheEnd() {
        let target = CleaningMotionGeometry.deletionTarget(currentIndex: 3, assetCount: 4)

        #expect(target == CleaningDeletionGeometry(pageIndex: 2, entryEdge: -1))
    }

    @Test @MainActor
    func deletingTheOnlyAssetPullsCompletionFromTheLeft() {
        let target = CleaningMotionGeometry.deletionTarget(currentIndex: 0, assetCount: 1)

        #expect(target == CleaningDeletionGeometry(pageIndex: 1, entryEdge: -1))
    }

    @Test @MainActor
    func deletionPullProgressTracksOnlyUpwardMotionAndClamps() {
        #expect(CleaningMotionGeometry.deletionProgress(verticalTranslation: 40, revealDistance: 200) == 0)
        #expect(CleaningMotionGeometry.deletionProgress(verticalTranslation: -50, revealDistance: 200) == 0.25)
        #expect(CleaningMotionGeometry.deletionProgress(verticalTranslation: -300, revealDistance: 200) == 1)
        #expect(CleaningMotionGeometry.incomingOffset(entryEdge: 1, pageWidth: 400, progress: 0.25) == 300)
        #expect(CleaningMotionGeometry.incomingOffset(entryEdge: -1, pageWidth: 400, progress: 1) == 0)
    }
}
